-- imports

local t_pack = table.pack
local t_unpack_orig = table.unpack
local t_insert = table.insert
local str_char = string.char
local str_find = string.find
local str_sub = string.sub
local m_random = math.random
local str_format = string.format
local error = _ENV.error
local rawset = _ENV.rawset
local rawget = _ENV.rawget
local type = _ENV.type
local pcall = _ENV.pcall
local xpcall = _ENV.xpcall
local m_type = math.type
local m_huge = math.huge
local ipairs = _ENV.ipairs
local pairs = _ENV.pairs
local tostring = _ENV.tostring
local tonumber = _ENV.tonumber
local j_encode = json.encode
local j_decode = json.decode
local cor_wrap = coroutine.wrap
local cor_yield = coroutine.yield
local FW_Schedule = _ENV.FW_Schedule
local FW_Pack = _ENV.FW_Pack

local CancelEvent = _ENV.CancelEvent
local TriggerClientEvent = _ENV.TriggerClientEvent
local GetGameTimer = _ENV.GetGameTimer

local Cfx_SetTimeout = Citizen.SetTimeout

local function t_unpack(t, i)
  return t_unpack_orig(t, i or 1, t.n)
end

local function iterator(obj)
  if type(obj) == 'table' then
    return ipairs(obj)
  elseif type(obj) == 'function' then
    return obj()
  end
end

local function error_or_return(status, ...)
  if not status then
    return error(tostring(...))
  end
  return ...
end

-- observers

local retrieve_observed_state, get_observed_state
do
  local observed_state = {}

  retrieve_observed_state = function(player, args)
    if args then
      local state = args.state
      if state then
        local stored = observed_state[player]
        if not stored then
          stored = {}
          observed_state[player] = stored
        end
        for k, v in pairs(state) do
          stored[k] = {GetGameTimer(), v}
        end
      end
    end
  end
  
  get_observed_state = function(player, ...)
    local state = observed_state[player]
    if state then
      return state[j_encode{...}]
    end
  end
  
  function FW_GetObservedStateUpdateTime(...)
    local state = get_observed_state(...)
    if state then
      return GetGameTimer() - state[1]
    end
  end
end

-- callbacks

do
  local callback_info = {}
  
  function FW_CreateCallbackHandler(name, handler)
    local registerer = callback_info[name]
    if not registerer then
      return error("Callback '"..tostring(name).."' was not defined!")
    end
    return registerer(handler)
  end
  
  local function warn_if_registered(name)
    if callback_info[name] then
      return error("Callback '"..tostring(name).."' is already registered!")
    end
  end
  
  local net_callback_handlers = {}
  
  function FW_RegisterCallback(name, eventname, has_source, processor)
    warn_if_registered(name)
    callback_info[name] = function(handler)
      if processor then
        local handler_old = handler
        handler = function(...)
          return handler_old(processor(...))
        end
      end
      AddEventHandler(eventname, function(...)
        local result
        if has_source then
          result = handler(_ENV.source, ...)
        else
          result = handler(...)
        end
        if result == false then
          CancelEvent()
        end
      end)
      return true
    end
  end
  local FW_RegisterCallback = _ENV.FW_RegisterCallback
  
  function FW_RegisterServerCallback(name, eventname, ...)
    RegisterServerEvent(eventname)
    return FW_RegisterCallback(name, eventname, ...)
  end
  
  function FW_RegisterPlainCallback(name)
    warn_if_registered(name)
    callback_info[name] = function()
      return true
    end
  end
  
  function FW_RegisterNetCallback(name, processor)
    warn_if_registered(name)
    callback_info[name] = function(handler)
      if processor then
        local handler_old = handler
        handler = function(...)
          return handler_old(processor(...))
        end
      end
      net_callback_handlers[name] = handler
    end
  end
  
  RegisterNetEvent('fivework:ClientCallbacks')
  AddEventHandler('fivework:ClientCallbacks', function(data)
    local source = _ENV.source
    
    for _, record in ipairs(data) do
      local name, args = t_unpack(record)
      retrieve_observed_state(source, args)
      
      local handler = net_callback_handlers[name]
      if handler then
        local ok, msg = xpcall(handler, FW_Traceback, source, t_unpack(args))
        if not ok then
          FW_ErrorLog("Error in callback "..name..":\n", msg)
        end
      end
    end
  end)
end

-- remote execution

local GetPlayers = _ENV.GetPlayers

function AllPlayers()
  return cor_wrap(function()
    for _, playerid in ipairs(GetPlayers()) do 
      cor_yield(tonumber(playerid) or playerid)
    end
  end)
end

local AllPlayers = _ENV.AllPlayers

local NetworkGetEntityOwner = _ENV.NetworkGetEntityOwner
local NetworkGetNetworkIdFromEntity = _ENV.NetworkGetNetworkIdFromEntity

do
  local player_continuations = {}
  
  local function get_continuations(player)
    local continuations = player_continuations[player]
    if not continuations then
      continuations = {}
      player_continuations[player] = continuations
    end
    return continuations
  end
  
  local function newid()
    local chars = {}
    for i = 1, 32 do
      chars[i] = m_random(33, 126)
    end
    return str_char(t_unpack(chars))
  end
  
  local function newtoken(continuations)
    local token
    repeat
      token = newid()
    until not continuations[token]
    return token
  end
  
  local error_dropped = {}
  
  local function newtask(stack)
    local callbacks = {}
    local result
    local function subscribe(callback)
      if result then
        return callback(t_unpack(result))
      else
        t_insert(callbacks, callback)
      end
    end
    local function complete(ok, ...)
      local ok_result
      if ok == error_dropped then
        ok_result = false
      else
        ok_result = ok
      end
      result = t_pack(ok_result, ...)
      local handled = false
      for _, callback in ipairs(callbacks) do
        callback(ok_result, ...)
        handled = true
      end
      if not handled and not ok then
        stack.error = ...
        error(stack)
      end
      return handled
    end
    return subscribe, complete
  end
  
  local exec_queue = {}
  
  local function remote_exec_function(player, ...)
    local queue = exec_queue[player]
    if not queue then
      queue = {}
      exec_queue[player] = queue
      Cfx_SetTimeout(0, function()
        exec_queue[player] = nil
        TriggerClientEvent('fivework:ExecFunctions', player, queue)
      end)
    end
    t_insert(queue, {...})
  end
  
  local function pack_args(...)
    local args = t_pack(...)
    for i = 1, args.n do
      local v = args[i]
      if type(v) == 'table' then
        args[i] = FW_Pack(v)
      end
    end
    return args
  end
  
  local function player_task_factory(name, transform, stack_level, player, ...)
    local continuations = get_continuations(player)
    local token = newtoken(continuations)
    local stack = stack_level and FW_StackDump(nil, stack_level)
    local subscribe, complete = newtask(stack)
    continuations[token] = function(...)
      continuations[token] = nil
      return complete(...)
    end
    remote_exec_function(player, name, pack_args(...), token)
    return transform(subscribe)
  end
  
  local function player_discard_factory(name, transform, stack_level, player, ...)
    return remote_exec_function(player, name, pack_args(...))
  end
  
  local function group_task_factory(name, transform, stack_level, group, ...)
    local args = pack_args(...)
    local results = {}
    local stack = stack_level and FW_StackDump(nil, stack_level)
    for i, v in iterator(group) do
      local player = v or i
      
      local continuations = get_continuations(player)
      local token = newtoken(continuations)
      local subscribe, complete = newtask(stack)
      continuations[token] = function(...)
        continuations[token] = nil
        return complete(...)
      end
      remote_exec_function(player, name, args, token)
      results[player] = transform(subscribe)
    end
    return results
  end
  
  local function group_discard_factory(name, transform, stack_level, group, ...)
    local args = pack_args(...)
    for i, v in iterator(group) do
      local player = v or i
      remote_exec_function(player, name, args)
    end
  end
  
  local function all_task_factory(name, transform, stack_level, ...)
    return group_task_factory(name, transform, stack_level and stack_level + 1, AllPlayers, ...)
  end
  
  local function all_discard_factory(name, transform, stack_level, ...)
    return group_discard_factory(name, transform, stack_level and stack_level + 1, AllPlayers, ...)
  end
  
  local function owner_task_factory(name, transform, stack_level, entity, ...)
    local player = NetworkGetEntityOwner(entity)
    if not player then return end
    entity = NetworkGetNetworkIdFromEntity(entity)
    return player_task_factory(name..'NetworkIdIn1', transform, stack_level and stack_level + 1, player, entity, ...)
  end
  
  local function owner_discard_factory(name, transform, stack_level, entity, ...)
    local player = NetworkGetEntityOwner(entity)
    if not player then return end
    entity = NetworkGetNetworkIdFromEntity(entity)
    return player_discard_factory(name..'NetworkIdIn1', transform, stack_level and stack_level + 1, player, entity, ...)
  end
  
  RegisterNetEvent('fivework:ExecFunctionResults')
  AddEventHandler('fivework:ExecFunctionResults', function(data)
    local source = _ENV.source
    for _, record in ipairs(data) do
      local status, args, token = t_unpack(record)
      retrieve_observed_state(source, args)
      
      local continuations = player_continuations[source]
      if continuations then
        local handler = continuations[token]
        if handler then
          local ok, msg = xpcall(handler, FW_Traceback, status, t_unpack(args))
          if not ok then
            FW_ErrorLog("Error in asynchronous continuation:\n", msg)
          end
          if not ok or msg then
            status = true
          end
        end
      end
      if not status then
        FW_ErrorLog("Error from unhandled asynchronous call:\n", t_unpack(args))
      end
    end
  end)
  
  AddEventHandler('playerDropped', function(reason)
    local source = _ENV.source
    local continuations = player_continuations[source]
    if continuations then
      for token, handler in pairs(continuations) do
        local ok, msg = xpcall(handler, FW_Traceback, error_dropped, "player dropped: "..tostring(reason))
        if not ok then
          FW_ErrorLog("Error in asynchronous continuation:\n", msg)
        end
      end
      player_continuations[source] = nil
    end
  end)
  
  local function transform_subscribe(subscribe)
    return function()
      return error_or_return(FW_Schedule(subscribe))
    end
  end
  
  local function call_result(factory)
    return function(key)
      return function(...)
        return factory(key, transform_subscribe, nil, ...)()
      end
    end
  end
  
  local function try_call_result(factory)
    return function(key)
      return function(...)
        return pcall(factory(key, transform_subscribe, nil, ...))
      end
    end
  end
  
  local function pass_result(factory)
    return function(key)
      return function(...)
        return factory(key, transform_subscribe, 2, ...)
      end
    end
  end
  
  local func_patterns = {
    ['ForPlayer$'] = pass_result(player_task_factory),
    ['ForPlayerWait$'] = call_result(player_task_factory),
    ['ForPlayerTryWait$'] = try_call_result(player_task_factory),
    ['ForPlayerDiscard$'] = pass_result(player_discard_factory),
    ['ForAll$'] = pass_result(all_task_factory),
    ['ForAllDiscard$'] = pass_result(all_discard_factory),
    ['ForGroup$'] = pass_result(group_task_factory),
    ['ForGroupDiscard$'] = pass_result(group_discard_factory),
    ['ForOwner$'] = pass_result(owner_task_factory),
    ['ForOwnerWait$'] = call_result(owner_task_factory),
    ['ForOwnerTryWait$'] = try_call_result(owner_task_factory),
    ['ForOwnerDiscard$'] = pass_result(owner_discard_factory),
    ['FromPlayer$'] = function(key)
      return function(player, ...)
        local state = get_observed_state(player, key, ...)
        if state then
          return error_or_return(t_unpack(state[2]))
        end
      end
    end
  }
  
  local function find_pattern_function(key)
    for pattern, proc in pairs(func_patterns) do
      local i, j = str_find(key, pattern)
      if i then
        local newkey = str_sub(key, 1, i - 1)..str_sub(key, j + 1)
        local f = proc(newkey)
        if f then
          return f
        end
      end
    end
  end
  
  setmetatable(_ENV, {
    __index = function(self, key)
      if type(key) ~= 'string' then return nil end
      local result = find_pattern_function(key)
      if result then
        rawset(self, key, result)
        return result
      end
    end
  })
end

-- chat utils

do
  local function hexcolor(code)
    local b, g, r = code & 0xFF, (code >> 8) & 0xFF, (code >> 16) & 0xFF
    return {r, g, b}
  end
  
  function SendClientMessage(playerid, color, message)
    message = message or ""
    if type(message) ~= 'table' then
      message = tostring(message)
      if playerid == 0 then
        return print(message)
      end
      message = {message}
    elseif playerid == 0 then
      return print(t_unpack(message))
    end
    if type(color) == 'number' then
      color = hexcolor(color)
    end
    local info = {color = color, multiline = true, args = {t_unpack(message)}}
    for k, v in pairs(message) do
      if type(k) ~= 'number' then
        info[k] = v
      end
    end
    return TriggerClientEvent('chat:addMessage', playerid, info)
  end
  
  local SendClientMessage = _ENV.SendClientMessage
  
  function SendClientMessageToAll(...)
    return SendClientMessage(-1, ...)
  end
  
  local SendClientMessageToAll = _ENV.SendClientMessageToAll
  
  function SendClientMessageFormat(playerid, color, format, ...)
    return SendClientMessage(playerid, color, str_format(format, ...))
  end
  
  function SendClientMessageToAllFormat(color, format, ...)
    return SendClientMessageToAll(color, str_format(format, ...))
  end
end

-- serialization

do
  local special_prefix = '#'
  local literal_infix = '#'
  local json_infix = ':'
  local special_infix = '.'
  local definition_suffix = '='
  local infix_pos = #special_prefix + 1
  
  local function is_special(str)
    return str_sub(str, 1, #special_prefix) == special_prefix
  end
  
  local function needs_transform(t)
    local array, object
    local count = 0
    for k, v in pairs(t) do
      if type(v) == 'table' then
        if needs_transform(v) then
          return true
        end
      elseif type(v) == 'string' then
        if is_special(v) then
          return true
        end
      elseif m_type(v) == 'float' then
        if v ~= v or v == m_huge or v == -m_huge then
          return true
        end
      end
      if m_type(k) == 'integer' and k > 0 then
        if object then
          return true
        end
        count = count + 1
        array = true
      elseif type(k) == 'string' then
        if array or is_special(k) then
          return true
        end
        object = true
      else
        return true
      end
    end
    return count ~= #t
  end
  
  local function transform_table(t, cache)
    if not needs_transform(t) then
      return t
    end
    cache = cache or {}
    local g = cache[t]
    if g then
      return g
    end
    g = {}
    cache[t] = g
    for k, v in pairs(t) do
      if type(v) == 'table' then
        v = transform_table(v, cache)
      elseif type(v) == 'string' and is_special(v) then
        v = special_prefix..literal_infix..v
      elseif m_type(v) == 'float' then
        if v ~= v then
          v = special_prefix..special_infix..'nan'
        elseif v == m_huge then
          v = special_prefix..special_infix..'inf'
        elseif v == -m_huge then
          v = special_prefix..special_infix..'-inf'
        end
      end
      if type(k) ~= 'string' then
        if type(k) == 'table' then
          local k2 = transform_table(k, cache)
          if k ~= k2 then
            for i = 1, m_huge do
              local l = special_prefix..i
              if not g[l] then
                g[special_prefix..i..definition_suffix] = k2
                k = l
                break
              end
            end
          else
            k = special_prefix..json_infix..j_encode(k)
          end
        elseif m_type(k) == 'float' then
          if k ~= k then
            k = special_prefix..special_infix..'nan'
          elseif k == m_huge then
            k = special_prefix..special_infix..'inf'
          elseif k == -m_huge then
            k = special_prefix..special_infix..'-inf'
          else
            k = special_prefix..json_infix..j_encode(k)
          end
        else
          k = special_prefix..json_infix..j_encode(k)
        end
      elseif is_special(k) then
        k = special_prefix..literal_infix..k
      end
      g[k] = v
    end
    return g
  end
  
  local transform_table_back
  
  local special_table = {
    ['nan'] = 0/0,
    ['inf'] = m_huge,
    ['-inf'] = -m_huge
  }
  
  local function transform_value_back(v, t)
    if type(v) == 'table' then
      return transform_table_back(v)
    elseif type(v) == 'string' and is_special(v) then
      if str_sub(v, infix_pos, infix_pos + #json_infix - 1) == json_infix then
        return j_decode(str_sub(v, infix_pos + #json_infix))
      elseif str_sub(v, infix_pos, infix_pos + #literal_infix - 1) == literal_infix then
        return str_sub(v, infix_pos + #literal_infix)
      elseif str_sub(v, infix_pos, infix_pos + #special_infix - 1) == special_infix then
        return special_table[str_sub(v, infix_pos + #special_infix)]
      else
        local def = v..definition_suffix
        return t[def]
      end
    else
      return v
    end
  end
  
  transform_table_back = function(t)
    local g, d
    for k, v in pairs(t) do
      local k2, v2 = transform_value_back(k, t), transform_value_back(v, t)
      if k ~= k2 then
        d = d or {}
        d[k] = true
        if k2 then
          g = g or {}
          g[k2] = v2
        end
      elseif v ~= v2 then
        t[k] = v2
      end
    end
    if d then
      for k in pairs(d) do
        t[k] = nil
      end
    end
    if g then
      for k, v in pairs(g) do
        t[k] = v
      end
    end
    return t
  end
  
  local SaveResourceFile = _ENV.SaveResourceFile
  local LoadResourceFile = _ENV.LoadResourceFile
  
  function SaveResourceData(name, file, ...)
    data = j_encode(transform_table(t_pack(...)))
    if not data or data == '' then
      return error('invalid data returned from json.encode')
    end
    return SaveResourceFile(name, file, data, #data)
  end
  
  function LoadResourceData(name, file)
    local data = LoadResourceFile(name, file)
    if data and data ~= '' then
      local obj = j_decode(data)
      if not obj then
        return error('invalid data encountered in file '..name..":\n"..data)
      end
      return t_unpack(transform_table_back(obj))
    end
  end
  
  local GetCurrentResourceName = _ENV.GetCurrentResourceName
  
  function SaveScriptData(...)
    return SaveResourceData(GetCurrentResourceName(), ...)
  end
  
  function LoadScriptData(...)
    return LoadResourceData(GetCurrentResourceName(), ...)
  end
end

-- misc

local GetNumPlayerIdentifiers = _ENV.GetNumPlayerIdentifiers
local GetPlayerIdentifier = _ENV.GetPlayerIdentifier

function PlayerIdentifiers(player)
  return cor_wrap(function()
    local num = GetNumPlayerIdentifiers(player)
    for i = 0, num-1 do
      local id = GetPlayerIdentifier(player, i)
      if id then
        local i, j = str_find(id, ':')
        if i then
          cor_yield(str_sub(id, 1, i - 1), str_sub(id, j + 1))
        end
      end
    end
  end)
end

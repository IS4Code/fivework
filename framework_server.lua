-- imports

local t_pack = table.pack
local t_unpack_orig = table.unpack
local str_char = string.char
local str_find = string.find
local str_sub = string.sub
local m_random = math.random
local cor_yield = coroutine.yield
local str_format = string.format
local error = _ENV.error
local rawset = _ENV.rawset
local rawget = _ENV.rawget
local type = _ENV.type
local m_type = math.type
local m_huge = math.huge
local ipairs = _ENV.ipairs
local pairs = _ENV.pairs
local tostring = _ENV.tostring
local j_encode = json.encode
local j_decode = json.decode
local cor_wrap = coroutine.wrap
local cor_yield = coroutine.yield

local CancelEvent = _ENV.CancelEvent
local TriggerClientEvent = _ENV.TriggerClientEvent

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

-- internal

do
  local callback_info = {}
  
  function FW_CreateCallbackHandler(name, handler)
    return callback_info[name](handler)
  end
  
  local net_callback_handlers = {}
  
-- callback configuration
  
  function FW_RegisterCallback(name, eventname, has_source, processor)
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
    callback_info[name] = function()
      return true
    end
  end
  
  function FW_RegisterNetCallback(name, processor)
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
  
  RegisterNetEvent('fivework:ClientCallback')
  AddEventHandler('fivework:ClientCallback', function(name, args)
    local handler = net_callback_handlers[name]
    if handler then
      return handler(_ENV.source, t_unpack(args))
    end
  end)
end

-- remote execution

local NetworkGetEntityOwner = _ENV.NetworkGetEntityOwner
local NetworkGetNetworkIdFromEntity = _ENV.NetworkGetNetworkIdFromEntity

do
  local continuations = {}
  
  local function newid()
    local chars = {}
    for i = 1, 32 do
      chars[i] = m_random(33, 126)
    end
    return str_char(t_unpack(chars))
  end
  
  local function newtoken()
    local token
    repeat
      token = newid()
    until not continuations[token]
    return token
  end
  
  local function player_scheduler_factory(name)
    return function(callback, player, ...)
      local token = newtoken()
      continuations[token] = function(...)
        continuations[token] = nil
        return callback(...)
      end
      TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(...), token)
    end
  end
  
  local function player_scheduler_factory_no_wait(name)
    return function(callback, player, ...)
      return callback(true, TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(...), nil))
    end
  end
  
  local function all_scheduler_factory(name)
    return function(callback, ...)
      return callback(true, TriggerClientEvent('fivework:ExecFunction', -1, name, t_pack(...), nil))
    end
  end
  
  local function owner_scheduler_factory(name)
    name = name..'NetworkIdIn1'
    return function(callback, entity, ...)
      local player = NetworkGetEntityOwner(entity)
      if not player then return callback(false) end
      entity = NetworkGetNetworkIdFromEntity(entity)
      local token = newtoken()
      continuations[token] = function(...)
        continuations[token] = nil
        return callback(...)
      end
      TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(entity, ...), token)
    end
  end
  
  local function owner_scheduler_factory_no_wait(name)
    name = name..'NetworkedArgument'
    return function(callback, entity, ...)
      local player = NetworkGetEntityOwner(entity)
      if not player then return callback(false) end
      entity = NetworkGetNetworkIdFromEntity(entity)
      return callback(true, TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(entity, ...), nil))
    end
  end
  
  local function group_scheduler_factory(name)
    return function(callback, group, ...)
      local args = t_pack(...)
      for i, v in iterator(group) do
        TriggerClientEvent('fivework:ExecFunction', v, name, args, nil)
      end
      return callback(true)
    end
  end
  
  RegisterNetEvent('fivework:ExecFunctionResult')
  AddEventHandler('fivework:ExecFunctionResult', function(status, args, token)
    local handler = continuations[token]
    if handler then
      return handler(status, t_unpack(args))
    elseif not status then
      error(t_unpack(args))
    end
  end)
  
  local function handle_result(status, ...)
    if not status then
      error(...)
    end
    return ...
  end
  
  local function for_func(scheduler_factory)
    return function(key)
      local scheduler = scheduler_factory(key)
      if scheduler then
        return function(...)
          return handle_result(cor_yield(scheduler, ...))
        end
      end
    end
  end
  
  local func_patterns = {
    ['ForPlayer$'] = for_func(player_scheduler_factory),
    ['ForPlayerNoWait$'] = for_func(player_scheduler_factory_no_wait),
    ['ForAll$'] = for_func(all_scheduler_factory),
    ['ForGroup$'] = for_func(group_scheduler_factory),
    ['ForOwner$'] = for_func(owner_scheduler_factory),
    ['ForOwnerNoWait$'] = for_func(owner_scheduler_factory_no_wait)
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
    return SaveResourceFile(name, file, data, #data)
  end
  
  function LoadResourceData(name, file)
    local data = LoadResourceFile(name, file)
    return t_unpack(transform_table_back(j_decode(data)))
  end
  
  local GetCurrentResourceName = _ENV.GetCurrentResourceName
  
  function SaveScriptData(...)
    return SaveResourceData(GetCurrentResourceName(), ...)
  end
  
  function LoadScriptData(...)
    return LoadResourceData(GetCurrentResourceName(), ...)
  end
end

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

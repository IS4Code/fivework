-- imports

local pcall = _ENV.pcall
local pairs = _ENV.pairs
local ipairs = _ENV.ipairs
local next = _ENV.next
local tostring = _ENV.tostring
local tonumber = _ENV.tonumber
local load = _ENV.load
local type = _ENV.type
local error = _ENV.error
local assert = _ENV.assert
local rawset = _ENV.rawset
local select = _ENV.select
local m_type = math.type
local t_pack = table.pack
local t_unpack_orig = table.unpack
local t_concat = table.concat
local t_insert = table.insert
local cor_yield = coroutine.yield
local str_find = string.find
local str_sub = string.sub
local str_gsub = string.gsub
local str_byte = string.byte
local str_format = string.format
local str_rep = string.rep
local j_encode = json.encode

local TriggerServerEvent = _ENV.TriggerServerEvent
local NetworkGetNetworkIdFromEntity = _ENV.NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = _ENV.NetworkGetEntityFromNetworkId
local GetGameTimer = _ENV.GetGameTimer
local GetTimeDifference = _ENV.GetTimeDifference
local GetTimeOffset = _ENV.GetTimeOffset
local IsTimeMoreThan = _ENV.IsTimeMoreThan
local Cfx_Wait = Citizen.Wait
local Cfx_CreateThread = Citizen.CreateThread
local CancelEvent = _ENV.CancelEvent
local GetHashKey = _ENV.GetHashKey

local FW_Async = _ENV.FW_Async

local function t_unpack(t, i)
  return t_unpack_orig(t, i or 1, t.n)
end

do
  local function char_replacer(c)
    if str_sub(c, -1) ~= ' ' then
      return str_rep('\t', #c - 1)..str_format('%%%02x', str_byte(c, -1))
    end
    return str_rep('\t', #c)
  end
  
  function GetStringHash(text)
    return GetHashKey(str_gsub(text, ' *[%% \tA-Z]', char_replacer))
  end
end
local GetStringHash = _ENV.GetStringHash

-- internal

do
  local callback_info = {}
  
  function FW_CreateCallbackHandler(name, handler)
    return callback_info[name](handler)
  end
  
-- callback configuration
  
  function FW_RegisterCallback(name, eventname, cancellable, processor)
    callback_info[name] = function(handler)
      if processor then
        local handler_old = handler
        handler = function(...)
          return handler_old(processor(...))
        end
      end
      AddEventHandler(eventname, function(...)
        local result = handler(...)
        if cancellable and result == false then
          CancelEvent()
        end
      end)
      return true
    end
  end
  
  function FW_RegisterPlainCallback(name)
    callback_info[name] = function()
      return true
    end
  end
end

function FW_RegisterNetCallback(name, eventname, processor)
  return AddEventHandler(eventname, function(...)
    local args
    if processor then
      args = t_pack(processor(...))
    else
      args = t_pack(...)
    end
    return TriggerServerEvent('fivework:ClientCallback', name, args)
  end)
end

function FW_TriggerNetCallback(name, ...)
  return TriggerServerEvent('fivework:ClientCallback', name, t_pack(...))
end
local FW_TriggerNetCallback = _ENV.FW_TriggerNetCallback

-- frame handlers

local frame_func_handlers = {}

Cfx_CreateThread(function()
  while true do
    for key, info in pairs(frame_func_handlers) do
      local f, timeout, args = info[1], info[2], info[3] 
      if timeout == true then
        pcall(f, t_unpack(args))
      elseif IsTimeMoreThan(GetGameTimer(), timeout) then
        frame_func_handlers[key] = nil
      else
        pcall(f, t_unpack(args))
      end
    end
    Cfx_Wait(0)
  end
end)

local function pack_frame_args(f, enable, ...)
  if enable then
    if type(enable) == 'number' then
      return {f, GetTimeOffset(GetGameTimer(), enable), t_pack(...)}
    elseif enable == true then
      return {f, true, t_pack(...)}
    else
      return {f, true, t_pack(enable, ...)}
    end
  end
end

-- remote execution

do
  local function replace_network_id_1(a, ...)
    a = NetworkGetNetworkIdFromEntity(a)
    return a, ...
  end
  
  local function replace_network_id_2(a, b, ...)
    b = NetworkGetNetworkIdFromEntity(b)
    return a, b, ...
  end
  
  local function replace_network_id_3(a, b, c, ...)
    c = NetworkGetNetworkIdFromEntity(c)
    return a, b, c, ...
  end
  
  local function shift_2(a, b, ...)
    return b, a, ...
  end
  
  local function shift_3(a, b, c, ...)
    return c, a, b, ...
  end
  
  local find_func
  
  local func_patterns = {
    ['NetworkIdIn(%d+)$'] = function(name, pos)
      local f = find_func(name)
      if type(f) == 'function' then
        pos = tonumber(pos)
        if pos == 0 then
          return f
        elseif pos == 1 then
          return function(a, ...)
            a = NetworkGetEntityFromNetworkId(a)
            return f(a, ...)
          end
        elseif pos == 2 then
          return function(a, b, ...)
            b = NetworkGetEntityFromNetworkId(b)
            return f(a, b, ...)
          end
        elseif pos == 3 then
          return function(a, b, c, ...)
            c = NetworkGetEntityFromNetworkId(c)
            return f(a, b, c, ...)
          end
        else
          return function(...)
            local t = t_pack(...)
            t[pos] = NetworkGetEntityFromNetworkId(t[pos])
            return f(t_unpack(t))
          end
        end
      end
    end,
    ['NetworkIdOut(%d+)$'] = function(name, pos)
      local f = find_func(name)
      if type(f) == 'function' then
        pos = tonumber(pos)
        if pos == 0 then
          return f
        elseif pos == 1 then
          return function(...)
            return replace_network_id_1(f(...))
          end
        elseif pos == 2 then
          return function(...)
            return replace_network_id_2(f(...))
          end
        elseif pos == 3 then
          return function(...)
            return replace_network_id_3(f(...))
          end
        else
          return function(...)
            local t = t_pack(f(...))
            t[pos] = NetworkGetNetworkIdFromEntity(t[pos])
            return t_unpack(t)
          end
        end
      end
    end,
    ['AtIndex$'] = function(name)
      local f = find_func(name..'ThisFrame')
      if type(f) == 'function' then
        return function(key, ...)
          frame_func_handlers[key] = pack_frame_args(f, ...)
          return key
        end
      end
    end,
    ['ShiftIn(%d+)$'] = function(name, shift)
      local f = find_func(name)
      if type(f) == 'function' then
        shift = tonumber(shift)
        if shift <= 1 then
          return f
        elseif shift == 2 then
          return function(a, b, ...)
            return f(b, a, ...)
          end
        elseif shift == 3 then
          return function(a, b, c, ...)
            return f(c, a, b, ...)
          end
        else
          return function(...)
            local t = t_pack(...)
            for i = shift, 2, -1 do
              local old = t[i]
              t[i] = t[i-1]
              t[i-1] = old
            end
            return f(t_unpack(t))
          end
        end
      end
    end,
    ['ShiftOut(%d+)$'] = function(name, shift)
      local f = find_func(name)
      if type(f) == 'function' then
        shift = tonumber(shift)
        if shift <= 1 then
          return f
        elseif shift == 2 then
          return function(...)
            return shift_2(f(...))
          end
        elseif shift == 3 then
          return function(...)
            return shift_3(f(...))
          end
        else
          return function(...)
            local t = t_pack(f(...))
            for i = shift, 2, -1 do
              local old = t[i]
              t[i] = t[i-1]
              t[i-1] = old
            end
            return t_unpack(t)
          end
        end
      end
    end
  }
  
  local function find_script_var(key)
    if key == '_G' then
      return _ENV
    elseif key ~= 'debug' then
      return find_func(key)
    end
  end
  
  local script_environment = setmetatable({}, {
    __index = function(self, key)
      local value = find_script_var(key)
      rawset(self, key, value)
      return value
    end,
    __newindex = function(self, key, value)
      if find_script_var(key) then
        return error("'"..key.."' cannot be redefined")
      end
      return rawset(self, key, value)
    end
  })
  
  local do_script
  do
    local script_cache = {}
    
    do_script = function(chunk, ...)
      local hash = GetStringHash(chunk)
      local script = script_cache[hash]
      if not script then
        script = assert(load(chunk, '=(load)', nil, script_environment))
        script_cache[hash] = script
      end
      return script(...)
    end
  end
  
  local function match_result(name, proc, i, j, ...)
    if i then
      local newname = str_sub(name, 1, i - 1)..str_sub(name, j + 1)
      return proc(newname, ...)
    end
  end
  
  find_func = function(name)
    if name == 'DoScript' then
      return do_script
    elseif name == 'rawset' or name == 'rawget' then
      return nil
    end
    local f = _ENV[name]
    if f then
      return f
    end
    if not str_find(name, 'ThisFrame$') then
      f = find_func(name .. 'ThisFrame')
      if type(f) == 'function' then
        return function(...)
          frame_func_handlers[f] = pack_frame_args(f, ...)
        end
      end
    end
    for pattern, proc in pairs(func_patterns) do
      f = match_result(name, proc, str_find(name, pattern))
      if f then
        return f
      end
    end
  end
  
  local function process_call(token, status, ...)
    if token or not status then
      return TriggerServerEvent('fivework:ExecFunctionResult', status, t_pack(...), token)
    end
  end
  
  local function remote_call(name, token, args)
    return process_call(token, pcall(script_environment[name], t_unpack(args)))
  end
  
  RegisterNetEvent('fivework:ExecFunction')
  AddEventHandler('fivework:ExecFunction', function(name, args, token)
    return FW_Async(remote_call, name, token, args)
  end)
end  

-- in-game loading

local IsModelValid = _ENV.IsModelValid
local RequestModel = _ENV.RequestModel
local HasModelLoaded = _ENV.HasModelLoaded
local SetModelAsNoLongerNeeded = _ENV.SetModelAsNoLongerNeeded
local DoesEntityExist = _ENV.DoesEntityExist
local RequestCollisionAtCoord = _ENV.RequestCollisionAtCoord
local HasCollisionLoadedAroundEntity = _ENV.HasCollisionLoadedAroundEntity

do
  local function model_scheduler(callback, hash, timeout)
    return Cfx_CreateThread(function()
    	RequestModel(hash)
      local time = GetGameTimer()
    	while not HasModelLoaded(hash) do
    		RequestModel(hash)
    		Cfx_Wait(0)
        if timeout and timeout >= 0 then
          local diff = GetTimeDifference(GetGameTimer(), time)
          if diff > timeout then
            return callback(false)
          end
        end
    	end
      callback(true)
      SetModelAsNoLongerNeeded(hash)
    end)
  end
  
  function LoadModel(hash, ...)
    if not IsModelValid(hash) then return false end
    return HasModelLoaded(hash) or cor_yield(model_scheduler, hash, ...)
  end
end

do
  local function collision_scheduler(callback, entity, x, y, z, timeout)
    return Cfx_CreateThread(function()
      RequestCollisionAtCoord(x, y, z)
      local time = GetGameTimer()
      while not HasCollisionLoadedAroundEntity(entity) do
        RequestCollisionAtCoord(x, y, z)
        Cfx_Wait(0)
        if timeout and timeout >= 0 then
          local diff = GetTimeDifference(GetGameTimer(), time)
          if diff > timeout then
            return callback(false)
          end
        end
      end
      return callback(true)
    end)
  end
  
  function LoadCollisionAroundEntity(entity, ...)
    if not DoesEntityExist(entity) then return false end
    return HasCollisionLoadedAroundEntity(entity) or cor_yield(collision_scheduler, entity, ...)
  end
end

-- text drawing

local AddTextEntry = _ENV.AddTextEntry
local GetLabelText = _ENV.GetLabelText

do
  local text_cache = {}
  
  function GetStringEntry(text)
    if type(text) == 'table' then
      if #text == 1 then
        return text[1]
      end
      local labels = {}
      for i, label in ipairs(text) do
        labels[i] = GetLabelText(label)
      end
      return GetStringEntry(t_concat(labels, text.sep))
    end
    local textkey = text_cache[text]
    if not textkey then
      local texthash = GetStringHash(text)
      textkey = 'FW_TEXT_'..str_sub(str_format('%08x', texthash), -8)
      AddTextEntry(textkey, text)
      text_cache[text] = textkey
    end
    return textkey
  end
end
local GetStringEntry = _ENV.GetStringEntry

local AddTextComponentSubstringPlayerName = _ENV.AddTextComponentSubstringPlayerName
local AddTextComponentInteger = _ENV.AddTextComponentInteger
local AddTextComponentFormattedInteger = _ENV.AddTextComponentFormattedInteger
local AddTextComponentFloat = _ENV.AddTextComponentFloat

do
  local function unpack_cond(value)
    if type(value) == 'table' then
      return t_unpack(value)
    else
      return value
    end
  end
  
  local function parse_text_data(data)
    for field, value in pairs(data) do
      if type(field) == 'string' then
        if field == 'Components' then
          for i, component in ipairs(value) do
            if type(component) ~= 'table' then
              component = {component}
            end
            local primary = component[1]
            if primary == nil then
              local ctype, cvalue = next(component)
              if ctype then
                _ENV['AddTextComponentSubstring'..ctype](unpack_cond(cvalue))
              end
            elseif type(primary) == 'string' then
              AddTextComponentSubstringPlayerName(t_unpack(component))
            elseif m_type(primary) == 'integer' then
              if component[2] ~= nil then
                AddTextComponentFormattedInteger(t_unpack(component))
              else
                AddTextComponentInteger(t_unpack(component))
              end
            elseif m_type(primary) == 'float' then
              AddTextComponentFloat(t_unpack(component))
            else
              AddTextComponentSubstringPlayerName(tostring(primary))
            end
          end
        else
          _ENV['SetText'..field](unpack_cond(value))
        end
      end
    end
  end
  
  local function text_formatter(beginFunc, endFunc)
    return function(text, data, ...)
      local textkey = GetStringEntry(text)
      beginFunc(textkey)
      if data then
        for i, data_inner in ipairs(data) do
          parse_text_data(data_inner)
        end
        parse_text_data(data)
      end
      return endFunc(...)
    end
  end
  
  DisplayTextThisFrame = text_formatter(BeginTextCommandDisplayText, EndTextCommandDisplayText)
  DisplayText = nil
  DisplayHelp = text_formatter(BeginTextCommandDisplayHelp, EndTextCommandDisplayHelp)
  ThefeedPostTicker = text_formatter(BeginTextCommandThefeedPost, EndTextCommandThefeedPostTicker)
end

-- keys

local IsControlJustPressed = _ENV.IsControlJustPressed
local IsControlJustReleased = _ENV.IsControlJustReleased

do
  local registered_controls = {}
  
  local function control_key(controller, key)
    if not key then
      controller, key = 0, controller
    end
    local data = {controller, key}
    return j_encode(data), data
  end
  
  function FW_RegisterControlKey(controller, key)
    local index, data = control_key(controller, key)
    registered_controls[index] = data
  end
  
  function FW_UnregisterControlKey(controller, key)
    local index = control_key(controller, key)
    registered_controls[index] = nil
  end
  
  function FW_IsControlKeyRegistered(controller, key)
    local index = control_key(controller, key)
    return registered_controls[index] ~= nil
  end
  
  Cfx_CreateThread(function()
    while true do
      local pressed = {}
      local released = {}
      for k, info in pairs(registered_controls) do
        if IsControlJustPressed(t_unpack(info)) then
          pressed[info[2]] = info[1]
        end
        if IsControlJustReleased(t_unpack(info)) then
          released[info[2]] = info[1]
        end
      end
      if next(pressed) or next(released) then
        FW_TriggerNetCallback('OnPlayerKeyStateChange', pressed, released)
      end
      Cfx_Wait(0)
    end
  end)
end

do
  local registered_updates = {}
  local interval = 0
  
  local function update_key(...)
    return j_encode(t_pack(...))
  end
  
  function FW_RegisterUpdate(fname, ...)
    local func = _ENV[fname]
    local value = func and func(...)
    registered_updates[update_key(fname, ...)] = t_pack(value, fname, ...)
  end
  
  function FW_UnregisterUpdate(...)
    registered_updates[update_key(...)] = nil
  end
  
  function FW_IsUpdateRegistered(...)
    return registered_updates[update_key(...)] ~= nil
  end
  
  function FW_SetUpdateInterval(newinterval)
    interval = newinterval
  end
  
  function FW_GetUpdateInterval()
    return interval
  end
  
  Cfx_CreateThread(function()
    while true do
      local updates = {}
      for k, info in pairs(registered_updates) do
        local func = _ENV[info[2]]
        if func then
          local newvalue = func(t_unpack(info, 3))
          local oldvalue = info[1]
          if oldvalue ~= newvalue then
            info[1] = newvalue
            updates[t_pack(t_unpack(info, 2))] = {newvalue, oldvalue}
          end
        end
      end
      if next(updates) then
        FW_TriggerNetCallback('OnPlayerUpdate', updates)
      end
      Cfx_Wait(interval)
    end
  end)
end

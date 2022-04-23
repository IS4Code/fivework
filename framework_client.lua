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
local setmetatable = _ENV.setmetatable
local m_type = math.type
local m_huge = math.huge
local t_pack = table.pack
local t_unpack_orig = table.unpack
local t_concat = table.concat
local t_insert = table.insert
local cor_yield = coroutine.yield
local str_find = string.find
local str_sub = string.sub
local str_gsub = string.gsub
local str_gmatch = string.gmatch
local str_byte = string.byte
local str_format = string.format
local str_rep = string.rep
local str_upper = string.upper
local j_encode = json.encode
local cor_wrap = coroutine.wrap
local cor_yield = coroutine.yield
local Vdist = _ENV.Vdist

local TriggerServerEvent = _ENV.TriggerServerEvent
local NetworkGetNetworkIdFromEntity = _ENV.NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = _ENV.NetworkGetEntityFromNetworkId
local NetworkDoesNetworkIdExist = _ENV.NetworkDoesNetworkIdExist
local DoesEntityExist = _ENV.DoesEntityExist
local GetGameTimer = _ENV.GetGameTimer
local GetTimeDifference = _ENV.GetTimeDifference
local GetTimeOffset = _ENV.GetTimeOffset
local IsTimeMoreThan = _ENV.IsTimeMoreThan
local Cfx_Wait = Citizen.Wait
local Cfx_CreateThread = Citizen.CreateThread
local CancelEvent = _ENV.CancelEvent
local GetHashKey = _ENV.GetHashKey
local PlayerId = _ENV.PlayerId
local PlayerPedId = _ENV.PlayerPedId

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

local function unpack_cond(value)
  if type(value) == 'table' then
    return t_unpack(value)
  else
    return value
  end
end

local function get_property_key(field)
  if type(field) == 'string' and field ~= 'n' then
    return field
  elseif type(field) == 'table' then
    return get_property_key(field[1])
  end
end

-- remote execution

local script_environment

-- observers

local observe_state
do
  local observers = {}
  
  local observe_value
  
  local function set_state(state, name, cache, ...)
    local data = t_pack(pcall(script_environment[name], ...))
    state[j_encode{name, ...}] = data
    for i = 2, data.n do
      observe_value(state, data[i], cache)
    end
  end
  
  local function validate(arg, validator)
    if validator then
      if type(validator) == 'boolean' then
        return true
      elseif type(validator) == 'table' then
        return validator[arg]
      elseif type(validator) == 'function' then
        local status, result = pcall(validator, arg)
        return status and result
      end
    end
  end
  
  observe_value = function(state, arg, cache)
    if arg == nil or arg ~= arg or cache[arg] then
      return
    end
    cache[arg] = true
    
    for key, v in pairs(observers) do
      if validate(arg, v[2]) then
        set_state(state, v[1], cache, arg, t_unpack(v, 3))
      end
    end
    
    if type(arg) == 'table' then
      for k, v in pairs(arg) do
        observe_value(state, k, cache)
        observe_value(state, v, cache)
      end
    end
  end
  
  observe_state = function(args)
    local cache = {}
    
    local state = {}
    for key, v in pairs(observers) do 
      if v[2] == nil then
        set_state(state, v[1], cache, t_unpack(v, 3))
      end
    end
    
    for i = 1, args.n do
      observe_value(state, args[i], cache)
    end
    
    if next(state) then
      args.state = state
    end
    return args
  end
  
  function FW_RegisterObserver(name, validator, ...)
    if type(validator) == 'string' then
      validator = assert(script_environment[validator], 'variable not found')
    end
    observers[j_encode{name, ...}] = t_pack(name, validator, ...)
  end
  
  function FW_UnregisterObserver(name, ...)
    observers[j_encode{name, ...}] = nil
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
  
  function FW_RegisterCallback(name, eventname, processor)
    warn_if_registered(name)
    callback_info[name] = function(handler)
      if processor then
        local handler_old = handler
        handler = function(...)
          return handler_old(processor(...))
        end
      end
      AddEventHandler(eventname, function(...)
        local result = handler(...)
        if result == false then
          CancelEvent()
        end
      end)
      return true
    end
  end
  
  function FW_RegisterPlainCallback(name)
    warn_if_registered(name)
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
    return TriggerServerEvent('fivework:ClientCallback', name, observe_state(args))
  end)
end

function FW_TriggerNetCallback(name, ...)
  return TriggerServerEvent('fivework:ClientCallback', name, observe_state(t_pack(...)))
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
  local function entity_from_network_id(id)
    if NetworkDoesNetworkIdExist(id) then
      return NetworkGetEntityFromNetworkId(id) 
    else
      return nil
    end
  end
  
  local function network_id_from_entity(id)
    if DoesEntityExist(id) then
      return NetworkGetNetworkIdFromEntity(id) 
    else
      return nil
    end
  end
  
  local function replace_network_id_1(a, ...)
    a = network_id_from_entity(a)
    return a, ...
  end
  
  local function replace_network_id_2(a, b, ...)
    b = network_id_from_entity(b)
    return a, b, ...
  end
  
  local function replace_network_id_3(a, b, c, ...)
    c = network_id_from_entity(c)
    return a, b, c, ...
  end
  
  local function shift_2(a, b, ...)
    return b, a, ...
  end
  
  local function shift_3(a, b, c, ...)
    return c, a, b, ...
  end
  
  local find_func, cache_script
    
  local function do_script(chunk, ...)
    local script = cache_script(chunk)
    return script(...)
  end
  
  local function try_cache_script(chunk)
    if chunk then
      local status, script = pcall(cache_script, chunk)
      if status then
        return script
      end
    end
    return chunk
  end
  
  local func_patterns = {
    ['NetworkIdIn(%d+)$'] = function(name, pos)
      local f, f_inner = find_func(name)
      if type(f) == 'function' then
        pos = tonumber(pos)
        if pos == 0 then
          return f, f_inner
        elseif pos == 1 then
          return function(a, ...)
            a = entity_from_network_id(a)
            return f(a, ...)
          end, f_inner
        elseif pos == 2 then
          return function(a, b, ...)
            b = entity_from_network_id(b)
            return f(a, b, ...)
          end, f_inner
        elseif pos == 3 then
          return function(a, b, c, ...)
            c = entity_from_network_id(c)
            return f(a, b, c, ...)
          end, f_inner
        else
          return function(...)
            local t = t_pack(...)
            t[pos] = entity_from_network_id(t[pos])
            return f(t_unpack(t))
          end, f_inner
        end
      end
    end,
    ['NetworkIdOut(%d+)$'] = function(name, pos)
      local f, f_inner = find_func(name)
      if type(f) == 'function' then
        pos = tonumber(pos)
        if pos == 0 then
          return f, f_inner
        elseif pos == 1 then
          return function(...)
            return replace_network_id_1(f(...))
          end, f_inner
        elseif pos == 2 then
          return function(...)
            return replace_network_id_2(f(...))
          end, f_inner
        elseif pos == 3 then
          return function(...)
            return replace_network_id_3(f(...))
          end, f_inner
        else
          return function(...)
            local t = t_pack(f(...))
            t[pos] = network_id_from_entity(t[pos])
            return t_unpack(t)
          end, f_inner
        end
      end
    end,
    ['EachFrame$'] = function(name)
      local f, f_inner = find_func(name..'ThisFrame')
      if not f then
        f, f_inner = find_func(name)
      end
      if type(f) == 'function' then
        if f == do_script then
          return function(timeout, chunk, ...)
            frame_func_handlers[do_script] = pack_frame_args(do_script, timeout, try_cache_script(chunk), ...)
          end, f_inner
        end
        
        return function(...)
          frame_func_handlers[f] = pack_frame_args(f, ...)
        end, f_inner
      end
    end,
    ['Named$'] = function(name)
      local f, f_inner = find_func(name..'ThisFrame')
      if type(f) == 'function' then
        return function(key, ...)
          frame_func_handlers[key] = pack_frame_args(f, ...)
          return key
        end, f_inner
      end
    end,
    ['EachFrameNamed$'] = function(name)
      local f, f_inner = find_func(name..'ThisFrame')
      if not f then
        f, f_inner = find_func(name)
      end
      if type(f) == 'function' then
        if f == do_script then
          return function(key, timeout, chunk, ...)
            frame_func_handlers[key] = pack_frame_args(do_script, timeout, try_cache_script(chunk), ...)
          end, f_inner
        end
        
        return function(key, ...)
          frame_func_handlers[key] = pack_frame_args(f, ...)
          return key
        end, f_inner
      end
    end,
    ['ShiftIn(%d+)$'] = function(name, shift)
      local f, f_inner = find_func(name)
      if type(f) == 'function' then
        shift = tonumber(shift)
        if shift <= 1 then
          return f, f_inner
        elseif shift == 2 then
          return function(a, b, ...)
            return f(b, a, ...)
          end, f_inner
        elseif shift == 3 then
          return function(a, b, c, ...)
            return f(c, a, b, ...)
          end, f_inner
        else
          return function(...)
            local t = t_pack(...)
            for i = shift, 2, -1 do
              local old = t[i]
              t[i] = t[i-1]
              t[i-1] = old
            end
            return f(t_unpack(t))
          end, f_inner
        end
      end
    end,
    ['ShiftOut(%d+)$'] = function(name, shift)
      local f, f_inner = find_func(name)
      if type(f) == 'function' then
        shift = tonumber(shift)
        if shift <= 1 then
          return f, f_inner
        elseif shift == 2 then
          return function(...)
            return shift_2(f(...))
          end, f_inner
        elseif shift == 3 then
          return function(...)
            return shift_3(f(...))
          end, f_inner
        else
          return function(...)
            local t = t_pack(f(...))
            for i = shift, 2, -1 do
              local old = t[i]
              t[i] = t[i-1]
              t[i-1] = old
            end
            return t_unpack(t)
          end, f_inner
        end
      end
    end,
    ['Self$'] = function(name)
      local f, f_inner = find_func(name)
      if type(f) == 'function' then
        return function(...)
          return f(PlayerId(), ...)
        end, f_inner
      end
    end,
    ['SelfPed$'] = function(name)
      local f, f_inner = find_func(name)
      if type(f) == 'function' then
        return function(...)
          return f(PlayerPedId(), ...)
        end, f_inner
      end
    end,
    ['PropertiesOf(%d+)$'] = function(name, initial)
      initial = tonumber(initial) or 1
      if initial == 0 then
        return function(...)
          local args = t_pack(...)
          for i = 1, args.n do
            local data = args[i]
            if data then
              for field, value in pairs(data) do
                local key = get_property_key(field)
                if key then
                  _ENV[name..key](unpack_cond(value))
                end
              end
            end
          end
        end
      elseif initial == 1 then
        return function(target, ...)
          local args = t_pack(...)
          for i = 1, args.n do
            local data = args[i]
            if data then
              for field, value in pairs(data) do
                local key = get_property_key(field)
                if key then
                  _ENV[name..key](target, unpack_cond(value))
                end
              end
            end
          end
        end
      elseif initial == 2 then
        return function(target1, target2, ...)
          local args = t_pack(...)
          for i = 1, args.n do
            local data = args[i]
            if data then
              for field, value in pairs(data) do
                local key = get_property_key(field)
                if key then
                  _ENV[name..key](target1, target2, unpack_cond(value))
                end
              end
            end
          end
        end
      elseif initial == 3 then
        return function(target1, target2, target3, ...)
          local args = t_pack(...)
          for i = 1, args.n do
            local data = args[i]
            if data then
              for field, value in pairs(data) do
                local key = get_property_key(field)
                if key then
                  _ENV[name..field](target1, target2, target3, unpack_cond(value))
                end
              end
            end
          end
        end
      else
        return function(...)
          local args = t_pack(...)
          for i = initial + 1, args.n do
            local data = args[i]
            if data then
              for field, value in pairs(data) do
                local key = get_property_key(field)
                if key then
                  local args2 = {}
                  for i = 1, initial do
                    args2[i] = args[i]
                  end
                  if type(value) == 'table' then
                    for i = 1, value.n or #value do
                      args2[initial + i] = value[i]
                    end
                    args2.n = initial + (value.n or #value)
                  else
                    args2[initial + 1] = value
                    args2.n = initial + 1
                  end
                  _ENV[name..key](t_unpack(args2))
                end
              end
            end
          end
        end
      end
    end
  }
  func_patterns['Properties$'] = func_patterns['PropertiesOf(%d+)$']
  
  local function find_script_var(key)
    if key == '_G' then
      return _ENV
    elseif key ~= 'debug' then
      return (find_func(key))
    end
  end
  
  script_environment = setmetatable({}, {
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
  
  do
    local script_cache = {}
    
    cache_script = function(chunk)
      if type(chunk) == 'function' then
        return chunk
      end
      local hash = GetStringHash(chunk)
      local script = script_cache[hash]
      if not script then
        script = assert(load(chunk, '=(load)', nil, script_environment))
        script_cache[hash] = script
      end
      return script
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
      return do_script, do_script
    elseif name == 'rawset' or name == 'rawget' then
      return nil
    end
    local f, f_inner = _ENV[name]
    if f then
      return f, f
    end
    if not str_find(name, 'ThisFrame$') then
      f, f_inner = find_func(name .. 'ThisFrame')
      if type(f) == 'function' then
        return function(...)
          frame_func_handlers[f] = pack_frame_args(f, ...)
        end, f_inner
      end
    end
    for pattern, proc in pairs(func_patterns) do
      f, f_inner = match_result(name, proc, str_find(name, pattern))
      if f then
        return f, f_inner or f
      end
    end
  end
  
  local function process_call(token, status, ...)
    if token or not status then
      return TriggerServerEvent('fivework:ExecFunctionResult', status, observe_state(t_pack(...)), token)
    end
  end
  
  local function remote_call(name, token, args)
    local func = script_environment[name]
    if func == nil then
      return process_call(token, false, "attempt to call a nil value (field '"..name.."')")
    end
    return process_call(token, pcall(func, t_unpack(args)))
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
local RequestCollisionAtCoord = _ENV.RequestCollisionAtCoord
local HasCollisionLoadedAroundEntity = _ENV.HasCollisionLoadedAroundEntity

do
  local function model_finalizer(hash, ...)
    SetModelAsNoLongerNeeded(hash)
    return ...
  end

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
      return model_finalizer(hash, callback(true))
    end)
  end
  
  function LoadModel(hash, ...)
    if not IsModelValid(hash) then return false end
    return HasModelLoaded(hash) or cor_yield(model_scheduler, hash, ...)
  end
end
local LoadModel = _ENV.LoadModel

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

do
  local IsScreenFadedIn = _ENV.IsScreenFadedIn
  local IsScreenFadedOut = _ENV.IsScreenFadedOut
  local DoScreenFadeIn = _ENV.DoScreenFadeIn
  local DoScreenFadeOut = _ENV.DoScreenFadeOut

  local function fade_scheduler(callback, func, check, duration)
    return Cfx_CreateThread(function()
      func(duration)
      while not check() do
        Cfx_Wait(0)
      end
      return callback(true)
    end)
  end
  
  function FadeInScreen(...)
    if IsScreenFadedIn() then return false end
    return cor_yield(fade_scheduler, DoScreenFadeIn, IsScreenFadedIn, ...)
  end
  
  function FadeOutScreen(...)
    if IsScreenFadedOut() then return false end
    return cor_yield(fade_scheduler, DoScreenFadeOut, IsScreenFadedOut, ...)
  end
end
local FadeInScreen = _ENV.FadeInScreen
local FadeOutScreen = _ENV.FadeOutScreen

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

function SetTextComponentsList(list)
  for i = 1, list.n or #list do
    local component = list[i]
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
end
local SetTextComponentsList = _ENV.SetTextComponentsList

function SetTextComponents(...)
  return SetTextComponentsList(t_pack(...))
end

do
  local function parse_text_data(data)
    for field, value in pairs(data) do
      local key = get_property_key(field)
      if key then
        _ENV['SetText'..key](unpack_cond(value))
      end
    end
    SetTextComponentsList(data)
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
      local pressed, released
      for k, info in pairs(registered_controls) do
        if IsControlJustPressed(t_unpack(info)) then
          if not pressed then
            pressed = {}
          end
          pressed[info[2]] = info[1]
        end
        if IsControlJustReleased(t_unpack(info)) then
          if not released then
            released = {}
          end
          released[info[2]] = info[1]
        end
      end
      if pressed or released then
        FW_TriggerNetCallback('OnPlayerKeyStateChange', pressed or {}, released or {})
      end
      Cfx_Wait(0)
    end
  end)
end

-- updates

do
  local registered_updates = {}
  local thread_running = {}
  local default_interval = 0
  
  local function launch_thread(interval)
    if interval then
      if thread_running[interval] then
        return
      end
      thread_running[interval] = true
    end
    Cfx_CreateThread(function()
      while true do
        local updates
        local any
        for k, info in pairs(registered_updates) do
          if info[1] == interval then
            any = true
            local func = script_environment[info[3]]
            local newvalue = func and func(t_unpack(info, 4))
            local oldvalue = info[2]
            if oldvalue ~= newvalue and (oldvalue == oldvalue or newvalue == newvalue) then
              info[2] = newvalue
              if not updates then
                updates = {}
              end
              updates[t_pack(t_unpack(info, 3))] = {newvalue, oldvalue}
            end
          end
        end
        if interval and not any then
          thread_running[interval] = nil
          return
        end
        if updates then
          FW_TriggerNetCallback('OnPlayerUpdate', updates)
        end
        Cfx_Wait(interval or default_interval)
      end
    end)
  end
  launch_thread(nil)
  
  function FW_RegisterUpdate(fname, ...)
    local func = script_environment[fname]
    local value = func and func(...)
    registered_updates[j_encode{fname, ...}] = t_pack(nil, value, fname, ...)
  end
  
  function FW_UnregisterUpdate(...)
    registered_updates[j_encode{...}] = nil
  end
  
  function FW_IsUpdateRegistered(...)
    return registered_updates[j_encode{...}] ~= nil
  end
  
  function FW_SetUpdateInterval(newinterval, fname, ...)
    if fname then
      local info = registered_updates[j_encode{fname, ...}]
      if info then
        info[1] = newinterval
        if newinterval then
          launch_thread(newinterval)
        end
        return true
      end
    else
      default_interval = newinterval
      return true
    end
  end
  
  function FW_GetUpdateInterval(fname, ...)
    if fname then
      local info = registered_updates[j_encode{fname, ...}]
      if info then
        return info[1]
      end
    else
      return default_interval
    end
  end
end

-- enumerators

local GetActivePlayers = _ENV.GetActivePlayers
local GetPlayerPed = _ENV.GetPlayerPed
local GetEntityAttachedTo = _ENV.GetEntityAttachedTo
local GetEntityCoords = _ENV.GetEntityCoords
local GetVehiclePedIsIn = _ENV.GetVehiclePedIsIn

do
  local entity_enumerator = {
    __gc = function(enum)
      if enum[1] and enum[2] then
        enum[2](enum[1])
      end
      enum[1], enum[2] = nil, nil
    end
  }
  
  local function enumerate_entities(initFunc, moveFunc, disposeFunc)
    return cor_wrap(function()
      local iter, id = initFunc()
      if not id or id == 0 then
        disposeFunc(iter)
        return
      end
      
      local enum = {iter, disposeFunc}
      setmetatable(enum, entity_enumerator)
      
      local next = true
      repeat
        cor_yield(id)
        next, id = moveFunc(iter)
      until not next
      
      enum[1], enum[2] = nil, nil
      disposeFunc(iter)
    end)
  end
  
  local FindFirstObject = _ENV.FindFirstObject
  local FindNextObject = _ENV.FindNextObject
  local EndFindObject = _ENV.EndFindObject
  function EnumerateAllObjects()
    return enumerate_entities(FindFirstObject, FindNextObject, EndFindObject)
  end
  local EnumerateAllObjects = _ENV.EnumerateAllObjects
  
  local FindFirstPed = _ENV.FindFirstPed
  local FindNextPed = _ENV.FindNextPed
  local EndFindPed = _ENV.EndFindPed
  function EnumerateAllPeds()
    return enumerate_entities(FindFirstPed, FindNextPed, EndFindPed)
  end
  local EnumerateAllPeds = _ENV.EnumerateAllPeds
  
  local FindFirstVehicle = _ENV.FindFirstVehicle
  local FindNextVehicle = _ENV.FindNextVehicle
  local EndFindVehicle = _ENV.EndFindVehicle
  function EnumerateAllVehicles()
    return enumerate_entities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
  end
  local EnumerateAllVehicles = _ENV.EnumerateAllVehicles
  
  local FindFirstPickup = _ENV.FindFirstPickup
  local FindNextPickup = _ENV.FindNextPickup
  local EndFindPickup = _ENV.EndFindPickup
  function EnumeratePickups()
    return enumerate_entities(FindFirstPickup, FindNextPickup, EndFindPickup)
  end
  local EnumeratePickups = _ENV.EnumeratePickups
  
  function EnumerateVehicles()
    return cor_wrap(function()
      for veh in EnumerateAllVehicles() do
        local plVeh = GetVehiclePedIsIn(GetPlayerPed(PlayerId()))
        if veh ~= plVeh then
          cor_yield(veh)
        end
      end
    end)
  end
  local EnumerateVehicles = _ENV.EnumerateVehicles

  function GetPlayerFromPed(ped)
    for _, i in ipairs(GetActivePlayers()) do
      if GetPlayerPed(i) == ped then
        return i
      end
    end
  end
  local GetPlayerFromPed = _ENV.GetPlayerFromPed
  
  function EnumeratePeds()
    return cor_wrap(function()
      for ped in EnumerateAllPeds() do
        if not GetPlayerFromPed(ped) then
          cor_yield(ped)
        end
      end
    end)
  end
  local EnumeratePeds = _ENV.EnumeratePeds
  
  function EnumerateEntities()
    return cor_wrap(function()
      for e in EnumeratePeds() do
        cor_yield(e)
      end
      for e in EnumerateVehicles() do
        cor_yield(e)
      end
      for e in EnumerateAllObjects() do
        cor_yield(e)
      end
      for e in EnumeratePickups() do
        cor_yield(e)
      end
    end)
  end
  
  function EnumerateAllEntities()
    return cor_wrap(function()
      for e in EnumerateAllPeds() do
        cor_yield(e)
      end
      for e in EnumerateAllVehicles() do
        cor_yield(e)
      end
      for e in EnumerateAllObjects() do
        cor_yield(e)
      end
      for e in EnumeratePickups() do
        cor_yield(e)
      end
    end)
  end
  
  function EnumerateObjects()
    return cor_wrap(function()
      for obj in EnumerateAllObjects() do
        local attached = GetEntityAttachedTo(obj)
        if not attached or attached == 0 then
          coroutine.yield(obj)
        end
      end
    end)
  end
  
  function FindNearestEntity(pos, iterator, maxdist)
    maxdist = maxdist or m_huge
    local entity, dist
    for v in iterator() do
      if not entity then
        dist = Vdist(pos, GetEntityCoords(v, false))
        if dist <= maxdist then
          entity = v
        else
          entity = nil
        end
      else
        local d = Vdist(pos, GetEntityCoords(v, false))
        if d <= maxdist and d < dist then
          dist = d
          entity = v
        end
      end
    end
    return entity, dist
  end
end

-- scaleform methods

local RequestScaleformMovie = _ENV.RequestScaleformMovie
local BeginScaleformMovieMethod = _ENV.BeginScaleformMovieMethod
local ScaleformMovieMethodAddParamTextureNameString = _ENV.ScaleformMovieMethodAddParamTextureNameString
local ScaleformMovieMethodAddParamBool = _ENV.ScaleformMovieMethodAddParamBool
local ScaleformMovieMethodAddParamInt = _ENV.ScaleformMovieMethodAddParamInt
local ScaleformMovieMethodAddParamFloat = _ENV.ScaleformMovieMethodAddParamFloat
local EndScaleformMovieMethod = _ENV.EndScaleformMovieMethod
local EndScaleformMovieMethodReturnValue = _ENV.EndScaleformMovieMethodReturnValue
local IsScaleformMovieMethodReturnValueReady = _ENV.IsScaleformMovieMethodReturnValueReady
local SetScaleformMovieAsNoLongerNeeded = _ENV.SetScaleformMovieAsNoLongerNeeded
local HasScaleformMovieLoaded = _ENV.HasScaleformMovieLoaded

do
  local function return_scheduler(callback, retval)
    return Cfx_CreateThread(function()
      while not IsScaleformMovieMethodReturnValueReady(retval) do
        Cfx_Wait(0)
      end
      callback(true)
    end)
  end
  
  local function get_scaleform_method_name(name)
    local i, j, rettype = str_find(name, 'Return(.+)$')
    if rettype then
      name = str_sub(name, 1, i - 1)
      if rettype == 'None' then
        rettype = nil
      else
        rettype = _ENV['GetScaleformMovieMethodReturnValue'..rettype]
        if not rettype then
          return
        end
      end
    end
    
    local t = {}
    for s in str_gmatch(name, '[A-Z][a-z]+') do
      t_insert(t, str_upper(s))
    end
    
    name = t_concat(t, '_')
    
    return name, rettype
  end
  
  local function scaleform_loaded_scheduler(callback, scaleform)
    return Cfx_CreateThread(function()
      while not HasScaleformMovieLoaded(scaleform) do
        Cfx_Wait(0)
      end
      callback(true)
    end)
  end
  
  local function wait_for_scaleform(scaleform)
    if HasScaleformMovieLoaded(scaleform) then
      return true
    else
      return cor_yield(scaleform_loaded_scheduler, scaleform)
    end
  end
  
  local function call_scaleform_method(rettype, ...)
    local args = t_pack(...)
    for i = 1, args.n do
      local arg = args[i]
      if type(arg) == 'table' then
        local ctype, cvalue = next(arg)
        if ctype then
          _ENV['ScaleformMovieMethodAddParam'..ctype](unpack_cond(cvalue))
        end
      elseif type(arg) == 'string' then
        ScaleformMovieMethodAddParamTextureNameString(arg)
      elseif type(arg) == 'boolean' then
        ScaleformMovieMethodAddParamBool(arg)
      elseif m_type(arg) == 'integer' then
        ScaleformMovieMethodAddParamInt(arg)
      elseif m_type(arg) == 'float' then
        ScaleformMovieMethodAddParamFloat(arg)
      else
        ScaleformMovieMethodAddParamTextureNameString(tostring(arg))
      end
    end
    
    if not rettype then
      return EndScaleformMovieMethod()
    else
      local retval = EndScaleformMovieMethodReturnValue()
      if IsScaleformMovieMethodReturnValueReady(retval) then
        return rettype(retval)
      else
        if cor_yield(return_scheduler, retval) then
          return rettype(retval)
        end
      end
    end
  end
  
  local scaleform_movie = setmetatable({}, {
    __index = function(self, key)
      local name, rettype = get_scaleform_method_name(key)
      if not name then
        return
      end
      
      local function f(self, ...)
        if type(self) == 'table' then
          self = self.__data
        end
        
        wait_for_scaleform(self)
        BeginScaleformMovieMethod(self, name)
        
        return call_scaleform_method(rettype, ...)
      end
      rawset(self, key, f)
      return f
    end
  })
  
  local scaleform_mt = {
    __index = scaleform_movie
  }
  
  local scaleform_mt_gc = {
    __index = scaleform_movie,
    __gc = function(self)
      local id = self.__data
      if id then
        self.__data = nil
        SetScaleformMovieAsNoLongerNeeded(id)
      end
    end
  }
  
  function ScaleformMovie(id, gc)
    if type(id) == 'string' then
      id = RequestScaleformMovie(id)
      if gc == nil then
        gc = true
      end
    end
    if id and id ~= 0 then
      return setmetatable({__data = id}, gc and scaleform_mt_gc or scaleform_mt)
    end
  end
  
  local function global_scaleform(beginFunc)
    return setmetatable({}, {
      __index = function(self, key)
        local name, rettype = get_scaleform_method_name(key)
        if not name then
          return
        end
        
        local function f(self, ...)
          beginFunc(name)
          return call_scaleform_method(rettype, ...)
        end
        rawset(self, key, f)
        return f
      end
    })
  end

  ScaleformMovieOnFrontend = global_scaleform(BeginScaleformMovieMethodOnFrontend)
  ScaleformMovieOnFrontendHeader = global_scaleform(BeginScaleformMovieMethodOnFrontendHeader)
  
  local function local_scaleform(beginFunc)
    local prototype = setmetatable({}, {
      __index = function(self, key)
        local name, rettype = get_scaleform_method_name(key)
        if not name then
          return
        end
        
        local function f(self, ...)
          if type(self) == 'table' then
            self = self.__data
          end
          
          beginFunc(self, name)
          
          return call_scaleform_method(rettype, ...)
        end
        rawset(self, key, f)
        return f
      end
    })
    
    local prototype_mt = {
      __index = prototype
    }
    
    return function(id)
      return setmetatable({__data = id}, prototype_mt)
    end
  end
  
  ScaleformScriptHudMovie = local_scaleform(BeginScaleformScriptHudMovieMethod)
  ScaleformMinimapMovie = local_scaleform(CallMinimapScaleformFunction)
end

-- spawning

do
  local SetEntityVisible = _ENV.SetEntityVisible
  local SetEntityCollision = _ENV.SetEntityCollision
  local FreezeEntityPosition = _ENV.FreezeEntityPosition
  local IsPedFatallyInjured = _ENV.IsPedFatallyInjured
  local ClearPedTasksImmediately = _ENV.ClearPedTasksImmediately
  local SetPlayerInvincible = _ENV.SetPlayerInvincible
  local IsPedInAnyVehicle = _ENV.IsPedInAnyVehicle

  function ToggleControl(controllable, flags)
    local player = PlayerId()
    local ped = PlayerPedId()
    
    SetPlayerControl(player, controllable, flags or 0)
  
    FreezeEntityPosition(ped, not controllable)
    SetPlayerInvincible(player, not controllable)
    
    if not controllable or not IsPedInAnyVehicle(ped) then
      SetEntityCollision(ped, controllable)
    end
    
    if not controllable and not IsPedFatallyInjured(ped) then
      ClearPedTasksImmediately(ped)
    end
  end
  
  local ToggleControl = _ENV.ToggleControl
  local RequestCollisionAtCoord = _ENV.RequestCollisionAtCoord
  local SetEntityCoordsNoOffset = _ENV.SetEntityCoordsNoOffset
  local NetworkResurrectLocalPlayer = _ENV.NetworkResurrectLocalPlayer
  local ClearPlayerWantedLevel = _ENV.ClearPlayerWantedLevel
  local ClearPedBloodDamage = _ENV.ClearPedBloodDamage
  local ClearPedWetness = _ENV.ClearPedWetness
  local ClearPedEnvDirt = _ENV.ClearPedEnvDirt
  local SetPedConfigFlag = _ENV.SetPedConfigFlag
  local ShutdownLoadingScreen = _ENV.ShutdownLoadingScreen
  
  function SpawnIn(model, modelProperties, x, y, z, heading, entityProperties, fade)
    if fade then
      FadeOutScreen(fade)
    end
    
    ToggleControl(false)
    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    
    if LoadModel(model) then
      SetPlayerModel(PlayerId(), model)
      ped = PlayerPedId()
      
      if modelProperties then
        for field, value in pairs(modelProperties) do
          local key = get_property_key(field)
          if key then
            _ENV['SetPed'..key](ped, unpack_cond(value))
          end
        end
      end
    end
    
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false, true)
    NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
    ClearPedTasksImmediately(ped)
    
    RemoveAllPedWeapons(ped)
    ClearPlayerWantedLevel(PlayerId())
    ClearPedBloodDamage(ped)
    ClearPedWetness(ped)
    ClearPedEnvDirt(ped)
    
    SetPedConfigFlag(ped, 32, false) --PED_FLAG_CAN_FLY_THRU_WINDSCREEN
    SetPedConfigFlag(ped, 184, true) --_PED_FLAG_DISABLE_SHUFFLING_TO_DRIVER_SEAT
    
    if entityProperties then
      for field, value in pairs(entityProperties) do
        local key = get_property_key(field)
        if key then
          _ENV['SetPed'..key](ped, unpack_cond(value))
        end
      end
    end
    
    LoadCollisionAroundEntity(ped)
    SetEntityVisible(ped, true, false)
    ShutdownLoadingScreen()
    
    if fade then
      FadeInScreen(fade)
    end
    
    ToggleControl(true)
  end
end
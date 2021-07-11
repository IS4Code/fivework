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

-- remote execution

local script_environment

-- observers

local observe_state
do
  local observers = {}
  
  local function set_state(state, name, ...)
    state[j_encode{name, ...}] = t_pack(pcall(script_environment[name], ...))
  end
  
  observe_state = function(args)
    local state = {}
    for name, v in pairs(observers) do
      local validator = v[1]
      if validator ~= nil then
        for i = 1, args.n do
          local arg = args[i]
          
          local valid
          if type(validator) == 'boolean' then
            valid = validator
          elseif type(validator) == 'table' then
            valid = validator[arg]
          elseif type(validator) == 'function' then
            local status, result = pcall(validator, arg)
            valid = status and result
          end
          
          if valid then
            set_state(state, name, arg, t_unpack(v, 2))
          end
        end
      else
        set_state(state, name, t_unpack(v, 2))
      end
    end
    if next(state) then
      args.state = state
    end
    return args
  end
  
  function FW_RegisterObserver(name, validator, ...)
    if type(validator) == 'string' then
      validator = assert(_ENV[validator], 'variable not found')
    end
    observers[name] = t_pack(validator, ...)
  end
  
  function FW_UnregisterObserver(name)
    observers[name] = nil
  end
end

-- callbacks

do
  local callback_info = {}
  
  function FW_CreateCallbackHandler(name, handler)
    return callback_info[name](handler)
  end
  
  function FW_RegisterCallback(name, eventname, processor)
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
            a = NetworkGetEntityFromNetworkId(a)
            return f(a, ...)
          end, f_inner
        elseif pos == 2 then
          return function(a, b, ...)
            b = NetworkGetEntityFromNetworkId(b)
            return f(a, b, ...)
          end, f_inner
        elseif pos == 3 then
          return function(a, b, c, ...)
            c = NetworkGetEntityFromNetworkId(c)
            return f(a, b, c, ...)
          end, f_inner
        else
          return function(...)
            local t = t_pack(...)
            t[pos] = NetworkGetEntityFromNetworkId(t[pos])
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
            t[pos] = NetworkGetNetworkIdFromEntity(t[pos])
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
    end
  }
  
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
        return f, f_inner
      end
    end
  end
  
  local function process_call(token, status, ...)
    if token or not status then
      return TriggerServerEvent('fivework:ExecFunctionResult', status, observe_state(t_pack(...)), token)
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

-- updates

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

-- enumerators

local GetActivePlayers = _ENV.GetActivePlayers
local GetPlayerPed = _ENV.GetPlayerPed
local GetEntityAttachedTo = _ENV.GetEntityAttachedTo
local GetEntityCoords = _ENV.GetEntityCoords

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
  function EnumerateVehicles()
    return enumerate_entities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
  end
  
  local FindFirstPickup = _ENV.FindFirstPickup
  local FindNextPickup = _ENV.FindNextPickup
  local EndFindPickup = _ENV.EndFindPickup
  function EnumeratePickups()
    return enumerate_entities(FindFirstPickup, FindNextPickup, EndFindPickup)
  end

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
local BeginScaleformScriptHudMovieMethod = _ENV.BeginScaleformScriptHudMovieMethod

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
          self = self.__id
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
      local id = self.__id
      if id then
        self.__id = nil
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
    return setmetatable({__id = id}, gc and scaleform_mt_gc or scaleform_mt)
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

  local scaleform_script_hud_movie = setmetatable({}, {
    __index = function(self, key)
      local name, rettype = get_scaleform_method_name(key)
      if not name then
        return
      end
      
      local function f(self, ...)
        if type(self) == 'table' then
          self = self.__id
        end
        
        BeginScaleformScriptHudMovieMethod(self, name)
        
        return call_scaleform_method(rettype, ...)
      end
      rawset(self, key, f)
      return f
    end
  })
  
  local scaleform_script_hud_movie_mt = {
    __index = scaleform_script_hud_movie
  }
  
  function ScaleformScriptHudMovie(id)
    return setmetatable({__id = id}, scaleform_script_hud_movie_mt)
  end
end
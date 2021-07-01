-- imports

local pcall = _ENV.pcall
local pairs = _ENV.pairs
local ipairs = _ENV.ipairs
local next = _ENV.next
local tostring = _ENV.tostring
local type = _ENV.type
local m_type = math.type
local t_pack = table.pack
local t_unpack_orig = table.unpack
local cor_yield = coroutine.yield
local str_find = string.find
local str_sub = string.sub
local str_gsub = string.gsub
local str_byte = string.byte
local str_format = string.format

local TriggerServerEvent = _ENV.TriggerServerEvent
local NetworkGetNetworkIdFromEntity = _ENV.NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = _ENV.NetworkGetEntityFromNetworkId

local FW_Async = _ENV.FW_Async

local function t_unpack(t)
  return t_unpack_orig(t, 1, t.n)
end

-- internal

local callback_info = {}

function FW_CreateCallbackHandler(name, handler)
  return callback_info[name](handler)
end

-- callback configuration

function FW_RegisterCallback(name, eventname, cancellable)
  callback_info[name] = function(handler)
    AddEventHandler(eventname, function(...)
      if not handler(...) and cancellable then
        CancelEvent()
      end
    end)
    return true
  end
end

function FW_RegisterNetCallback(name, eventname, args_replacer)
  return AddEventHandler(eventname, function(...)
    local args
    if args_replacer then
      args = t_pack(args_replacer(...))
    else
      args = t_pack(...)
    end
    return TriggerServerEvent('fivework:ClientCallback', name, args)
  end)
end

function FW_TriggerNetCallback(name, ...)
  return TriggerServerEvent('fivework:ClientCallback', name, t_pack(...))
end

-- frame handlers

local frame_func_handlers = {}

Citizen.CreateThread(function()
  while true do
    for f, args in pairs(frame_func_handlers) do
      pcall(f, t_unpack(args))
    end
    Citizen.Wait(0)
  end
end)

local function replace_network_id(entity, ...)
  return NetworkGetNetworkIdFromEntity(entity), ...
end

local func_patterns = {
  ['NetworkedArgument$'] = function(f)
    return function(entity, ...)
      entity = NetworkGetEntityFromNetworkId(entity)
      return f(entity, ...)
    end
  end,
  ['NetworkedResult$'] = function(f)
    return function(...)
      return replace_network_id(f(...))
    end
  end
}

local function find_func(name)
  local f = _ENV[name]
  if f then
    return f
  end
  if not str_find(name, 'ThisFrame$') then
    f = find_func(name .. 'ThisFrame')
    if f then
      return function(enable, ...)
        if enable and type(enable) ~= 'boolean' then
          frame_func_handlers[f] = t_pack(enable, ...)
        else
          frame_func_handlers[f] = enable and t_pack(...) or nil
        end
      end
    end
  end
  for pattern, proc in pairs(func_patterns) do
    local i, j = str_find(name, pattern)
    if i then
      local newname = str_sub(name, 1, i - 1)..str_sub(name, j + 1)
      f = find_func(newname)
      if f then
        return proc(f)
      end
    end
  end
end

-- remote execution

local function process_call(token, status, ...)
  if token or not status then
    return TriggerServerEvent('fivework:ExecFunctionResult', status, t_pack(...), token)
  end
end

local function remote_call(name, token, args)
  return process_call(token, pcall(find_func(name), t_unpack(args)))
end

RegisterNetEvent('fivework:ExecFunction')
AddEventHandler('fivework:ExecFunction', function(name, args, token)
  return FW_Async(remote_call, name, token, args)
end)

-- in-game loading

local Cfx_Wait = Citizen.Wait
local Cfx_CreateThread = Citizen.CreateThread
local IsModelValid = _ENV.IsModelValid
local RequestModel = _ENV.RequestModel
local GetGameTimer = _ENV.GetGameTimer
local HasModelLoaded = _ENV.HasModelLoaded
local GetTimeDifference = _ENV.GetTimeDifference
local SetModelAsNoLongerNeeded = _ENV.SetModelAsNoLongerNeeded
local DoesEntityExist = _ENV.DoesEntityExist
local RequestCollisionAtCoord = _ENV.RequestCollisionAtCoord
local HasCollisionLoadedAroundEntity = _ENV.HasCollisionLoadedAroundEntity

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

-- text drawing

local text_cache = {}

local AddTextEntry = _ENV.AddTextEntry
local GetHashKey = _ENV.GetHashKey

local function hexreplacer(c)
  return str_format('%x', str_byte(c))
end

function GetStringEntry(text)
  local textkey = text_cache[text]
  if not textkey then
    local texthash = GetHashKey(str_gsub(text, '(.)', hexreplacer))
    textkey = 'FW_TEXT_'..str_sub(str_format('%08x', texthash), -8)
    print(textkey)
    AddTextEntry(textkey, text)
    text_cache[text] = textkey
  end
  return textkey
end
local GetStringEntry = _ENV.GetStringEntry

local AddTextComponentSubstringPlayerName = _ENV.AddTextComponentSubstringPlayerName
local AddTextComponentInteger = _ENV.AddTextComponentInteger
local AddTextComponentFloat = _ENV.AddTextComponentFloat

function DrawTextDataThisFrame(text, x, y, data)
  local textkey = GetStringEntry(text)
  BeginTextCommandDisplayText(textkey)
  if data then
    for field, value in pairs(data) do
      if field == 'Components' then
        for i, component in ipairs(value) do
          if type(component) == 'string' then
            AddTextComponentSubstringPlayerName(component)
          elseif m_type(component) == 'integer' then
            AddTextComponentInteger(component)
          elseif m_type(component) == 'float' then
            AddTextComponentFloat(component, 2)
          elseif type(component) == 'table' then
            local ctype, cvalue = next(component)
            if type(cvalue) == 'table' then
              _ENV['AddTextComponentSubstring'..ctype](t_unpack(cvalue))
            else
              _ENV['AddTextComponentSubstring'..ctype](cvalue)
            end
          else
            AddTextComponentSubstringPlayerName(tostring(component))
          end
        end
      elseif type(value) == 'table' then
        _ENV['SetText'..field](t_unpack(value))
      else
        _ENV['SetText'..field](value)
      end
    end
  end
  return EndTextCommandDisplayText(x, y)
end

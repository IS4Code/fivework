-- imports

local t_pack = table.pack
local t_unpack_orig = table.unpack
local pcall = _ENV.pcall

local TriggerServerEvent = _ENV.TriggerServerEvent

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

-- remote execution

local function process_call(token, status, ...)
  if token or not status then
    return TriggerServerEvent('fivework:ExecFunctionResult', token, status, t_pack(...))
  end
end

local function remote_call(name, token, args)
  return process_call(token, pcall(_ENV[name], t_unpack(args)))
end

RegisterNetEvent('fivework:ExecFunction')
AddEventHandler('fivework:ExecFunction', function(name, token, args)
  return FW_Async(remote_call, name, token, args)
end)

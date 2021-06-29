-- imports

local t_unpack = table.unpack
local CancelEvent = _ENV.CancelEvent

-- internal

local callback_info = {}

function FW_CreateCallbackHandler(name, handler)
  return callback_info[name](handler)
end

local net_callback_handlers = {}

-- configuration

function FW_RegisterCallback(name, eventname, has_source, cancellable)
  callback_info[name] = function(handler)
    AddEventHandler(eventname, function(...)
      local result
      if has_source then
        result = handler(source, ...)
      else
        result = handler(...)
      end
      if cancellable and not result then
        CancelEvent()
      end
    end)
    return true
  end
end

function FW_RegisterNetCallback(name)
  callback_info[name] = function(handler)
    net_callback_handlers[name] = handler
  end
end

RegisterNetEvent('fivework:ClientCallback')
AddEventHandler('fivework:ClientCallback', function(name, args)
  local handler = net_callback_handlers[name]
  if handler then
    return handler(source, t_unpack(args))
  end
end)

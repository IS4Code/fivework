-- imports

local t_unpack_orig = table.unpack
local s_char = string.char
local m_random = math.random
local cor_yield = coroutine.yield
local error = _ENV.error
local rawset = _ENV.rawset

local CancelEvent = _ENV.CancelEvent
local TriggerClientEvent = _ENV.TriggerClientEvent

local function t_unpack(t)
  return t_unpack_orig(t, 1, t.n)
end

-- internal

local callback_info = {}

function FW_CreateCallbackHandler(name, handler)
  return callback_info[name](handler)
end

local net_callback_handlers = {}

-- callback configuration

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

-- remote execution

local continuations = {}

local function newid()
  local chars = {}
  for i = 1, 32 do
    chars[i] = m_random(33, 126)
  end
  return s_char(t_unpack(chars))
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
    TriggerClientEvent('fivework:ExecFunction', name, token, t_pack(...))
  end
end

RegisterNetEvent('fivework:ExecFunctionResult')
AddEventHandler('fivework:ExecFunctionResult', function(token, status, args)
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

local function for_index(scheduler_factory)
  return function(self, key)
    local scheduler = scheduler_factory(key)
    local function caller(...)
      return handle_result(cor_yield(scheduler, ...))
    end
    rawset(self, key, caller)
    return caller
  end
end

ForPlayer = setmetatable({}, {
  __index = for_index(player_scheduler_factory)
})

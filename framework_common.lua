-- imports

local cor = coroutine
local cor_create = cor.create
local cor_resume = cor.resume
local cor_yield = cor.yield
local error = _ENV.error
local rawset = _ENV.rawset
local t_unpack_orig = table.unpack

local Cfx_SetTimeout = Citizen.SetTimeout

local function t_unpack(t)
  return t_unpack_orig(t, 1, t.n)
end

-- async processing

function FW_Async(func, ...)
  local thread = cor_create(func)
  local on_yield
  local function schedule(scheduler, ...)
    return scheduler(function(...)
      return on_yield(cor_resume(thread, ...))
    end, ...)
  end
  on_yield = function(status, ...)
    if not status then
      error(...)
    end
    if coroutine.status(thread) ~= 'dead' then
      return schedule(...)
    end
    return ...
  end
  return on_yield(cor_resume(thread, ...))
end
local FW_Async = _ENV.FW_Async

local function sleep_scheduler(func, ms, ...)
  return Cfx_SetTimeout(ms, func, ...)
end

function Sleep(...)
  return cor_yield(sleep_scheduler, ...)
end

-- events

local registered_events = {}

public = setmetatable({}, {
  __newindex = function(self, key, value)
    if not registered_events[key] then
      registered_events[key] = FW_CreateCallbackHandler(key, function(...)
        local func = self[key]
        if func then
          return FW_Async(func, ...)
        end
      end)
    end
    return rawset(self, key, value)
  end
})

function FW_TriggerCallback(name, ...)
  local handler = public[name]
  if handler then
    return handler(...)
  end
end

-- commands

local registered_commands = {}

local function cmd_newindex(restricted)
  return function(self, key, value)
    if not registered_commands[key] then
      registered_commands[key] = RegisterCommand(key, function(source, args, rawCommand)
        local func = self[key]
        if func then
          return FW_Async(func, source, rawCommand, t_unpack(args))
        end
      end, restricted)
    end
    return rawset(self, key, value)
  end
end

cmd = setmetatable({}, {
   __newindex = cmd_newindex(false)
})

cmd_ac = setmetatable({}, {
   __newindex = cmd_newindex(true)
})

local cmd, cmd_ac = _ENV.cmd, _ENV.cmd_ac

function FW_TriggerCommand(name, ...)
  local handler = cmd[name]
  if handler then
    return handler(...)
  end
  handler = cmd_ac[name]
  if handler then
    return handler(...)
  end
end

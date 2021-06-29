-- imports

local cor = coroutine
local cor_create = cor.create
local cor_resume = cor.resume
local cor_yield = cor.yield
local error = _ENV.error
local rawset = _ENV.rawset

local Cfx_SetTimeout = Citizen.SetTimeout

-- async processing

local function run_async(func, ...)
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
          return run_async(func, ...)
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
      local handler = function(...)
        local func = self[key]
        if func then
          return run_async(func, ...)
        end
      end
      RegisterCommand(key, handler, restricted)
      registered_commands[key] = handler
    end
    return rawset(self, key, value)
  end
end

cmd = setmetatable({}, {
   _newindex = cmd_newindex(false)
})

cmdp = setmetatable({}, {
   _newindex = cmd_newindex(true)
})

function FW_TriggerCommand(name, ...)
  local handler = cmd[name]
  if handler then
    return handler(...)
  end
  handler = cmdp[name]
  if handler then
    return handler(...)
  end
end

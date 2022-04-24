-- imports

local cor = coroutine
local cor_create = cor.create
local cor_resume = cor.resume
local cor_yield = cor.yield
local cor_running = cor.running
local cor_status = cor.status
local error = _ENV.error
local assert = _ENV.assert
local tostring = _ENV.tostring
local rawset = _ENV.rawset
local pcall = _ENV.pcall
local xpcall = _ENV.xpcall
local ipairs = _ENV.ipairs
local t_pack = table.pack
local t_unpack_orig = table.unpack
local t_insert = table.insert
local d_traceback = debug.traceback

local Cfx_SetTimeout = Citizen.SetTimeout
local Cfx_CreateThread = Citizen.CreateThread
local Cfx_Await = Citizen.Await

local function t_unpack(t, i)
  return t_unpack_orig(t, i or 1, t.n)
end

-- async processing

local active_threads = setmetatable({}, {
  __mode = 'k'
})

local function thread_func(func, ...)
  return xpcall(func, d_traceback, ...)
end

function FW_Async(func, ...)
  local thread = cor_create(thread_func)
  active_threads[thread] = true
  local on_yield
  local function schedule(scheduler, ...)
    return scheduler(function(...)
      return on_yield(cor_resume(thread, ...))
    end, ...)
  end
  on_yield = function(status, ok_or_scheduler, ...)
    if not status then
      active_threads[thread] = nil
      return false, print("Unexpected error from coroutine:\n", ok_or_scheduler, ...)
    end
    if cor_status(thread) ~= 'dead' then
      return false, schedule(ok_or_scheduler, ...)
    end
    active_threads[thread] = nil
    if not ok_or_scheduler then
      return false, print("Error from coroutine:\n", ...)
    end
    return true, ...
  end
  return on_yield(cor_resume(thread, func, ...))
end
local FW_Async = _ENV.FW_Async

function FW_IsAsync()
  return active_threads[cor_running()] or false
end
local FW_IsAsync = _ENV.FW_IsAsync

function FW_Schedule(scheduler, ...)
  if not FW_IsAsync() then
    return error("attempted to perform asynchronous operation from non-asynchronous context; use FW_Async")
  end
  return cor_yield(scheduler, ...)
end

local function call_or_wrap_async(func, ...)
  if FW_IsAsync() then
    return true, func(...)
  else
    return FW_Async(func, ...)
  end
end

local function sleep_scheduler(func, ms, ...)
  return Cfx_SetTimeout(ms, function(...)
    func(...)
  end, ...)
end

function Sleep(...)
  return FW_Schedule(sleep_scheduler, ...)
end
local Sleep = _ENV.Sleep

local function handle_yield_result(args, done, ...)
  if done then
    return ...
  else
    return t_unpack(args)
  end
end

local function yield_scheduler(func, args)
  return handle_yield_result(args, func())
end

function Yield(...)
  return FW_Schedule(yield_scheduler, t_pack(...))
end

local function threaded_scheduler(func, threadFunc, args)
  return Cfx_CreateThread(function()
    return func(threadFunc(t_unpack(args)))
  end)
end

function FW_Threaded(func, ...)
  return FW_Schedule(threaded_scheduler, func, t_pack(...))
end

local function on_next(obj, onresult, onerror)
  local result = obj.__result
  if result then
    if result[1] then
      if onresult then
        onresult(t_unpack(result, 2))
      end
    else
      if onerror then
        onerror(t_unpack(result, 2))
      end
    end
  else
    local cont = obj.__cont
    if not cont then
      cont = {}
      obj.__cont = cont
    end
    t_insert(cont, {onresult, onerror})
  end
  return obj
end

local function make_promise(func, ...)
  local obj = {next = on_next}
  return obj, FW_Async(function(...)
    local result = t_pack(pcall(func, ...))
    obj.__result = result
    local cont = obj.__cont
    if cont then
      obj.__cont = nil
      for i, c in ipairs(cont) do
        local onresult, onerror = c[1], c[2]
        if result[1] then
          if onresult then
            onresult(t_unpack(result, 2))
          end
        else
          if onerror then
            onerror(t_unpack(result, 2))
          end
        end
      end
    end
  end, ...)
end

function FW_Awaited(func, ...)
  return Cfx_Await(make_promise(func, ...))
end

-- events

local registered_events = {}

local function async_results(done, ...)
  if done then
    return ...
  end
end

public = setmetatable({}, {
  __newindex = function(self, key, value)
    if not registered_events[key] then
      registered_events[key] = FW_CreateCallbackHandler(key, function(...)
        local func = self[key]
        if func then
          return async_results(FW_Async(func, ...))
        end
      end)
    end
    return rawset(self, key, value)
  end
})
local public = _ENV.public

function FW_TriggerCallback(name, ...)
  local handler = public[name]
  if handler then
    return call_or_wrap_async(handler, ...)
  end
end
local FW_TriggerCallback = _ENV.FW_TriggerCallback

-- commands

local registered_commands = {}

local function after_command(source, rawCommand, status, ...)
  local result = FW_TriggerCallback('OnPlayerPerformedCommand', source, rawCommand, status, ...)
  if not status and not result then
    return print("Error from command '"..rawCommand.."':\n", ...)
  end
end

local function cmd_newindex(restricted)
  return function(self, key, value)
    if not registered_commands[key] then
      registered_commands[key] = RegisterCommand(key, function(source, args, rawCommand)
        local func = self[key]
        if func then
          return async_results(FW_Async(function(...)
            Sleep(0)
            local result = FW_TriggerCallback('OnPlayerReceivedCommand', source, rawCommand, ...)
            if result ~= false then
              return after_command(source, rawCommand, pcall(func, source, rawCommand, ...))
            end
          end, t_unpack(args)))
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
  local handler = cmd[name] or cmd_ac[name]
  if handler then
    return call_or_wrap_async(handler, ...)
  end
end

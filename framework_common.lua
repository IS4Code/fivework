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
local rawget = _ENV.rawget
local rawset = _ENV.rawset
local pcall = _ENV.pcall
local xpcall = _ENV.xpcall
local ipairs = _ENV.ipairs
local setmetatable = _ENV.setmetatable
local type = _ENV.type
local select = _ENV.select
local tonumber = _ENV.tonumber
local collectgarbage = _ENV.collectgarbage
local t_pack = table.pack
local t_unpack_orig = table.unpack
local t_insert = table.insert
local t_concat = table.concat
local d_getinfo = debug.getinfo
local d_getlocal = debug.getlocal
local d_traceback = debug.traceback
local m_huge = math.huge
local m_type = math.type
local m_tointeger = math.tointeger
local m_modf = math.modf
local m_maxinteger = math.maxinteger
local u_codepoint = utf8.codepoint
local u_char = utf8.char
local u_charpattern = utf8.charpattern
local s_char = string.char
local s_byte = string.byte
local s_gsub = string.gsub
local s_sub = string.sub
local s_find = string.find
local s_match = string.match

local GetHashKey = _ENV.GetHashKey
local GetGameTimer = _ENV.GetGameTimer

local Cfx_SetTimeout = Citizen.SetTimeout
local Cfx_CreateThread = Citizen.CreateThread
local Cfx_Await = Citizen.Await
local Cfx_InvokeNative = Citizen.InvokeNative
local Cfx_ResultAsString = Citizen.ResultAsString()
local Cfx_Wait = Citizen.Wait

local function t_unpack(t, i)
  return t_unpack_orig(t, i or 1, t.n)
end

-- configuration

FW_ErrorLog = print
FW_WarningLog = print
FW_DebugLog = function()end

local monitor_interval = 100

local async_cleanup = 4

function FW_SetTimeMonitor(interval)
  monitor_interval = interval
end

function FW_SetAsyncCleanup(size)
  async_cleanup = size
end

do
  local stackdump_mt = {}
  
  local function thread_level(thread)
    return (thread and thread ~= cor_running()) and 0 or 1
  end
  
  local function default_traceback(thread, message, level)
    local thread_type = type(thread)
    if thread_type == 'table' and getmetatable(thread) == stackdump_mt then
      return message
    end
    if thread_type == 'thread' then
      level = (level or 1) + thread_level(thread)
    else
      message = (message or 1) + 1
    end
    return d_traceback(thread, message, level)
  end

  FW_Traceback = default_traceback

  function FW_StackDump(thread, level)
    level = level or thread_level(thread)
    
    local data = setmetatable({}, stackdump_mt)
    
    for i = level + thread_level(thread), m_huge do
      local info = thread and d_getinfo(thread, i, 'nlStuf') or d_getinfo(i, 'nlStuf')
      if not info then
        break
      end
      
      local args = {}
      info.args = args
      
      local outside_thread
      
      local function add_arg(j)
        local ok, name, value
        if thread then ok, name, value = pcall(d_getlocal, thread, i + thread_level(thread) * 2, j) else ok, name, value = pcall(d_getlocal, i + 2, j) end
        if not ok then
          outside_thread = true
          return false
        end
        if not name then
          return false
        end
        t_insert(args, {name, value})
        return true
      end
      
      for j = 1, what == 'C' and m_huge or info.nparams do
        if not add_arg(j) then break end
      end
      
      if info.isvararg then
        local args_over = 0
        for j = -1, -m_huge, -1 do
          if not add_arg(j) then break end
          if j < -8 then
            args[#args] = nil
            args_over = args_over + 1
          end
        end
        info.args_over = args_over
      end
      
      if outside_thread then
        break
      end
      
      t_insert(data, info)
    end
    
    return data
  end
  local FW_StackDump = _ENV.FW_StackDump
  
  function FW_RuntimeTraceback(thread, message, level)
    local thread_type = type(thread)
    if (thread_type == 'table' and getmetatable(thread) == stackdump_mt) or thread_type == 'thread' then
      return default_traceback(thread, message, level)
    else
      message, level = thread, message
    end
    if message ~= nil and type(message) ~= 'string' then
      return message
    end
    return Cfx_InvokeNative(`FORMAT_STACK_TRACE` & 0xFFFFFFFF, nil, 0, Cfx_ResultAsString)
  end
  
  local string_escape_pattern = "([\"\\\a\b\f\n\r\t\v])"
  local string_escapes = {
    ["\""]="\\\"", ["\\"]="\\\\",
    ["\a"]="\\a", ["\b"]="\\b", ["\f"]="\\f", ["\n"]="\\n", ["\r"]="\\r", ["\t"]="\\t", ["\v"]="\\v"
  }
  
  local function find_global(value)
    for k, v in pairs(_ENV) do
      if type(k) == 'string' and v == value then
        return k
      end
      if type(v) == 'table' and v ~= _ENV then
        for k2, v2 in pairs(v) do
          if v2 == value then
            return k..'.'..k2
          end
        end
      end
    end
  end
  
  function FW_PrettyTraceback(thread, message, level)
    local thread_type = type(thread)
    local is_dump = thread_type == 'table' and getmetatable(thread) == stackdump_mt
    if thread_type ~= 'thread' and not is_dump then
      message, level = thread, message
      thread = nil
    end
    
    if message ~= nil and type(message) ~= 'string' then
      return message
    end
    
    level = level or thread_level(thread)
    
    local data = is_dump and thread or FW_StackDump(thread, level + thread_level(thread))
    
    local lines = {}
    if message then
      t_insert(lines, message)
    end
    
    local err = data.error
    if err then
      t_insert(lines, tostring(err))
    end
    
    for i, info in ipairs(data) do
      if not is_dump or i >= level then
        local func = info.func
        
        if func == pcall or func == xpcall then
          break
        end
        
        if func ~= error and func ~= assert then
          local what, name, namewhat = info.what, info.name, info.namewhat
          if not name then
            if what == 'main' then
              name = "<"..what..">"
            elseif func then
              name = find_global(func)
              if not name then
                name = s_gsub(tostring(func), '^function: 0?x?0*', '0x')
              end
            end
          end
          
          local args = {}
          
          for i, v in ipairs(info.args) do
            local name, value = t_unpack(v)
            local value_type = type(value)
            if value_type == 'nil' or value_type == 'boolean' or value_type == 'number' then
              value = tostring(value)
            elseif value_type == 'string' then
              if #value > 32 then
                value = s_sub(value, 1, 29)
                value = "\""..s_gsub(value, string_escape_pattern, string_escapes).."\"..."
              else
                value = "\""..s_gsub(value, string_escape_pattern, string_escapes).."\""
              end
            else
              local name = find_global(value)
              if name then
                value = name
              else
                value = s_gsub(tostring(value), '^'..value_type..': 0?x?0*', '0x')
                value = value_type.."("..value..")"
              end
            end
            local str
            if s_sub(name, 1, 1) == '(' then
              str = value
            else
              str = name.." = "..value
            end
            t_insert(args, str)
          end
          
          local args_over = info.args_over
          if args_over and args_over > 0 then
            t_insert(args, "... ("..args_over.." more)")
          end
          
          local location = info.short_src
          local line, linestart, lineend = info.currentline, info.linedefined, info.lastlinedefined
          if line and line >= 0 then
            location = location..":"..line
          elseif linestart and linestart >= 0 then
            location = location..":"..linestart..".."..lineend
          end
          
          local fields = {"at", name.."("..t_concat(args, ", ")..")"}
          t_insert(fields, "in")
          t_insert(fields, location)
          if info.istailcall then
            t_insert(fields, "(tail call)")
          end
          t_insert(lines, t_concat(fields, " "))
        end
      end
    end
    return t_concat(lines, "\n")
  end
end

local function log_on_error(ok, ...)
  if not ok then
    FW_ErrorLog(...)
    FW_ErrorLog("Called from:\n", FW_Traceback(nil, 2))
  end
  return ok, ...
end

function FW_TryCall(func, ...)
  return log_on_error(xpcall(func, FW_Traceback, ...))
end

-- async processing

local active_threads = setmetatable({}, {
  __mode = 'k'
})

local function thread_func(func, ...)
  return xpcall(func, FW_Traceback, ...)
end

local function function_info(func)
  local info = d_getinfo(func)
  return "running "..info.what.." function "..info.namewhat.." in "..info.short_src..":"..info.linedefined..".."..info.lastlinedefined
end

local function check_time(start_time, func, thread)
  if monitor_interval then
    local time = GetGameTimer()
    if time > start_time + monitor_interval then
      local traceback
      if cor_status(thread) ~= 'dead' then
        traceback = FW_Traceback(thread)
      else
        local ok
        ok, traceback = pcall(function_info, func)
      end
      FW_WarningLog("Coroutine code took", time - start_time, "ms to execute:\n", traceback)
    end
  end
end

function FW_Async(func, ...)
  local thread = cor_create(thread_func)
  active_threads[thread] = true
  local on_yield
  local function schedule(scheduler, ...)
    local continuation = function(...)
      return on_yield(GetGameTimer(), cor_resume(thread, ...))
    end
    if type(scheduler) == 'number' then
      return Cfx_SetTimeout(scheduler, continuation, ...)
    end
    return scheduler(continuation, ...)
  end
  on_yield = function(start_time, status, ok_or_scheduler, ...)
    check_time(start_time, func, thread)
    if async_cleanup then
      collectgarbage('step', async_cleanup)
    end
    if not status then
      active_threads[thread] = nil
      return false, FW_ErrorLog("Unexpected error from coroutine:\n", ok_or_scheduler, ...)
    end
    if cor_status(thread) ~= 'dead' then
      return false, schedule(ok_or_scheduler, ...)
    end
    active_threads[thread] = nil
    if not ok_or_scheduler then
      return false, FW_ErrorLog("Error from coroutine:\n", ...)
    end
    return true, ...
  end
  return on_yield(GetGameTimer(), cor_resume(thread, func, ...))
end
local FW_Async = _ENV.FW_Async

function FW_IsAsync()
  return active_threads[cor_running()] or false
end
local FW_IsAsync = _ENV.FW_IsAsync

function FW_MarkAsync(thread)
  active_threads[thread or cor_running()] = true
end

function FW_Schedule(scheduler, ...)
  if not FW_IsAsync() then
    return error("attempted to perform asynchronous operation from non-asynchronous context; use FW_Async")
  end
  return cor_yield(scheduler, ...)
end
local FW_Schedule = _ENV.FW_Schedule

local function immediate(done, ...)
  return ...
end

local function log_error(status, ...)
  if status then
    return status, ...
  end
  return false, FW_ErrorLog("Error from handler:\n", ...)
end

local function call_or_wrap_async(func, ...)
  if FW_IsAsync() then
    return log_error(xpcall(func, FW_Traceback, ...))
  else
    return FW_Async(func, ...)
  end
end

do
  local GetCurrentResourceName = _ENV.GetCurrentResourceName
  AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
      call_or_wrap_async = function(func, ...)
        return log_error(xpcall(func, FW_Traceback, ...))
      end
      local function disabled()
        return error('this function cannot be used while the script is stopping')
      end
      cor_create = disabled
      cor_resume = disabled
      Cfx_SetTimeout = disabled
      Cfx_CreateThread = disabled
      Cfx_Await = disabled
    end
  end)
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

-- callbacks

do
  local callback_info = {}
  FW_CallbackHandlers = callback_info
  
  local AddStateBagChangeHandler = _ENV.AddStateBagChangeHandler
  
  function callback_info.OnStateBagChange(handler)
    AddStateBagChangeHandler(nil, nil, function(bagName, key, value, source, ...)
      local bagType, id = s_match(bagName, '^([^:]*):(.*)')
      if id then
        id = tonumber(id) or id
      end
      return handler(source, bagType or bagName, id, key, value, ...)
    end)
  end
  
  local function create_handler(name, handler)
    local registerer = callback_info[name]
    if not registerer then
      return error("Callback '"..tostring(name).."' was not defined!")
    end
    return registerer(handler)
  end
  FW_CreateCallbackHandler = create_handler
  
  local registered_events = {}
  
  public = setmetatable({}, {
    __newindex = function(self, key, value)
      if not registered_events[key] then
        local callback_key = s_match(key, '^(.*)_NoAsync$')
        local caller
        if callback_key then
          caller = function(...)
            local func = self[key]
            if func then
              return func(...)
            end
          end
        else
          callback_key = key
          caller = function(...)
            local func = self[key]
            if func then
              return immediate(FW_Async(func, ...))
            end
          end
        end
        registered_events[key] = create_handler(callback_key, caller)
      end
      return rawset(self, key, value)
    end
  })
end
local public = _ENV.public

function FW_TriggerCallback(name, ...)
  local handler = public[name]
  if handler then
    return immediate(call_or_wrap_async(handler, ...))
  end
end
local FW_TriggerCallback = _ENV.FW_TriggerCallback

-- commands

local registered_commands = {}

local function after_command(source, rawCommand, status, ...)
  local result = FW_TriggerCallback('OnPlayerPerformedCommand', source, rawCommand, status, ...)
  if not status and not result then
    return FW_ErrorLog("Error from command '"..tostring(rawCommand).."':\n", ...)
  end
end

local function call_command(source, args, result, ...)
  if result == true then
    return after_command(source, args, xpcall(args.handler, FW_Traceback, source, args, ...))
  elseif result ~= false then
    return after_command(source, args, xpcall(args.handler, FW_Traceback, source, args, t_unpack(args)))
  end
end

local command_mt = {
  __tostring = function(self)
    return self.raw or ""
  end,
  __index = function(self, key)
    local raw = self.raw
    if type(raw) == 'string' then
      local value
      if key == 'rawName' then
        local pos, _, match = s_find(raw, '^%s*([^%s]+)%s*')
        if pos then
          value = match
        end
      elseif key == 'rawArgs' then
        value = s_gsub(raw, '^%s*[^%s]+%s*', '')
      end
      rawset(self, key, value)
      return value
    end
  end
}

local function cmd_newindex(restricted)
  return function(self, key, value)
    if not registered_commands[key] then
      registered_commands[key] = RegisterCommand(key, function(source, args, rawCommand)
        local func = self[key]
        if func then
          args.raw = rawCommand
          args.handler = func
          args.name = key
          setmetatable(args, command_mt)
          return immediate(FW_Async(function(...)
            Sleep(0)
            return call_command(source, args, FW_TriggerCallback('OnPlayerReceivedCommand', source, args, ...))
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
    return immediate(call_or_wrap_async(handler, ...))
  end
end

-- events convenience

local TriggerEvent = _ENV.TriggerEvent
local TriggerServerEvent = _ENV.TriggerServerEvent
local TriggerClientEvent = _ENV.TriggerClientEvent
local WasEventCanceled = _ENV.WasEventCanceled

do
  local function event_table(trigger, prefix, separator, parent)
    return setmetatable({}, {
      __call = function(self, arg, ...)
        if arg == parent then
          trigger(prefix, ...)
        else
          trigger(prefix, arg, ...)
        end
        return not WasEventCanceled()
      end,
      __index = function(self, key)
        local t = event_table(trigger, prefix..separator..key, separator, self)
        rawset(self, key, t)
        return t
      end
    })
  end
  
  function EventsFor(prefix, separator)
    return event_table(TriggerEvent, prefix, separator)
  end
  
  if TriggerServerEvent then
    function ServerEventsFor(prefix, separator)
      return event_table(TriggerServerEvent, prefix, separator)
    end
  end
  
  if TriggerClientEvent then
    function ClientEventsFor(playerid, prefix, separator)
      return event_table(function(name, ...)
        return TriggerClientEvent(name, playerid, ...)
      end, prefix, separator)
    end
  end
end

local AddEventHandler = _ENV.AddEventHandler
local CancelEvent = _ENV.CancelEvent
do
  local function create_event_cache(registerer)
    return setmetatable({}, {
      __mode = 'k',
      __index = function(self, func)
        local name = 'fivework_func:'..tostring(func)
        registerer(name, function(...)
          local result = immediate(FW_Async(func, ...))
          if result == false then
            CancelEvent()
          end
        end)
        rawset(self, func, name)
        return name
      end
    })
  end

  local event_cache = create_event_cache(AddEventHandler)
  
  function GetFunctionEvent(func)
    return event_cache[func]
  end
end

-- packing

function FW_Pack(data)
  return data
end

if msgpack then
  local pack = msgpack.pack
  
  if pack then
    local packed_mt = {
      __pack = function(self, ...)
        return self.data, true
      end
    }
    
    function FW_Pack(data)
      return setmetatable({data = pack(data)}, packed_mt)
    end
  end
end

-- serialization

do
  local j_encode = json.encode
  local j_decode = json.decode
  
  local special_prefix = '#'
  local literal_infix = '#'
  local json_infix = ':'
  local special_infix = '.'
  local definition_suffix = '='
  local infix_pos = #special_prefix + 1
  
  local function is_special(str)
    return str_sub(str, 1, #special_prefix) == special_prefix
  end
  
  local function needs_transform(t)
    local array, object
    local count = 0
    for k, v in pairs(t) do
      if type(v) == 'table' then
        if needs_transform(v) then
          return true
        end
      elseif type(v) == 'string' then
        if is_special(v) then
          return true
        end
      elseif m_type(v) == 'float' then
        if v ~= v or v == m_huge or v == -m_huge then
          return true
        end
      end
      if m_type(k) == 'integer' and k > 0 then
        if object then
          return true
        end
        count = count + 1
        array = true
      elseif type(k) == 'string' then
        if array or is_special(k) then
          return true
        end
        object = true
      else
        return true
      end
    end
    return count ~= #t
  end
  
  local function transform_table(t, cache)
    if not needs_transform(t) then
      return t
    end
    cache = cache or {}
    local g = cache[t]
    if g then
      return g
    end
    g = {}
    cache[t] = g
    for k, v in pairs(t) do
      if type(v) == 'table' then
        v = transform_table(v, cache)
      elseif type(v) == 'string' and is_special(v) then
        v = special_prefix..literal_infix..v
      elseif m_type(v) == 'float' then
        if v ~= v then
          v = special_prefix..special_infix..'nan'
        elseif v == m_huge then
          v = special_prefix..special_infix..'inf'
        elseif v == -m_huge then
          v = special_prefix..special_infix..'-inf'
        end
      end
      if type(k) ~= 'string' then
        if type(k) == 'table' then
          local k2 = transform_table(k, cache)
          if k ~= k2 then
            for i = 1, m_huge do
              local l = special_prefix..i
              if not g[l] then
                g[special_prefix..i..definition_suffix] = k2
                k = l
                break
              end
            end
          else
            k = special_prefix..json_infix..j_encode(k)
          end
        elseif m_type(k) == 'float' then
          if k ~= k then
            k = special_prefix..special_infix..'nan'
          elseif k == m_huge then
            k = special_prefix..special_infix..'inf'
          elseif k == -m_huge then
            k = special_prefix..special_infix..'-inf'
          else
            k = special_prefix..json_infix..j_encode(k)
          end
        else
          k = special_prefix..json_infix..j_encode(k)
        end
      elseif is_special(k) then
        k = special_prefix..literal_infix..k
      end
      g[k] = v
    end
    return g
  end
  
  local transform_table_back
  
  local special_table = {
    ['nan'] = 0/0,
    ['inf'] = m_huge,
    ['-inf'] = -m_huge
  }
  
  local function transform_value_back(v, t)
    if type(v) == 'table' then
      return transform_table_back(v)
    elseif type(v) == 'string' and is_special(v) then
      if str_sub(v, infix_pos, infix_pos + #json_infix - 1) == json_infix then
        return j_decode(str_sub(v, infix_pos + #json_infix))
      elseif str_sub(v, infix_pos, infix_pos + #literal_infix - 1) == literal_infix then
        return str_sub(v, infix_pos + #literal_infix)
      elseif str_sub(v, infix_pos, infix_pos + #special_infix - 1) == special_infix then
        return special_table[str_sub(v, infix_pos + #special_infix)]
      else
        local def = v..definition_suffix
        return t[def]
      end
    else
      return v
    end
  end
  
  transform_table_back = function(t)
    local g, d
    for k, v in pairs(t) do
      local k2, v2 = transform_value_back(k, t), transform_value_back(v, t)
      if k ~= k2 then
        d = d or {}
        d[k] = true
        if k2 then
          g = g or {}
          g[k2] = v2
        end
      elseif v ~= v2 then
        t[k] = v2
      end
    end
    if d then
      for k in pairs(d) do
        t[k] = nil
      end
    end
    if g then
      for k, v in pairs(g) do
        t[k] = v
      end
    end
    return t
  end
  
  FW_TransformTableToStore = transform_table
  FW_RestoreTransformedTable = transform_table_back
end

-- ensure

do
  local function test_type(value, value_type)
    local number_type = m_type(value)
    return (number_type and number_type == value_type) or type(value) == value_type
  end
  
  local function get_type(value)
    return m_type(value) or type(value)
  end
  
  local function is_complex(value)
    local t = type(value)
    return t == 'table' or t == 'userdata' or t == 'function'
  end
  
  local validator_cache = setmetatable({}, {
    __mode = 'k'
  })
  
  local validator_integer_cache = {}
  
  local Ensure
  
  local function get_validator(func)
    if func == nil then
      return nil
    end
    if type(func) == 'function' then
      return func
    end
    if func ~= func then
      return Ensure(func)
    end
    local validator
    if m_type(func) == 'integer' then
      validator = validator_integer_cache[func]
      if not validator then
        validator = Ensure(func)
        validator_integer_cache[func] = validator
      end
    else
      validator = validator_cache[func]
      if not validator then
        validator = Ensure(func)
        validator_cache[func] = validator
      end
    end
    return validator
  end
  
  local DefaultValue = {}
  _ENV.Default = DefaultValue
  _ENV.DefaultValue = DefaultValue
  
  local DefaultKey = {}
  _ENV.DefaultKey = DefaultKey
  
  Ensure = function(default_value, ...)
    local value_type
    if select('#', ...) >= 1 then
      value_type = ...
      if default_value ~= nil and value_type and not test_type(default_value, value_type) then
        return error("Default value "..tostring(default_value).." does not match expected type "..tostring(value_type).."!")
      end
    else
      value_type = get_type(default_value)
    end
    local table_mt
    if default_value and value_type == 'table' then
      local function validate_key(key)
        if default_value[key] == nil then
          local key_validator = get_validator(default_value[DefaultKey])
          if key_validator then 
            return key_validator(key)
          end
        end
        return key
      end
      table_mt = {
        __index = function(self, key)
          key = validate_key(key)
          local old_value = rawget(self, key)
          if old_value ~= nil then
            return old_value
          end
          local validator = get_validator(default_value[key]) or get_validator(default_value[DefaultValue])
          if validator then
            local result = validator()
            if is_complex(result) and key ~= nil and key == key then
              rawset(self, key, result)
            end
            return result
          end
        end,
        __newindex = function(self, key, value)
          key = validate_key(key)
          if value ~= nil then
            local validator = get_validator(default_value[key]) or get_validator(default_value[DefaultValue])
            if validator then
              return rawset(self, key, validator(value))
            end
          end
          return rawset(self, key, value)
        end
      }
    end
    return function(tested)
      if value_type then
        if tested ~= nil and not test_type(tested, value_type) then
          if value_type == 'number' then
            tested = tonumber(tested)
          elseif value_type == 'integer' then
            tested = tonumber(tested)
            if tested then
              tested = m_modf(tested)
              tested = m_tointeger(tested)
            end
          elseif value_type == 'float' then
            tested = tonumber(tested)
            if tested then
              tested = tested + 0.0
            end
          elseif value_type == 'string' then
            tested = tostring(tested)
          else
            tested = nil
          end
        end
        
        if value_type == 'table' then
          tested = tested or {}
          if default_value then
            local default_value_validator = get_validator(default_value[DefaultValue])
            local default_key_validator = get_validator(default_value[DefaultKey])
            if default_key_validator or default_value_validator then
              local moved
              for k, v in pairs(tested) do
                if default_value[k] == nil then
                  if default_key_validator then
                    local new_k = default_key_validator(k)
                    if new_k ~= k then
                      if not moved then
                        moved = {}
                      end
                      moved[new_k] = v
                      tested[k] = nil
                    elseif default_value_validator then
                      tested[k] = default_value_validator(v)
                    end
                  elseif default_value_validator then
                    tested[k] = default_value_validator(v)
                  end
                end
              end
              if moved then
                for k, v in pairs(moved) do
                  if tested[k] == nil then
                    if default_value_validator and default_value[k] ~= nil then
                      v = default_value_validator(v)
                    end
                    tested[k] = v
                  end
                end
              end
            end
            for k, v in pairs(default_value) do
              if k ~= DefaultValue and k ~= DefaultKey then
                local value = tested[k]
                if value ~= nil then
                  tested[k] = get_validator(v)(value)
                end
              end
            end
          end
          if table_mt then
            setmetatable(tested, table_mt)
          end
        end
      end
      if tested == nil then
        tested = default_value
      end
      return tested
    end
  end
  _ENV.Ensure = Ensure
end

-- shared

local DoesEntityExist_orig = _ENV.DoesEntityExist

function DoesEntityExistSafe(id)
  local ok, result = pcall(DoesEntityExist_orig, id)
  return ok and result
end

local DoesEntityExist = _ENV.DoesEntityExistSafe

do
  local NetworkGetEntityFromNetworkId = _ENV.NetworkGetEntityFromNetworkId
  local NetworkDoesNetworkIdExist = _ENV.NetworkDoesNetworkIdExist or function() return true end

  function FW_GetEntityFromBag(bagName)
    local id, pos = s_gsub(bagName, '^localEntity:', '')
    if pos == 0 then
      id, pos = s_gsub(bagName, '^entity:', '')
      if pos == 0 then
        id = nil
      else
        id = tonumber(id)
        if id and NetworkDoesNetworkIdExist(id) then
          id = NetworkGetEntityFromNetworkId(id)
        else
          id = nil
        end
      end
    else
      id = tonumber(id)
    end
    if id and not DoesEntityExist(id) then
      return nil
    end
    return id
  end
  
  function FW_CheckTimeout(time1, time2, max)
    if not time1 then
      return 0, 1
    end
    time1, time2 = time2, time1 + time2
    if time2 >= (max or m_maxinteger) then
      return
    end
    Cfx_Wait(time2)
    return time1, time2
  end
end

-- miscellaneous

do
  local tr_table = {}
  local escape_char = '\27'
  
  local function pattern_replacer(value)
    if value == escape_char or u_codepoint(value) >= 128 then
      local rep = tr_table[value]
      if not rep then
        rep = #tr_table + 1
        if rep > 128 then
          return error("Too many distinct characters in patterns!")
        end
        tr_table[rep] = value
        rep = s_char(127 + rep)
        tr_table[value] = rep
      end
      return rep
    end
  end
  
  local function input_replacer(value)
    local ord = u_codepoint(value)
    if value == escape_char or ord >= 128 then
      return tr_table[value] or escape_char..ord..escape_char
    end
  end
  
  local function input_back_replacer(char, ord)
    if char == escape_char then
      ord = tonumber(ord)
      if ord then
        return u_char(ord)
      end
    end
    local rep = s_byte(char) - 127
    return tr_table[rep]
  end
  
  function TransformUtf8Pattern(pattern)
    return (s_gsub(pattern, u_charpattern, pattern_replacer))
  end
  
  function TransformUtf8(input)
    return (s_gsub(input, u_charpattern, input_replacer))
  end
  
  local back_pattern = '(['..escape_char..'\128-\255])([0-9]*)'..escape_char..'?'
  function TransformUtf8Back(input)
    return (s_gsub(input, back_pattern, input_back_replacer))
  end
end
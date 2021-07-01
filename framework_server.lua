-- imports

local t_pack = table.pack
local t_unpack_orig = table.unpack
local str_char = string.char
local str_find = string.find
local str_sub = string.sub
local m_random = math.random
local cor_yield = coroutine.yield
local str_format = string.format
local error = _ENV.error
local rawset = _ENV.rawset
local rawget = _ENV.rawget
local type = _ENV.type
local ipairs = _ENV.ipairs
local pairs = _ENV.pairs
local tostring = _ENV.tostring

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

local FW_RegisterCallback = _ENV.FW_RegisterCallback

function FW_RegisterServerCallback(name, eventname, ...)
  RegisterServerEvent(eventname)
  return FW_RegisterCallback(name, eventname, ...)
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
  return str_char(t_unpack(chars))
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
    TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(...), token)
  end
end

local function player_scheduler_factory_no_wait(name)
  return function(callback, player, ...)
    return callback(true, TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(...), nil))
  end
end

local function all_scheduler_factory(name)
  return function(callback, ...)
    return callback(true, TriggerClientEvent('fivework:ExecFunction', -1, name, t_pack(...), nil))
  end
end

local NetworkGetEntityOwner = _ENV.NetworkGetEntityOwner

local function owner_scheduler_factory(name)
  return function(callback, entity, ...)
    local player = NetworkGetEntityOwner(entity)
    if not player then return callback(false) end
    local token = newtoken()
    continuations[token] = function(...)
      continuations[token] = nil
      return callback(...)
    end
    TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(...), token)
  end
end

local function owner_scheduler_factory_no_wait(name)
  return function(callback, entity, ...)
    local player = NetworkGetEntityOwner(entity)
    if not player then return callback(false) end
    return callback(true, TriggerClientEvent('fivework:ExecFunction', player, name, t_pack(...), nil))
  end
end

local function iterator(obj)
  if type(obj) == 'table' then
    return ipairs(obj)
  elseif type(obj) == 'function' then
    return obj
  end
end

local function group_scheduler_factory(name)
  return function(callback, group, ...)
    local args = t_pack(...)
    for i, v in iterator(group) do
      TriggerClientEvent('fivework:ExecFunction', v, name, args, nil)
    end
    return callback(true)
  end
end

RegisterNetEvent('fivework:ExecFunctionResult')
AddEventHandler('fivework:ExecFunctionResult', function(status, args, token)
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

local func_patterns = {
  ['ForPlayer$'] = setmetatable({}, {
    __index = for_index(player_scheduler_factory)
  }),
  ['ForPlayerNoWait$'] = setmetatable({}, {
    __index = for_index(player_scheduler_factory_no_wait)
  }),
  ['ForAll$'] = setmetatable({}, {
    __index = for_index(all_scheduler_factory)
  }),
  ['ForGroup$'] = setmetatable({}, {
    __index = for_index(group_scheduler_factory)
  }),
  ['ForOwner$'] = setmetatable({}, {
    __index = for_index(owner_scheduler_factory)
  }),
  ['ForOwnerNoWait$'] = setmetatable({}, {
    __index = for_index(owner_scheduler_factory_no_wait)
  })
}

local function find_pattern_function(key)
  for pattern, t in pairs(func_patterns) do
    local i, j = str_find(key, pattern)
    if i then
      key = str_sub(key, 1, i - 1)..str_sub(key, j + 1)
      return t[key]
    end
  end
end

setmetatable(_ENV, {
  __index = function(self, key)
    if type(key) ~= 'string' then return nil end
    local result = find_pattern_function(key)
    if result then
      rawset(self, key, result)
      return result
    end
  end
})

-- chat utils

local function hexcolor(code)
  local b, g, r = code & 0xFF, (code >> 8) & 0xFF, (code >> 16) & 0xFF
  return {r, g, b}
end

function SendClientMessage(playerid, color, message)
  message = message or ""
  if type(message) ~= 'table' then
    message = tostring(message)
    if playerid == 0 then
      return print(message)
    end
    message = {message}
  elseif playerid == 0 then
    return print(t_unpack(message))
  end
  if type(color) == 'number' then
    color = hexcolor(color)
  end
  return TriggerClientEvent('chat:addMessage', playerid, {color = color, multiline = true, args = message})
end

local SendClientMessage = _ENV.SendClientMessage

function SendClientMessageToAll(...)
  return SendClientMessage(-1, ...)
end

local SendClientMessageToAll = _ENV.SendClientMessageToAll

function SendClientMessageFormat(playerid, color, format, ...)
  return SendClientMessage(playerid, color, str_format(format, ...))
end

function SendClientMessageToAllFormat(color, format, ...)
  return SendClientMessageToAll(color, str_format(format, ...))
end

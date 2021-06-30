-- imports

local t_pack = table.pack
local t_unpack_orig = table.unpack
local str_char = string.char
local m_random = math.random
local cor_yield = coroutine.yield
local str_format = string.format
local error = _ENV.error
local rawset = _ENV.rawset
local type = _ENV.type
local ipairs = _ENV.ipairs
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
    TriggerClientEvent('fivework:ExecFunction', player, name, token, t_pack(...))
  end
end

local function player_scheduler_factory_no_wait(name)
  return function(callback, player, ...)
    return callback(true, TriggerClientEvent('fivework:ExecFunction', player, name, nil, t_pack(...)))
  end
end

local function all_scheduler_factory(name)
  return function(callback, ...)
    return callback(true, TriggerClientEvent('fivework:ExecFunction', -1, name, nil, t_pack(...)))
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
      TriggerClientEvent('fivework:ExecFunction', v, name, nil, args)
    end
    return callback(true)
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

ForPlayerNoWait = setmetatable({}, {
  __index = for_index(player_scheduler_factory_no_wait)
})

ForAll = setmetatable({}, {
  __index = for_index(all_scheduler_factory)
})

ForGroup = setmetatable({}, {
  __index = for_index(group_scheduler_factory)
})

function FW_UseFunction(name)
  _ENV[name..'ForPlayer'] = ForPlayer[name]
  _ENV[name..'ForPlayerNoWait'] = ForPlayerNoWait[name]
  _ENV[name..'ForAll'] = ForAll[name]
  _ENV[name..'ForGroup'] = ForGroup[name]
end

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

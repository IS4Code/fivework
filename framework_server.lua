-- imports

local t_pack = table.pack
local t_unpack_orig = table.unpack
local t_insert = table.insert
local str_char = string.char
local str_find = string.find
local str_sub = string.sub
local m_random = math.random
local str_format = string.format
local error = _ENV.error
local rawset = _ENV.rawset
local rawget = _ENV.rawget
local type = _ENV.type
local pcall = _ENV.pcall
local xpcall = _ENV.xpcall
local m_type = math.type
local m_huge = math.huge
local ipairs = _ENV.ipairs
local pairs = _ENV.pairs
local tostring = _ENV.tostring
local tonumber = _ENV.tonumber
local setmetatable = _ENV.setmetatable
local select = _ENV.select
local m_huge = math.huge
local j_encode = json.encode
local j_decode = json.decode
local cor_wrap = coroutine.wrap
local cor_yield = coroutine.yield
local FW_Schedule = _ENV.FW_Schedule
local Entity = _ENV.Entity
local vec3 = _ENV.vec3

local CancelEvent = _ENV.CancelEvent
local TriggerClientEvent = _ENV.TriggerClientEvent
local GetGameTimer = _ENV.GetGameTimer
local Entity = _ENV.Entity

local Cfx_Wait = Citizen.Wait
local Cfx_CreateThread = Citizen.CreateThread

local FW_Async = _ENV.FW_Async
local FW_TryCall = _ENV.FW_TryCall
local FW_TransformTableToStore = _ENV.FW_TransformTableToStore
local FW_SetTimeout = _ENV.FW_SetTimeout

local function t_unpack(t, i)
  return t_unpack_orig(t, i or 1, t.n)
end

local function iterator(obj)
  if type(obj) == 'table' then
    return ipairs(obj)
  elseif type(obj) == 'function' then
    return obj()
  end
end

local function error_or_return(status, ...)
  if not status then
    return error(tostring(...))
  end
  return ...
end

-- observers

local retrieve_observed_state, get_observed_state
do
  local observed_state = {}

  retrieve_observed_state = function(player, args)
    if args then
      local state = args.state
      if state then
        local stored = observed_state[player]
        if not stored then
          stored = {}
          observed_state[player] = stored
        end
        for k, v in pairs(state) do
          stored[k] = {GetGameTimer(), v}
        end
      end
    end
  end
  
  get_observed_state = function(player, ...)
    local state = observed_state[player]
    if state then
      return state[j_encode{...}]
    end
  end
  
  function FW_GetObservedStateUpdateTime(...)
    local state = get_observed_state(...)
    if state then
      return GetGameTimer() - state[1]
    end
  end
  
  AddEventHandler('playerDropped', function()
    local source = _ENV.source
    local stored = observed_state[source]
    if stored then
      FW_SetTimeout(0, function()
        if observed_state[source] == stored then
          observed_state[source] = nil
        end
      end)
    end
  end)
end

-- callbacks

do
  local callback_info = FW_CallbackHandlers
  
  local function warn_if_registered(name)
    if callback_info[name] then
      return error("Callback '"..tostring(name).."' is already registered!")
    end
  end
  
  local net_callback_handlers = {}
  
  function FW_RegisterCallback(name, eventname, has_source, processor)
    warn_if_registered(name)
    callback_info[name] = function(handler)
      if processor then
        local handler_old = handler
        handler = function(...)
          return handler_old(processor(...))
        end
      end
      AddEventHandler(eventname, function(...)
        local result
        if has_source then
          result = handler(_ENV.source, ...)
        else
          result = handler(...)
        end
        if result == false then
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
  
  function FW_RegisterPlainCallback(name)
    warn_if_registered(name)
    callback_info[name] = function()
      return true
    end
  end
  
  function FW_RegisterNetCallback(name, processor)
    warn_if_registered(name)
    callback_info[name] = function(handler)
      if processor then
        local handler_old = handler
        handler = function(...)
          return handler_old(processor(...))
        end
      end
      net_callback_handlers[name] = handler
    end
  end
  
  RegisterNetEvent('fivework:ClientCallbacks')
  AddEventHandler('fivework:ClientCallbacks', function(data)
    local source = _ENV.source
    
    local i = 1
    local count = #data
    local name
    
    local function process()
      while i <= count do
        local record = data[i]
        i = i + 1
        
        local args
        name, args = t_unpack(record)
        if not callback_info[name] then
          FW_TriggerCallback('OnUnregisteredNetCallback', source, name, args)
        else
          retrieve_observed_state(source, args)
          
          local handler = net_callback_handlers[name]
          if handler then
            handler(source, t_unpack(args))
          end
        end
      end
    end
    
    repeat
      local ok, msg = xpcall(process, FW_Traceback)
      if not ok then
        FW_ErrorLog("Error in callback "..name..":\n", msg)
      end
    until ok
  end)
end

-- remote execution

local GetPlayers = _ENV.GetPlayers

function AllPlayers()
  return cor_wrap(function()
    for _, playerid in ipairs(GetPlayers()) do 
      cor_yield(tonumber(playerid) or playerid)
    end
  end)
end

local AllPlayers = _ENV.AllPlayers

local NetworkGetEntityOwner = _ENV.NetworkGetEntityOwner
local NetworkGetNetworkIdFromEntity = _ENV.NetworkGetNetworkIdFromEntity

local newid_chars = {}
local function newid()
  for i = 1, 32 do
    newid_chars[i] = m_random(33, 126)
  end
  return str_char(t_unpack(newid_chars))
end

local function newtoken(continuations)
  local token
  repeat
    token = newid()
  until not continuations[token]
  return token
end

do
  local player_continuations = {}
  
  local function get_continuations(player)
    local continuations = player_continuations[player]
    if not continuations then
      continuations = {}
      player_continuations[player] = continuations
    end
    return continuations
  end
  
  local error_dropped = {}
  
  local function newtask(stack)
    local callbacks
    local result
    local function subscribe(callback)
      if result then
        return callback(t_unpack(result))
      else
        if not callbacks then
          callbacks = {callback}
        else
          t_insert(callbacks, callback)
        end
      end
    end
    local function complete(ok, ...)
      local ok_result
      if ok == error_dropped then
        ok_result = false
      else
        ok_result = ok
      end
      result = t_pack(ok_result, ...)
      local handled = false
      if callbacks then
        for _, callback in ipairs(callbacks) do
          callback(ok_result, ...)
          handled = true
        end
      end
      if not handled and not ok then
        stack.error = ...
        error(stack)
      end
      return handled
    end
    return subscribe, complete
  end
  
  local exec_queue = {}
  
  local max_queue_size = 200
  
  function FW_SetRemoteCallQueueMaxSize(len)
    max_queue_size = len or m_huge
  end
  
  local function remote_exec_function(player, ...)
    local queue = exec_queue[player]
    if not queue then
      queue = {}
      exec_queue[player] = queue
      FW_SetTimeout(0, function()
        if exec_queue[player] == queue then
          -- Reset if a new queue was not created (might happen if code runs between two scheduled executions)
          exec_queue[player] = nil
        end
        TriggerClientEvent('fivework:ExecFunctions', player, queue)
      end)
    end
    t_insert(queue, {...})
    if #queue >= max_queue_size then
      -- Reset the queue (timer will still send the old one)
      exec_queue[player] = nil
    end
  end
  
  local empty_pack = t_pack()
  local function pack_args(...)
    local first = ...
    if first == nil and select('#', ...) == 0 then
      return empty_pack
    end
    local args = t_pack(...)
    for i = 1, args.n do
      local v = args[i]
      if type(v) == 'table' then
        args[i] = FW_Pack(v)
      end
    end
    return args
  end
  
  local function player_task_factory(name, transform, stack_level, player, ...)
    local continuations = get_continuations(player)
    local token = newtoken(continuations)
    local stack = stack_level and FW_StackDump(nil, stack_level)
    local subscribe, complete = newtask(stack)
    continuations[token] = function(...)
      continuations[token] = nil
      return complete(...)
    end
    remote_exec_function(player, name, pack_args(...), token)
    return transform(subscribe)
  end
  
  local function player_discard_factory(name, transform, stack_level, player, ...)
    return remote_exec_function(player, name, pack_args(...))
  end
  
  local group_table_mt = {
    __index = function(self, key)
      if type(key) == 'string' then
        local as_num = tonumber(key)
        if as_num then
          return rawget(self, as_num)
        end
      else
        local as_str = tostring(key)
        if as_str then
          return rawget(self, as_str)
        end
      end
    end
  }
  
  local function group_task_factory(name, transform, stack_level, group, ...)
    local args = pack_args(...)
    local results = setmetatable({}, group_table_mt)
    local stack = stack_level and FW_StackDump(nil, stack_level)
    for i, v in iterator(group) do
      local player = v or i
      
      local continuations = get_continuations(player)
      local token = newtoken(continuations)
      local subscribe, complete = newtask(stack)
      continuations[token] = function(...)
        continuations[token] = nil
        return complete(...)
      end
      remote_exec_function(player, name, args, token)
      results[player] = transform(subscribe)
    end
    return results
  end
  
  local function group_discard_factory(name, transform, stack_level, group, ...)
    local args = pack_args(...)
    for i, v in iterator(group) do
      local player = v or i
      remote_exec_function(player, name, args)
    end
  end
  
  local function all_task_factory(name, transform, stack_level, ...)
    return group_task_factory(name, transform, stack_level and stack_level + 1, AllPlayers, ...)
  end
  
  local function all_discard_factory(name, transform, stack_level, ...)
    return group_discard_factory(name, transform, stack_level and stack_level + 1, AllPlayers, ...)
  end
  
  local function owner_task_factory(name, transform, stack_level, entity, ...)
    local player = NetworkGetEntityOwner(entity)
    if not player then return end
    entity = NetworkGetNetworkIdFromEntity(entity)
    return player_task_factory(name..'NetworkIdIn1', transform, stack_level and stack_level + 1, player, entity, ...)
  end
  
  local function owner_discard_factory(name, transform, stack_level, entity, ...)
    local player = NetworkGetEntityOwner(entity)
    if not player then return end
    entity = NetworkGetNetworkIdFromEntity(entity)
    return player_discard_factory(name..'NetworkIdIn1', transform, stack_level and stack_level + 1, player, entity, ...)
  end
  
  RegisterNetEvent('fivework:ExecFunctionResults')
  AddEventHandler('fivework:ExecFunctionResults', function(data)
    local source = _ENV.source
    
    local i = 1
    local count = #data
    
    local function process()
      while i <= count do
        local record = data[i]
        i = i + 1
    
        local status, args, token = t_unpack(record)
        retrieve_observed_state(source, args)
        
        local continuations = player_continuations[source]
        if continuations then
          local handler = continuations[token]
          if handler then
            local result = handler(status, t_unpack(args))
            if result then
              status = true
            end
          end
        end
        if not status then
          FW_ErrorLog("Error from unhandled asynchronous call:\n", t_unpack(args))
        end
      end
    end
    
    repeat
      local ok, msg = xpcall(process, FW_Traceback)
      if not ok then
        FW_ErrorLog("Error in asynchronous continuation:\n", msg)
      end
    until ok
  end)
  
  AddEventHandler('playerDropped', function(reason)
    local source = _ENV.source
    local continuations = player_continuations[source]
    if continuations then
      player_continuations[source] = nil
      for token, handler in pairs(continuations) do
        local ok, msg = xpcall(handler, FW_Traceback, error_dropped, "player dropped: "..tostring(reason))
        if not ok then
          FW_ErrorLog("Error in asynchronous continuation:\n", msg)
        end
      end
    end
  end)
  
  local function timeout_scheduler(callback, timeout, scheduler)
    local fired
    local function finished(...)
      if not fired then
        fired = true
        return callback(...)
      end
    end
    FW_SetTimeout(timeout, function()
      return finished(false, "timeout "..tostring(timeout).." hit")
    end)
    return scheduler(finished)
  end
  
  local function transform_subscribe(subscribe)
    return function(timeout)
      if timeout then
        return error_or_return(FW_Schedule(timeout_scheduler, timeout, subscribe))
      end
      return error_or_return(FW_Schedule(subscribe))
    end
  end
  
  local global_timeout
  
  function FW_SetWaitTimeout(timeout)
    global_timeout = timeout
  end
  
  local function call_result(factory)
    return function(key)
      return function(...)
        return factory(key, transform_subscribe, nil, ...)(global_timeout)
      end
    end
  end
  
  local function try_call_result(factory)
    return function(key)
      return function(...)
        return pcall(factory(key, transform_subscribe, nil, ...), global_timeout)
      end
    end
  end
  
  local function timeout_call_result(factory)
    return function(key)
      return function(arg1, timeout, ...)
        return factory(key, transform_subscribe, nil, arg1, ...)(timeout)
      end
    end
  end
  
  local function try_timeout_call_result(factory)
    return function(key)
      return function(arg1, timeout, ...)
        return pcall(factory(key, transform_subscribe, nil, arg1, ...), timeout)
      end
    end
  end
  
  local function pass_result(factory)
    return function(key)
      return function(...)
        return factory(key, transform_subscribe, 2, ...)
      end
    end
  end
  
  local init_key = 'fw:ei'
  
  local active_spawners = {}
  
  local token_spawners = setmetatable({}, {
    __mode = 'v'
  })
  
  local entity_spawners = setmetatable({}, {
    __mode = 'v'
  })
  
  function FW_GetEntitySpawner(entity)
    return entity_spawners[entity]
  end
  
  function FW_EligibleSpawnerPlayers(x, y, z, bucket)
    return AllPlayers()
  end
  
  local DoesEntityExist = _ENV.DoesEntityExistSafe
  local SetEntityRoutingBucket = _ENV.SetEntityRoutingBucket
  local GetPlayerRoutingBucket = _ENV.GetPlayerRoutingBucket
  local GetPlayerPed = _ENV.GetPlayerPed
  local DeleteEntity = _ENV.DeleteEntity
  local GetEntityCoords = _ENV.GetEntityCoords
  local GetEntityRotation = _ENV.GetEntityRotation
  local GetEntityHealth = _ENV.GetEntityHealth
  local NetworkGetEntityOwner = _ENV.NetworkGetEntityOwner
  
  local entity_last_state = setmetatable({}, {})
  
  local entity_last_state_weak = setmetatable({}, {
    __mode = 'v'
  })
  
  AddEventHandler('entityRemoved', function(entity)
    local state = entity_last_state[entity]
    if state then
      entity_last_state[entity] = nil
      entity_last_state_weak[entity] = state
    end
    
    local data = entity_spawners[entity]
    if data then
      data.removed()
    end
  end)
  
  function StoreEntityLastState(entity)
    entity_last_state[entity] = Entity(entity).state
  end
  
  function GetEntityLastState(entity)
    return entity_last_state[entity] or entity_last_state_weak[entity]
  end
  
  local entity_state_known_keys = setmetatable({
    [init_key] = true
  }, {
    __mode = 'k'
  })
  
  function GetEntityStateKnownKeys()
    return pairs(entity_state_known_keys)
  end
  
  function AddEntityStateKnownKey(key)
    entity_state_known_keys[key] = true
  end
  
  local function create_spawner(fname, model, x, y, z, bucket, ...)
    local data = {}
    active_spawners[data] = true
    local spawn_args = t_pack(model, x, y, z, ...)
    local entity
    local is_deleting
    local parent
    bucket = bucket or 0
    
    local set_rotation = SetEntityRotationForEntitySpawner
    local set_health = SetEntityHealthForEntitySpawner
    
    local state_data = {}
    
    local state = setmetatable({}, {
      __newindex = function(self, key, value)
        state_data[key] = value
        entity_state_known_keys[key] = true
        if entity and DoesEntityExist(entity) then
          local state = Entity(entity).state
          entity_last_state[entity] = state
          state[key] = value
        end
      end,
      __index = function(self, key)
        return state_data[key]
      end
    })
    data.state = state
    
    local children = {}
    data.children = children
    
    data.entity = setmetatable({}, {
      __tostring = function(self)
        return tostring(self.__data)
      end
    })
    
    data.netid = setmetatable({}, {
      __tostring = function(self)
        return tostring(self.__data)
      end
    })
    
    function data.removed()
      FW_DebugLog("Entity", entity, "for spawner", data, "is being removed")
      local rotation, health
      if not is_deleting and entity and DoesEntityExist(entity) then
        local pos = GetEntityCoords(entity)
        x, y, z = pos.x, pos.y, pos.z
        spawn_args[2] = x
        spawn_args[3] = y
        spawn_args[4] = z
        rotation = GetEntityRotation(entity)
        health = GetEntityHealth(entity)
        FW_DebugLog("Preserved state", pos, rotation, health)
      end
      data.set_entity(nil)
      if is_deleting then
        active_spawners[data] = nil
      end
      if rotation then
        set_rotation(data, rotation.x, rotation.y, rotation.z, 2, true)
      end
      if health then
        set_health(data, health)
      end
    end
    
    function data.delete()
      is_deleting = true
      if entity then
        if DoesEntityExist(entity) then
          active_spawners[data] = false
          DeleteEntity(entity)
          return
        else
          data.set_entity(nil)
        end
      end
      active_spawners[data] = nil
    end
    
    local bad_players = {}
    
    function data.set_entity(id, netid)
      if entity then
        entity_spawners[entity] = nil
      end
      
      FW_DebugLog("Changing entity for", data, "from", entity, "to", id)
      
      data.entity.__data = id
      data.netid.__data = netid
      entity = id
      bad_players = {}
      
      if id then
        entity_spawners[id] = data
        if DoesEntityExist(id) then
          Entity(id).state[init_key] = state[init_key]
        end
      end
    end
    
    function data.set_parent(new_parent)
      local old_parent = data.parent
      if old_parent then
        old_parent.children[data] = nil
      end
      data.parent = new_parent
      parent = new_parent
      if new_parent then
        new_parent.children[data] = true
      end
    end
    
    function data.set_bucket(newbucket)
      bucket = newbucket
      if entity and DoesEntityExist(entity) then
        SetEntityRoutingBucket(entity, newbucket)
      end
    end
    
    function data.get_bucket()
      return bucket
    end
    
    local spawning_time
    local spawning_player
    local token
    
    function data.spawned(id, netid)
      token_spawners[token] = nil
      token = nil
      spawning_time = nil
      spawning_player = nil
      data.set_entity(id, netid)
    end
    
    function data.parent_removed()
      if entity and not DoesEntityExist(entity) then
        data.set_entity(nil)
      end
      if entity then
        local removed_entity = entity
        data.removed()
        DeleteEntity(entity)
      end
    end
    
    function data.update(parent_player)
      if is_deleting then
        return
      end
      if entity and not DoesEntityExist(entity) then
        data.set_entity(nil)
      end
      if parent and not parent_player then
        return
      end
      if spawning_time then
        if GetGameTimer() - spawning_time > 3000 then
          FW_DebugLog("Player", spawning_player, "did not spawn entity", fname, data, "within 3s timeout, looking for another...")
          spawning_time = nil
          bad_players[spawning_player] = 6
          spawning_player = nil
          token_spawners[token] = nil
          token = nil
        else
          return
        end
      end
      if not entity then
        x, y, z = t_unpack(spawn_args, 2)
        local min_player
        
        if parent_player then
          min_player = parent_player
        else
          local pos = vec3(x, y, z)
          local min_dist = m_huge
          
          for player in FW_EligibleSpawnerPlayers(x, y, z, bucket) do
            local bad_score = bad_players[player]
            if bad_score then
              bad_score = bad_score - 1
              if bad_score <= 0 then
                bad_score = nil
              end
              bad_players[player] = bad_score
            end
          
            if not bad_score and GetPlayerRoutingBucket(player) == bucket then
              local ped = GetPlayerPed(player)
              if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                local dist = #(coords - pos)
                if dist < min_dist then
                  min_dist = dist
                  min_player = player
                end
              end
            end
          end
        end
        
        if min_player then
          spawning_time = GetGameTimer()
          spawning_player = min_player
          token = newtoken(token_spawners)
          token_spawners[token] = data
          
          FW_DebugLog("Spawning", fname, data, "for player", min_player)
          TriggerClientEvent('fivework:SpawnEntity', min_player, token, fname, spawn_args)
        end
        
        for k in pairs(children) do
          k.parent_removed()
        end
      else
        local owner = NetworkGetEntityOwner(entity)
        if owner then
          for k in pairs(children) do
            if active_spawners[k] then
              k.update(owner)
            end
          end
        end
      end
    end
    return data
  end
  
  function SetEntitySpawnerRoutingBucket(spawner, bucket)
    return spawner.set_bucket(bucket)
  end
  
  function GetEntitySpawnerRoutingBucket(spawner)
    return spawner.get_bucket()
  end
  
  function GetEntitySpawnerEntity(spawner)
    return spawner.entity
  end
  
  function GetEntitySpawnerNetworkId(spawner)
    return spawner.netid
  end
  
  function DeleteEntitySpawner(spawner)
    return spawner.delete()
  end
  
  function SetEntitySpawnerParent(spawner, parent)
    return spawner.set_parent(parent)
  end
  
  function GetEntitySpawnerParent(spawner)
    return spawner.parent
  end
  
  Cfx_CreateThread(function()
    while true do
      Cfx_Wait(500)
      for k, v in pairs(active_spawners) do
        if v then
          FW_TryCall(k.update)
        end
      end
    end
  end)
  
  local check_timeout = FW_CheckTimeout
  
  local NetworkGetEntityFromNetworkId = _ENV.NetworkGetEntityFromNetworkId
  
  RegisterNetEvent('fivework:EntitySpawned')
  AddEventHandler('fivework:EntitySpawned', function(netid, token)
    local source = _ENV.source
    local spawner = token_spawners[token]
    
    FW_DebugLog("Spawned entity with netid", netid, "for", spawner, "by player", source)
  
    local id = NetworkGetEntityFromNetworkId(netid)
    local a, b = check_timeout()
    while not DoesEntityExist(id) do
      a, b = check_timeout(a, b, 1000)
      if not a then
        FW_DebugLog("Spawned entity did not appear within 1s timeout")
        return
      end
      id = NetworkGetEntityFromNetworkId(netid)
    end
    
    if spawner and token_spawners[token] == spawner then
      FW_DebugLog("Successfully assigned entity", id, "to", spawner)
      spawner.spawned(id, netid)
    else
      FW_DebugLog("Entity", id, "does not belong to any spawner, deleting...")
      DeleteEntity(id)
    end
  end)
  
  local function clear_state(state)
    local init = state[init_key]
    if init then
      local clock = (init._cl or -1) + 1
      state[init_key] = {_cl = clock}
    end
  end
  
  function ClearEntityInitState(entity)
    return clear_state(Entity(entity).state)
  end
  
  function ClearEntitySpawnerInitState(spawner)
    return clear_state(spawner.state)
  end
  
  local function update_state(state, data)
    local init = state[init_key]
    if init then
      local clock = (init._cl or -1) + 1
      data._cl = clock
    end
    state[init_key] = data
  end
  
  function UpdateEntityInitState(entity, data)
    return update_state(Entity(entity).state, data)
  end
  
  function UpdateEntitySpawnerInitState(spawner, data)
    return update_state(spawner.state, data)
  end
  
  local entity_init_changed_handler, spawner_init_changed_handler
  
  function SetEntityInitStateChangedHandler(handler)
    entity_init_changed_handler = handler
  end
  
  function SetEntitySpawnerInitStateChangedHandler(handler)
    spawner_init_changed_handler = handler
  end
  
  local function add_state(state, key, fname, once, for_owner, args)
    local init = state[init_key]
    if not init then
      init = {}
    end
    local clock = (init._cl or -1) + 1
    init._cl = clock
    local data
    if args then
      data = {fname, clock, once, for_owner, args}
    end
    if not key and data then
      t_insert(init, data)
    else
      init[key] = data
    end
    state[init_key] = init
    return init
  end
  
  local function add_entity_state(entity, key, fname, once, for_owner, args)
    local state = Entity(entity).state
    entity_last_state[entity] = state
    local init = add_state(state, key, fname, once, for_owner, args)
    if entity_init_changed_handler then
      entity_init_changed_handler(entity, init)
    end
  end
  
  local function add_entity_spawner_state(spawner, key, fname, once, for_owner, args)
    local state = spawner.state
    local init = add_state(state, key, fname, once, for_owner, args)
    if spawner_init_changed_handler then
      spawner_init_changed_handler(entity, init)
    end
  end
  
  local function set_entity_state(adder, fname, entity, key_length, once, reset, for_owner, ...)
    local args
    if not reset then
      args = t_pack(nil, ...)
    end
    if not key_length then
      return adder(entity, nil, fname, once, args)
    else
      local key_parts = {fname, ...}
      for i = key_length + 2, #key_parts do
        key_parts[i] = nil
      end
      return adder(entity, j_encode(key_parts), fname, once, for_owner, args)
    end
  end
  
  local function entity_state_result(adder, has_key, once, reset, for_owner)
    return function(fname)
      if has_key then
        return function(entity, key_length, ...)
          return set_entity_state(adder, fname, entity, key_length, once, reset, for_owner, ...)
        end
      else
        return function(entity, ...)
          return set_entity_state(adder, fname, entity, 0, once, reset, for_owner, ...)
        end
      end
    end
  end
  
  local func_patterns = {
    ['ForPlayer$'] = pass_result(player_task_factory),
    ['ForPlayerWait$'] = call_result(player_task_factory),
    ['ForPlayerTryWait$'] = try_call_result(player_task_factory),
    ['ForPlayerTimeout$'] = timeout_call_result(player_task_factory),
    ['ForPlayerTryTimeout$'] = try_timeout_call_result(player_task_factory),
    ['ForPlayerDiscard$'] = pass_result(player_discard_factory),
    ['ForAll$'] = pass_result(all_task_factory),
    ['ForAllDiscard$'] = pass_result(all_discard_factory),
    ['ForGroup$'] = pass_result(group_task_factory),
    ['ForGroupDiscard$'] = pass_result(group_discard_factory),
    ['ForOwner$'] = pass_result(owner_task_factory),
    ['ForOwnerWait$'] = call_result(owner_task_factory),
    ['ForOwnerTryWait$'] = try_call_result(owner_task_factory),
    ['ForOwnerTimeout$'] = timeout_call_result(owner_task_factory),
    ['ForOwnerTryTimeout$'] = try_timeout_call_result(owner_task_factory),
    ['ForOwnerDiscard$'] = pass_result(owner_discard_factory),
    ['ForEntity$'] = entity_state_result(add_entity_state, false, false, false, false),
    ['ForEntityOnce$'] = entity_state_result(add_entity_state, false, true, false, false),
    ['ForEntityKey$'] = entity_state_result(add_entity_state, true, false, false, false),
    ['ForEntityOnceKey$'] = entity_state_result(add_entity_state, true, true, false, false),
    ['ForEntityOwner$'] = entity_state_result(add_entity_state, false, false, false, true),
    ['ForEntityOwnerOnce$'] = entity_state_result(add_entity_state, false, true, false, true),
    ['ForEntityOwnerKey$'] = entity_state_result(add_entity_state, true, false, false, true),
    ['ForEntityOwnerOnceKey$'] = entity_state_result(add_entity_state, true, true, false, true),
    ['ForEntityNot$'] = entity_state_result(add_entity_state, false, false, true, false),
    ['ForEntityNotKey$'] = entity_state_result(add_entity_state, true, false, true, false),
    ['ForEntitySpawner$'] = entity_state_result(add_entity_spawner_state, false, false, false, false),
    ['ForEntitySpawnerOnce$'] = entity_state_result(add_entity_spawner_state, false, true, false, false),
    ['ForEntitySpawnerKey$'] = entity_state_result(add_entity_spawner_state, true, false, false, false),
    ['ForEntitySpawnerOnceKey$'] = entity_state_result(add_entity_spawner_state, true, true, false, false),
    ['ForEntitySpawnerOwner$'] = entity_state_result(add_entity_spawner_state, false, false, false, true),
    ['ForEntitySpawnerOwnerOnce$'] = entity_state_result(add_entity_spawner_state, false, true, false, true),
    ['ForEntitySpawnerOwnerKey$'] = entity_state_result(add_entity_spawner_state, true, false, false, true),
    ['ForEntitySpawnerOwnerOnceKey$'] = entity_state_result(add_entity_spawner_state, true, true, false, true),
    ['ForEntitySpawnerNot$'] = entity_state_result(add_entity_spawner_state, false, false, true, false),
    ['ForEntitySpawnerNotKey$'] = entity_state_result(add_entity_spawner_state, true, false, true, false),
    ['NewSpawner$'] = function(fname)
      return function(model, x, y, z, bucket, ...)
        return create_spawner(fname, model, x, y, z, bucket, ...)
      end
    end,
    ['FromPlayer$'] = function(key)
      return function(player, ...)
        local state = get_observed_state(player, key, ...)
        if state then
          return error_or_return(t_unpack(state[2]))
        end
      end
    end
  }
  
  FW_FuncPatterns = func_patterns
  
  local function find_pattern_function(key)
    for pattern, proc in pairs(func_patterns) do
      local i, j = str_find(key, pattern)
      if i then
        local newkey = str_sub(key, 1, i - 1)..str_sub(key, j + 1)
        local f = proc(newkey)
        if f then
          return f
        end
      end
    end
  end
  
  local registered_globals = {source = true}
  local warn_on_global_access
  
  function FW_GlobalInitializationDone()
    for k, v in pairs(_ENV) do
      if type(k) == 'string' then
        registered_globals[k] = true
      end
    end
    warn_on_global_access = true
  end
  
  function FW_DefaultGlobal(declared)
    return nil
  end
  
  local old_global_mt = getmetatable(_ENV)
  setmetatable(_ENV, {
    __index = function(self, key)
      if old_global_mt then
        local indexer = old_global_mt.__index
        if indexer then
          local existing = indexer(self, key)
          if existing ~= nil then
            return existing
          end
        end
      end
      if type(key) ~= 'string' then return nil end
      local result = find_pattern_function(key)
      if result then
        rawset(self, key, result)
        return result
      end
      if warn_on_global_access and not registered_globals[key] then
        FW_WarningLog("Global '"..key.."' not declared before retrieval, at:\n", FW_Traceback(nil, 2))
        return FW_DefaultGlobal(false)
      end
      return FW_DefaultGlobal(true)
    end,
    __newindex = function(self, key, value)
      if type(key) == 'string' then
        if warn_on_global_access and not registered_globals[key] then
          FW_WarningLog("Global '"..key.."' not declared before assignment to "..tostring(value)..", at:\n", FW_Traceback(nil, 2))
        end
        registered_globals[key] = true
      end
      if old_global_mt then
        local newindexer = old_global_mt.__newindex
        if newindexer then
          return newindexer(self, key, value)
        end
      end
      return rawset(self, key, value)
    end
  })
end

-- chat utils

do
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
    local info = {color = color, multiline = true, args = {t_unpack(message)}}
    for k, v in pairs(message) do
      if type(k) ~= 'number' then
        info[k] = v
      end
    end
    return TriggerClientEvent('chat:addMessage', playerid, info)
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
end

-- serialization

do
  local FW_RestoreTransformedTable = _ENV.FW_RestoreTransformedTable
  local SaveResourceFile = _ENV.SaveResourceFile
  local LoadResourceFile = _ENV.LoadResourceFile
  
  function SaveResourceData(name, file, ...)
    local data = j_encode(FW_TransformTableToStore(t_pack(...)))
    if not data or data == '' then
      return error('invalid data returned from json.encode')
    end
    return SaveResourceFile(name, file, data, #data)
  end
  
  function LoadResourceData(name, file)
    local data = LoadResourceFile(name, file)
    if data and data ~= '' then
      local obj = j_decode(data)
      if not obj then
        return error('invalid data encountered in file '..name..":\n"..data)
      end
      return t_unpack(FW_RestoreTransformedTable(obj))
    end
  end
  
  local GetCurrentResourceName = _ENV.GetCurrentResourceName
  
  function SaveScriptData(...)
    return SaveResourceData(GetCurrentResourceName(), ...)
  end
  
  function LoadScriptData(...)
    return LoadResourceData(GetCurrentResourceName(), ...)
  end
end

-- misc

local GetNumPlayerIdentifiers = _ENV.GetNumPlayerIdentifiers
local GetPlayerIdentifier = _ENV.GetPlayerIdentifier

function PlayerIdentifiers(player)
  return cor_wrap(function()
    local num = GetNumPlayerIdentifiers(player)
    for i = 0, num-1 do
      local id = GetPlayerIdentifier(player, i)
      if id then
        local i, j = str_find(id, ':')
        if i then
          cor_yield(str_sub(id, 1, i - 1), str_sub(id, j + 1))
        end
      end
    end
  end)
end

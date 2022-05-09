local NetworkGetEntityFromNetworkId = _ENV.NetworkGetEntityFromNetworkId
local t_unpack = table.unpack

FW_RegisterCallback('OnEntityCreated', 'entityCreated')
FW_RegisterCallback('OnEntityCreating', 'entityCreating')
FW_RegisterCallback('OnResourceStart', 'onResourceStart')
FW_RegisterCallback('OnResourceStop', 'onResourceStop')
FW_RegisterNetCallback('OnPlayerConnect')
FW_RegisterCallback('OnPlayerDisconnect', 'playerDropped', true)
FW_RegisterCallback('OnIncomingConnection', 'playerConnecting', true)
FW_RegisterServerCallback('OnPlayerEnterVehicle', 'baseevents:enteredVehicle', true, function(source, localid, seat, modelkey, networkid, ...)
  return source, NetworkGetEntityFromNetworkId(networkid), seat, networkid, localid, modelkey, ...
end)
FW_RegisterServerCallback('OnPlayerExitVehicle', 'baseevents:leftVehicle', true, function(source, localid, seat, modelkey, networkid, ...)
  return source, NetworkGetEntityFromNetworkId(networkid), seat, networkid, localid, modelkey, ...
end)
FW_RegisterNetCallback('OnPlayerInit')
FW_RegisterNetCallback('OnPlayerActivate')
FW_RegisterNetCallback('OnPlayerSpawn')
FW_RegisterNetCallback('OnGameEvent', function(source, name, args)
  return source, name, t_unpack(args)
end)
FW_RegisterNetCallback('OnPlayerKeyStateChange')

FW_RegisterCallback('OnPlayerText', 'chatMessage', false, function(source, author, message, ...)
  return source, message, author, ...
end)

FW_RegisterPlainCallback('OnPlayerDeath')
FW_RegisterNetCallback('OnPlayerUpdate')
FW_RegisterPlainCallback('OnPlayerReceivedCommand')
FW_RegisterPlainCallback('OnPlayerPerformedCommand')
FW_RegisterPlainCallback('OnScriptInit')
FW_RegisterPlainCallback('OnScriptExit')

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then
    FW_TriggerCallback('OnScriptInit')
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    FW_TriggerCallback('OnScriptExit')
  end
end)

RegisterServerEvent('baseevents:onPlayerDied')
AddEventHandler('baseevents:onPlayerDied', function(killertype, killerpos)
  FW_TriggerCallback('OnPlayerDeath', source, killertype, nil, killerpos, {})
end)

RegisterServerEvent('baseevents:onPlayerKilled')
AddEventHandler('baseevents:onPlayerKilled', function(killerid, data)
  local killertype, killerpos = data.killertype, data.killerpos
  data.killertype, data.killerpos = nil, nil
  FW_TriggerCallback('OnPlayerDeath', source, killertype, killerid, killerpos, data)
end)

FW_RegisterNetCallback('OnNativeUIIndexChange')
FW_RegisterNetCallback('OnNativeUIListChange')
FW_RegisterNetCallback('OnNativeUISliderChange')
FW_RegisterNetCallback('OnNativeUIProgressChange')
FW_RegisterNetCallback('OnNativeUICheckboxChange')
FW_RegisterNetCallback('OnNativeUIListSelect')
FW_RegisterNetCallback('OnNativeUISliderSelect')
FW_RegisterNetCallback('OnNativeUIProgressSelect')
FW_RegisterNetCallback('OnNativeUIItemSelect')
FW_RegisterNetCallback('OnNativeUIMenuChanged')
FW_RegisterNetCallback('OnNativeUIMenuClosed')

FW_RegisterPlainCallback('OnVehicleDestroyed')
FW_RegisterPlainCallback('OnPlayerPickup')

local function id_to_server_id(playerid, id)
  local network_id = NetworkGetNetworkIdFromEntityFromPlayer(playerid, id)
  if network_id then
    return NetworkGetEntityFromNetworkId(network_id)
  end
  return -id
end

FW_CreateCallbackHandler('OnGameEvent', function(playerid, type, ...)
  if type == 'CEventNetworkVehicleUndrivable' then
    local entity, destroyer, weapon = ...
    entity = id_to_server_id(playerid, entity)
    destroyer = id_to_server_id(playerid, destroyer)
    FW_TriggerCallback('OnVehicleDestroyed', playerid, entity, destroyer, weapon)
  elseif type == 'CEventNetworkPlayerCollectedPickup' then
    local pickup, player, hash, amount = ...
    FW_TriggerCallback('OnPlayerPickup', playerid, pickup, player, hash, amount)
  end
end)

FW_RegisterPlainCallback('OnPlayerEnterExitArea')
FW_RegisterPlainCallback('OnPlayerEnterExitSphere')

function RegisterPlayerAreaCheck(playerid, name, ...)
  FW_RegisterUpdateKeyDefaultForPlayer(playerid, 'IsEntityWithinAreaSelfPedSkip', 1, false, name, ...)
end

function RegisterPlayerSphereCheck(playerid, name, ...)
  FW_RegisterUpdateKeyDefaultForPlayer(playerid, 'IsEntityWithinRangeSelfPedSkip', 1, false, name, ...)
end

function UnregisterPlayerAreaCheck(playerid, name)
  FW_UnregisterUpdateForPlayer(playerid, 'IsEntityWithinAreaSelfPedSkip', name)
end

function UnregisterPlayerSphereCheck(playerid, name)
  FW_UnregisterUpdateForPlayer(playerid, 'IsEntityWithinRangeSelfPedSkip', name)
end

function CheckPlayerUpdates(playerid, updates)
  for key, value in pairs(updates) do
    if key[1] == 'IsEntityWithinAreaSelfPedSkip' then
      FW_TriggerCallback('OnPlayerEnterExitArea', playerid, key[2], table.unpack(value))
    elseif key[1] == 'IsEntityWithinRangeSelfPedSkip' then
      FW_TriggerCallback('OnPlayerEnterExitSphere', playerid, key[2], table.unpack(value))
    end
  end
end

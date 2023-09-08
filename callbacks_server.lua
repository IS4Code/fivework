local NetworkGetEntityFromNetworkId = _ENV.NetworkGetEntityFromNetworkId
local t_unpack = table.unpack
local select = _ENV.select

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
FW_RegisterPlainCallback('OnUnregisteredNetCallback')

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
FW_RegisterPlainCallback('OnEntityDamaged')

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
    FW_TriggerCallback('OnVehicleDestroyed', playerid, entity, destroyer, weapon, select(4, ...))
  elseif type == 'CEventNetworkPlayerCollectedPickup' then
    local pickup, player, hash, amount = ...
    FW_TriggerCallback('OnPlayerPickup', playerid, pickup, player, hash, amount, select(5, ...))
  elseif type == 'CEventNetworkEntityDamage' then
    local victim, attacker, unk1, unk2, unk3, fatal, weapon = ...
    victim = id_to_server_id(playerid, victim)
    attacker = id_to_server_id(playerid, attacker)
    FW_TriggerCallback('OnEntityDamaged', playerid, victim, attacker, weapon, fatal and fatal ~= 0, unk1, unk2, unk3, select(8, ...))
  end
end)

FW_RegisterPlainCallback('OnPlayerEnterExitArea')
FW_RegisterPlainCallback('OnPlayerEnterExitSphere')
FW_RegisterPlainCallback('OnPlayerEnterExitCircle')

function RegisterPlayerAreaCheck(playerid, name, ...)
  FW_RegisterUpdateKeyDefaultForPlayerDiscard(playerid, 'IsEntityWithinAreaSelfPedSkip', 1, false, name, ...)
end

function RegisterPlayerSphereCheck(playerid, name, ...)
  FW_RegisterUpdateKeyDefaultForPlayerDiscard(playerid, 'IsEntityWithinRangeSelfPedSkip', 1, false, name, ...)
end

function RegisterPlayerCircleCheck(playerid, name, ...)
  FW_RegisterUpdateKeyDefaultForPlayerDiscard(playerid, 'IsEntityWithinRange2DSelfPedSkip', 1, false, name, ...)
end

function UnregisterPlayerAreaCheck(playerid, name)
  FW_UnregisterUpdateForPlayerDiscard(playerid, 'IsEntityWithinAreaSelfPedSkip', name)
end

function UnregisterPlayerSphereCheck(playerid, name)
  FW_UnregisterUpdateForPlayerDiscard(playerid, 'IsEntityWithinRangeSelfPedSkip', name)
end

function UnregisterPlayerCircleCheck(playerid, name)
  FW_UnregisterUpdateForPlayerDiscard(playerid, 'IsEntityWithinRange2DSelfPedSkip', name)
end

function RegisterPlayerGroupAreaCheck(playerid, group, name, ...)
  FW_RegisterGroupUpdateKeyDefaultForPlayerDiscard(playerid, group, 'IsEntityWithinAreaSelfPedSkip', 1, false, name, ...)
end

function RegisterPlayerGroupSphereCheck(playerid, group, name, ...)
  FW_RegisterGroupUpdateKeyDefaultForPlayerDiscard(playerid, group, 'IsEntityWithinRangeSelfPedSkip', 1, false, name, ...)
end

function RegisterPlayerGroupCircleCheck(playerid, group, name, ...)
  FW_RegisterGroupUpdateKeyDefaultForPlayerDiscard(playerid, group, 'IsEntityWithinRange2DSelfPedSkip', 1, false, name, ...)
end

function UnregisterPlayerGroupAreaCheck(playerid, group, name)
  FW_UnregisterGroupUpdateForPlayerDiscard(playerid, group, 'IsEntityWithinAreaSelfPedSkip', name)
end

function UnregisterPlayerGroupSphereCheck(playerid, group, name)
  FW_UnregisterGroupUpdateForPlayerDiscard(playerid, group, 'IsEntityWithinRangeSelfPedSkip', name)
end

function UnregisterPlayerGroupCircleCheck(playerid, group, name)
  FW_UnregisterGroupUpdateForPlayerDiscard(playerid, group, 'IsEntityWithinRange2DSelfPedSkip', name)
end

function CheckPlayerUpdates(playerid, updates)
  for key, value in pairs(updates) do
    if key[1] == 'IsEntityWithinAreaSelfPedSkip' then
      if FW_TriggerCallback('OnPlayerEnterExitArea', playerid, key[2], table.unpack(value)) then
        updates[key] = nil
      end
    elseif key[1] == 'IsEntityWithinRangeSelfPedSkip' then
      if FW_TriggerCallback('OnPlayerEnterExitSphere', playerid, key[2], table.unpack(value)) then
        updates[key] = nil
      end
    elseif key[1] == 'IsEntityWithinRange2DSelfPedSkip' then
      if FW_TriggerCallback('OnPlayerEnterExitCircle', playerid, key[2], table.unpack(value)) then
        updates[key] = nil
      end
    end
  end
end

FW_RegisterCallback('OnWeaponDamage', 'weaponDamageEvent')

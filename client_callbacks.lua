FW_RegisterNetCallback('OnPlayerSpawn', 'playerSpawned')
FW_RegisterNetCallback('OnGameEvent', 'gameEventTriggered')
FW_RegisterPlainCallback('OnPlayerReceivedCommand')
FW_RegisterPlainCallback('OnPlayerPerformedCommand')

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then
    FW_TriggerNetCallback('OnPlayerInit')
  end
end)

Citizen.CreateThread(function()
	while true do
		Wait(0)

		if NetworkIsSessionStarted() then
			TriggerServerEvent('fivework:PlayerActivated')
			return
		end
	end
end)

local m_type = math.type

local DoesEntityExist = _ENV.DoesEntityExist
FW_RegisterObserver('NetworkGetNetworkIdFromEntity', function(id)
  return m_type(id) == 'integer' and DoesEntityExist(id)
end)

local NetworkIsPlayerActive = _ENV.NetworkIsPlayerActive
FW_RegisterObserver('GetPlayerServerId', function(id)
  return m_type(id) == 'integer' and NetworkIsPlayerActive(id)
end)

function IsEntityWithinRange(entity, x, y, z, range)
  local pos = GetEntityCoords(entity)
  return GetDistanceBetweenCoords(pos.x, pos.y, pos.z, x, y, z, false) <= range
end

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

FW_RegisterObserver('NetworkGetNetworkIdFromEntity', DoesEntityExist)

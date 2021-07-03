FW_RegisterNetCallback('OnPlayerSpawn', 'playerSpawned')
FW_RegisterNetCallback('OnGameEvent', 'gameEventTriggered')

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

FW_RegisterNetCallback('OnPlayerSpawn', 'playerSpawned')

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

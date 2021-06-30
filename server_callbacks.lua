FW_RegisterCallback('OnEntityCreated', 'entityCreated')
FW_RegisterCallback('OnEntityCreating', 'entityCreating', nil, true)
FW_RegisterCallback('OnResourceStart', 'onResourceStart')
RegisterServerEvent('fivework:PlayerActivated')
FW_RegisterCallback('OnPlayerConnect', 'fivework:PlayerActivated', true)
FW_RegisterCallback('OnPlayerDisconnect', 'playerDropped', true)
FW_RegisterCallback('OnIncomingConnection', 'playerConnecting', nil, true)

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then
    FW_TriggerCallback('OnScriptInit')
  end
end)

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
    
    local sessionStarted, playerActive
    
    if not sessionStarted then
      if NetworkIsSessionStarted() then
        FW_TriggerNetCallback('OnPlayerConnect')
        sessionStarted = true
      end
    end
    
    if not playerActive then
      if NetworkIsPlayerActive(PlayerId()) then
        FW_TriggerNetCallback('OnPlayerActivate')
        playerActive = true
      end
    end
    
    if sessionStarted and playerActive then
      return
    end
  end
end)

local m_type = math.type

local DoesEntityExist = _ENV.DoesEntityExist
FW_RegisterObserver('NetworkGetNetworkIdFromEntity', function(id)
  return m_type(id) == 'integer' and DoesEntityExist(id) and NetworkGetEntityIsNetworked(id)
end)

local NetworkIsPlayerActive = _ENV.NetworkIsPlayerActive
FW_RegisterObserver('GetPlayerServerId', function(id)
  return m_type(id) == 'integer' and NetworkIsPlayerActive(id)
end)

function IsEntityWithinRange(entity, x, y, z, range)
  local pos = GetEntityCoords(entity)
  return GetDistanceBetweenCoords(pos.x, pos.y, pos.z, x, y, z, true) <= range
end

function IsEntityWithinArea(entity, x1, y1, z1, x2, y2, z2)
  local pos = GetEntityCoords(entity)
  return pos.x >= x1 and pos.x <= x2 and pos.y >= y1 and pos.y <= y2 and pos.z >= z1 and pos.z <= z2
end

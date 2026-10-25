-- Beautiful Humans / Project Zomboid event bridge.
-- Only events confirmed in Build 42 are registered. Missing events are logged
-- and skipped so a partial game build cannot break the whole mod.

BH = BH or {}

if BH.Integration and BH.Integration._loaded then
    return
end

require "BH/Core"
require "BH/Persistence/Persistence"
require "BH/Anatomy/Model"
require "BH/Medical/Medical"
require "BH/Integration/PlayerObserver"

BH.Integration = BH.Integration or {}
local Integration = BH.Integration
Integration._loaded = true
Integration._registered = false
Integration.zombieHits = 0

local Player = BH.Integration.Player

local function addGameEvent(name, callback)
    if not Events or not Events[name] then
        BH.Log.Warn("integration", "Game event is unavailable", name)
        return false
    end
    local event = Events[name]
    local ok, errorMessage = pcall(function()
        event.Add(callback)
    end)
    if not ok then
        BH.Log.Error("integration", "Failed to register game event", {
            event = name,
            error = tostring(errorMessage),
        })
        return false
    end
    return true
end

local function startAndAttachLocalPlayer(reason)
    BH.Log.Info("integration", "Start event received", reason)
    BH.Start()

    local player = nil
    local ok, value = pcall(function()
        return getPlayer()
    end)
    if ok then
        player = value
    end
    if player then
        Player.EnsurePlayer(player)
    end
end

function Integration.OnGameStart()
    startAndAttachLocalPlayer("OnGameStart")
end

function Integration.OnServerStarted()
    startAndAttachLocalPlayer("OnServerStarted")
end

function Integration.OnCreatePlayer(playerIndex, player)
    Player.OnCreate(playerIndex, player)
end

function Integration.OnPlayerUpdate(player)
    Player.OnUpdate(player)
end

function Integration.OnPlayerGetDamage(character, damageType, damage)
    Player.OnGetDamage(character, damageType, damage)
end

function Integration.OnPlayerDeath(player)
    Player.OnDeath(player)
end

function Integration.OnHitZombie(zombie, wielder, bodyPart, weapon)
    Integration.zombieHits = Integration.zombieHits + 1
    -- Zombie anatomy is a later module. Keep the bridge passive for now.
end

function Integration.OnWeaponHitCharacter(attacker, target, weapon, damageSplit)
    -- Reserved for the equipment/material modules. Intentionally passive.
end

function Integration.OnPostSave()
    BH.Log.Debug("integration", "Post-save event received")
end

function Integration.Boot()
    if Integration._registered then
        return true
    end
    Integration._registered = true

    BH.Log.Info("integration", "Registering game events", {
        gameVersion = BH.GetGameVersionString(),
    })

    if not BH.IsGameVersionAtLeast(42, 0) then
        BH.Log.Warn("integration", "Target Build 42 was not confirmed at runtime")
    end

    addGameEvent("OnGameStart", Integration.OnGameStart)
    addGameEvent("OnServerStarted", Integration.OnServerStarted)
    addGameEvent("OnCreatePlayer", Integration.OnCreatePlayer)
    addGameEvent("OnPlayerUpdate", Integration.OnPlayerUpdate)
    addGameEvent("OnPlayerGetDamage", Integration.OnPlayerGetDamage)
    addGameEvent("OnPlayerDeath", Integration.OnPlayerDeath)
    addGameEvent("OnHitZombie", Integration.OnHitZombie)
    addGameEvent("OnWeaponHitCharacter", Integration.OnWeaponHitCharacter)
    addGameEvent("OnPostSave", Integration.OnPostSave)

    return true
end

BH.RegisterModule({
    id = "bh.integration",
    version = BH.VERSION,
    requires = { "bh.core", "bh.persistence", "bh.anatomy", "bh.physiology", "bh.medical" },
    description = "Project Zomboid event bridge and player observation",
    init = function(context)
        BH.Anatomy.Zones.ResolveEngineIndices()
        Integration.Boot()
        context.log.Info("integration", "Integration module ready", {
            engineZones = BH.Anatomy.Zones.Count(),
        })
    end,
})

return Integration

-- Beautiful Humans / player observation bridge.
-- The base game remains authoritative for health. This bridge observes base
-- BodyPart state transitions and mirrors them into structured BH injuries.
-- It never creates a second health pool and never lowers base health.

BH = BH or {}

if BH.Integration and BH.Integration.Player then
    return
end

require "BH/Core"
require "BH/Persistence/Persistence"
require "BH/Anatomy/Model"
require "BH/Medical/Medical"

BH.Integration = BH.Integration or {}

local Player = {
    baselines = {},
    tickCounters = {},
    lastTickAt = {},
    pendingContext = {},
}
BH.Integration.Player = Player

local Model = BH.Anatomy.Model

function Player.Key(player)
    if not player then
        return "unknown"
    end
    local idOk, onlineId = pcall(function()
        return player:getOnlineID()
    end)
    if idOk and onlineId ~= nil then
        return "id:" .. tostring(onlineId)
    end
    local nameOk, username = pcall(function()
        return player:getUsername()
    end)
    if nameOk and type(username) == "string" and username ~= "" then
        return "name:" .. username
    end
    return "obj:" .. tostring(player)
end

local function callBool(part, method)
    local ok, value = pcall(function()
        return part[method](part)
    end)
    return ok and value == true
end

local function callNumber(part, method, fallback)
    local ok, value = pcall(function()
        return part[method](part)
    end)
    if ok and BH.Util.IsFiniteNumber(value) then
        return value
    end
    return fallback
end

function Player.ReadPartState(part)
    return {
        bitten = callBool(part, "isBitten"),
        cut = callBool(part, "isCut"),
        scratched = callBool(part, "isScratched"),
        deepWounded = callBool(part, "isDeepWounded"),
        fracture = callNumber(part, "getFractureTime", 0) > 0,
        burn = callNumber(part, "getBurnTime", 0) > 0,
        bleeding = callNumber(part, "getBleedingTime", 0) > 0,
        bandaged = callBool(part, "bandaged"),
        infection = callNumber(part, "getWoundInfectionLevel", 0),
        health = callNumber(part, "getHealth", 100),
    }
end

local function emptyBaseline()
    return { zones = {} }
end

local function snapshot(player)
    local baseline = emptyBaseline()
    if not BodyPartType or not BodyPartType.FromIndex then
        return baseline
    end
    local ok, bodyDamage = pcall(function()
        return player:getBodyDamage()
    end)
    if not ok or not bodyDamage then
        return baseline
    end

    local zones = BH.Anatomy.Zones.GetAll()
    for index = 1, #zones do
        local zone = zones[index]
        local partOk, part = pcall(function()
            return bodyDamage:getBodyPart(BodyPartType.FromIndex(zone.engineIndex))
        end)
        if partOk and part then
            baseline.zones[zone.id] = Player.ReadPartState(part)
        end
    end
    return baseline
end

function Player.EnsurePlayer(player)
    if not player then
        return nil, "player is nil"
    end
    local ext, errorMessage = BH.Persistence.GetCharacterData(player)
    if not ext then
        BH.Log.Error("player", "Could not obtain character extension", errorMessage)
        return nil, errorMessage
    end
    ext.metadata = ext.metadata or {}
    ext.metadata.ownerKey = BH.Persistence.GetPlayerKey(player)
    local key = Player.Key(player)
    if not Player.baselines[key] then
        Player.baselines[key] = snapshot(player)
        BH.Log.Info("player", "Base injury baseline captured", {
            player = ext.metadata.ownerKey,
        })
    end
    return ext
end

local function severityFor(base, missingHealth)
    return BH.Util.Clamp(base + missingHealth * 0.30, 10, 100)
end

local function createFromTransition(ext, zone, kind, baseSeverity, source, missingHealth, now)
    local injury, reason = Model.AddInjury(ext, zone.id, kind, severityFor(baseSeverity, missingHealth), source, {
        now = now,
        characterKey = ext.metadata and ext.metadata.ownerKey,
        meta = { observedFromBase = true },
    })
    if injury then
        BH.Log.Info("player", "Observed new base injury", {
            zone = zone.id,
            kind = kind,
            severity = injury.severity,
            reason = reason,
        })
    end
    return injury
end

function Player.ScanBaseInjuries(player, ext, context)
    if not BodyPartType or not BodyPartType.FromIndex then
        return 0
    end
    local ok, bodyDamage = pcall(function()
        return player:getBodyDamage()
    end)
    if not ok or not bodyDamage then
        return 0
    end

    context = type(context) == "table" and context or {}
    local key = Player.Key(player)
    local baseline = Player.baselines[key] or emptyBaseline()
    local now = BH.Persistence.GetGameTimeHours()
    local created = 0

    local zones = BH.Anatomy.Zones.GetAll()
    for index = 1, #zones do
        local zone = zones[index]
        local partOk, part = pcall(function()
            return bodyDamage:getBodyPart(BodyPartType.FromIndex(zone.engineIndex))
        end)
        if partOk and part then
            local state = Player.ReadPartState(part)
            local previous = baseline.zones[zone.id] or {}
            local missingHealth = math.max(0, 100 - (state.health or 100))
            local source = context.source or "unknown"

            if state.bitten and not previous.bitten then
                createFromTransition(ext, zone, "bite", 50, "zombie", missingHealth, now)
                created = created + 1
            end
            if state.cut and not previous.cut then
                createFromTransition(ext, zone, "cut", 32, source, missingHealth, now)
                created = created + 1
            end
            if state.scratched and not previous.scratched then
                createFromTransition(ext, zone, "abrasion", 18, "zombie", missingHealth, now)
                created = created + 1
            end
            if state.deepWounded and not previous.deepWounded then
                createFromTransition(ext, zone, "deep_wound", 55, source, missingHealth, now)
                created = created + 1
            end
            if state.fracture and not previous.fracture then
                createFromTransition(ext, zone, "fracture", 60, context.source or "fall", missingHealth, now)
                created = created + 1
            end
            if state.burn and not previous.burn then
                createFromTransition(ext, zone, "burn", 45, "environment", missingHealth, now)
                created = created + 1
            end
            if state.bleeding and not state.bandaged and not previous.bleeding then
                local zoneState = Model.GetZoneState(ext, zone.id, false)
                local hasBleeding = false
                if zoneState then
                    for _, injury in pairs(zoneState.injuries) do
                        if (injury.bleeding or 0) > 0.1 then
                            hasBleeding = true
                            break
                        end
                    end
                end
                if not hasBleeding then
                    createFromTransition(ext, zone, "cut", 20, "unknown", missingHealth, now)
                    created = created + 1
                end
            end

            -- The base game may apply a bandage without asking BH. Mirror the
            -- bandaged state so the medical panel does not contradict it.
            if state.bandaged then
                local zoneState = Model.GetZoneState(ext, zone.id, false)
                if zoneState then
                    for _, injury in pairs(zoneState.injuries) do
                        if not injury.bandaged and injury.status ~= "healed" then
                            injury.bandaged = true
                            injury.bleeding = math.min(injury.bleeding or 0, 5)
                            injury.meta = injury.meta or {}
                            injury.meta.externalBandage = true
                        end
                    end
                end
            end
            if state.infection > 0 then
                local zoneState = Model.GetZoneState(ext, zone.id, false)
                if zoneState then
                    for _, injury in pairs(zoneState.injuries) do
                        injury.infection = math.max(injury.infection or 0, state.infection)
                    end
                end
            end

            baseline.zones[zone.id] = state
        end
    end

    Player.baselines[key] = baseline
    return created
end

function Player.OnCreate(playerIndex, player)
    local ext = Player.EnsurePlayer(player)
    if ext then
        BH.Log.Info("player", "Player extension ready", {
            player = ext.metadata.ownerKey,
            schema = ext.schemaVersion,
            injuries = BH.Persistence.CountInjuries(ext),
        })
    end
end

function Player.OnUpdate(player)
    if not player then
        return
    end
    local key = Player.Key(player)
    local interval = BH.Config.Get("tickInterval") or 30
    local counter = (Player.tickCounters[key] or 0) + 1
    if counter < interval then
        Player.tickCounters[key] = counter
        return
    end
    Player.tickCounters[key] = 0

    local ext = Player.EnsurePlayer(player)
    if not ext then
        return
    end

    local context = Player.pendingContext[key] or {}
    Player.pendingContext[key] = nil
    Player.ScanBaseInjuries(player, ext, context)

    local now = BH.Persistence.GetGameTimeHours()
    local last = Player.lastTickAt[key]
    local minutes = 0.5
    if last and now > last then
        minutes = BH.Util.Clamp((now - last) * 60, 0.1, 60)
    end
    Player.lastTickAt[key] = now

    local healed = Model.Tick(ext, minutes)
    if BH.Physiology and BH.Physiology.Tick then
        BH.Physiology.Tick(ext, minutes)
    end

    if healed > 0 then
        BH.Log.Info("player", "Injuries healed", { count = healed })
    end
end

function Player.OnGetDamage(character, damageType, damage)
    if not character then
        return
    end
    local source = "unknown"
    if damageType == "FALLDOWN" then
        source = "fall"
    elseif damageType == "CARHITDAMAGE" or damageType == "CARCRASHDAMAGE" then
        source = "vehicle"
    elseif damageType == "WEAPONHIT" then
        source = "weapon"
    elseif damageType == "BLEEDING" then
        source = "medical"
    end

    local key = Player.Key(character)
    Player.pendingContext[key] = {
        source = source,
        damageType = damageType,
        damage = damage,
        at = BH.Persistence.GetGameTimeHours(),
    }
end

function Player.OnDeath(player)
    local key = Player.Key(player)
    Player.baselines[key] = nil
    Player.tickCounters[key] = nil
    Player.lastTickAt[key] = nil
    Player.pendingContext[key] = nil
end

return Player

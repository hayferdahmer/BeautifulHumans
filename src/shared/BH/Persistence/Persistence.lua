-- Beautiful Humans / per-character persistence.
-- Player modData is the only storage used by this module. It is part of the
-- base game save and is replicated by the engine; BH never writes save files
-- directly and never stores live game objects in the payload.

BH = BH or {}

if BH.Persistence and BH.Persistence._loaded then
    return
end

require "BH/Core"
require "BH/Persistence/Schema"

BH.Persistence = BH.Persistence or {}

local Persistence = BH.Persistence
Persistence._loaded = true
Persistence.STORAGE_KEY = "BH"
Persistence.QUARANTINE_KEY = "BH_QUARANTINE"
Persistence.Schema = BH.Persistence.Schema
Persistence.cache = {}

local function safeGameTime()
    local ok, hours = pcall(function()
        return getGameTime():getWorldAgeHours()
    end)
    if ok and BH.Util.IsFiniteNumber(hours) then
        return hours
    end
    local fallback = os.time and os.time() or 0
    if BH.Util.IsFiniteNumber(fallback) then
        return fallback
    end
    return 0
end

Persistence.GetGameTimeHours = safeGameTime

function Persistence.GetPlayerKey(player)
    if not player then
        return "unknown"
    end
    local ok, username = pcall(function()
        return player:getUsername()
    end)
    if ok and type(username) == "string" and username ~= "" then
        return username
    end
    local idOk, onlineId = pcall(function()
        return player:getOnlineID()
    end)
    if idOk and onlineId ~= nil then
        return "player:" .. tostring(onlineId)
    end
    return "local"
end

function Persistence.NewCharacterData()
    return BH.Persistence.Schema.NewCharacterData(safeGameTime())
end

function Persistence.GetRawModData(player)
    if not player then
        return nil, "player is nil"
    end
    local ok, modData = pcall(function()
        return player:getModData()
    end)
    if not ok or type(modData) ~= "table" then
        return nil, "player has no modData"
    end
    return modData
end

function Persistence.Quarantine(modData, reason)
    if type(modData) ~= "table" then
        return
    end
    modData[Persistence.QUARANTINE_KEY] = {
        at = safeGameTime(),
        reason = tostring(reason or "unknown"),
        version = BH.VERSION,
    }
end

function Persistence.GetCharacterData(player)
    local modData, modDataError = Persistence.GetRawModData(player)
    if not modData then
        return nil, modDataError
    end

    local cacheKey = Persistence.GetPlayerKey(player)
    local raw = modData[Persistence.STORAGE_KEY]
    if raw == nil then
        local fresh = Persistence.NewCharacterData()
        modData[Persistence.STORAGE_KEY] = fresh
        Persistence.cache[cacheKey] = fresh
        BH.Log.Info("persistence", "Created character extension", {
            player = cacheKey,
            schema = fresh.schemaVersion,
        })
        return fresh
    end

    local cached = Persistence.cache[cacheKey]
    if cached and cached == raw then
        return cached
    end

    local migrated, report = BH.Persistence.Schema.Migrate(raw)
    if not migrated then
        local reason = report and report.error or "migration failed"
        Persistence.Quarantine(modData, reason)
        local fresh = Persistence.NewCharacterData()
        modData[Persistence.STORAGE_KEY] = fresh
        Persistence.cache[cacheKey] = fresh
        BH.Log.Critical("persistence", "Character data quarantined and reset", {
            player = cacheKey,
            reason = reason,
        })
        return fresh, reason
    end

    modData[Persistence.STORAGE_KEY] = migrated
    Persistence.cache[cacheKey] = migrated
    if report and report.migrated then
        BH.Log.Info("persistence", "Character data migrated", {
            player = Persistence.GetPlayerKey(player),
            from = report.fromVersion,
            to = report.toVersion,
        })
    end
    if report and report.issues and #report.issues > 0 then
        BH.Log.Warn("persistence", "Character data repaired", {
            player = Persistence.GetPlayerKey(player),
            issues = report.issues,
        })
    end
    return migrated
end

function Persistence.SetCharacterData(player, data)
    local modData = Persistence.GetRawModData(player)
    if not modData then
        return false, "player has no modData"
    end
    local validated = BH.Persistence.Schema.Validate(data)
    if not validated then
        return false, "invalid character data"
    end
    modData[Persistence.STORAGE_KEY] = validated
    Persistence.cache[Persistence.GetPlayerKey(player)] = validated
    return true
end

function Persistence.Touch(data)
    if type(data) ~= "table" then
        return
    end
    data.metadata = data.metadata or {}
    data.metadata.updatedAt = safeGameTime()
    data.metadata.updatedVersion = BH.VERSION
end

function Persistence.ClearCharacterData(player)
    local modData = Persistence.GetRawModData(player)
    if not modData then
        return false, "player has no modData"
    end
    modData[Persistence.STORAGE_KEY] = nil
    Persistence.cache[Persistence.GetPlayerKey(player)] = nil
    return true
end

function Persistence.ResetCharacterData(player)
    local modData = Persistence.GetRawModData(player)
    if not modData then
        return false, "player has no modData"
    end
    local fresh = Persistence.NewCharacterData()
    modData[Persistence.STORAGE_KEY] = fresh
    Persistence.cache[Persistence.GetPlayerKey(player)] = fresh
    return fresh
end

function Persistence.CountInjuries(data)
    local total = 0
    if type(data) ~= "table" or type(data.anatomy) ~= "table" or type(data.anatomy.zones) ~= "table" then
        return 0
    end
    for _, zone in pairs(data.anatomy.zones) do
        if type(zone) == "table" and type(zone.injuries) == "table" then
            for _ in pairs(zone.injuries) do
                total = total + 1
            end
        end
    end
    return total
end

function Persistence.GetSummary(data)
    if type(data) ~= "table" then
        return nil
    end
    return {
        schemaVersion = data.schemaVersion,
        injuries = Persistence.CountInjuries(data),
        pain = data.physiology and data.physiology.pain or 0,
        bloodLoss = data.physiology and data.physiology.bloodLoss or 0,
        lastUpdated = data.metadata and data.metadata.updatedAt or 0,
    }
end

BH.RegisterModule({
    id = "bh.persistence",
    version = BH.VERSION,
    requires = { "bh.core" },
    description = "Versioned per-character modData persistence and migrations",
    init = function(context)
        context.log.Info("persistence", "Persistence ready", {
            schema = context.schemaVersion,
            storageKey = Persistence.STORAGE_KEY,
        })
    end,
})

return Persistence

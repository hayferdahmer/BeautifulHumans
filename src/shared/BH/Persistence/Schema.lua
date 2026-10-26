-- Beautiful Humans / versioned character schema.
-- Schema code is deliberately defensive: save data is untrusted input and a
-- corrupt record must never prevent the rest of the mod from loading.

BH = BH or {}

if BH.Persistence and BH.Persistence.Schema then
    return
end

require "BH/Core"

BH.Persistence = BH.Persistence or {}

local Schema = {
    CURRENT_VERSION = 1,
    VALID_STATUS = {
        active = true,
        healing = true,
        infected = true,
        healed = true,
    },
}
BH.Persistence.Schema = Schema

local VALID_KIND = {
    abrasion = true,
    bruise = true,
    burn = true,
    cut = true,
    deep_wound = true,
    fracture = true,
    puncture = true,
    sprain = true,
    bite = true,
}

local VALID_SOURCE = {
    debug = true,
    environment = true,
    fall = true,
    medical = true,
    unknown = true,
    vehicle = true,
    weapon = true,
    zombie = true,
}

local function isTable(value)
    return type(value) == "table"
end

local function finite(value, fallback)
    if BH.Util.IsFiniteNumber(value) then
        return value
    end
    return fallback
end

local function clamp(value, minimum, maximum, fallback)
    if not BH.Util.IsFiniteNumber(value) then
        return fallback
    end
    return BH.Util.Clamp(value, minimum, maximum)
end

local function ensureTable(parent, key)
    if not isTable(parent[key]) then
        parent[key] = {}
    end
    return parent[key]
end

function Schema.NewCharacterData(now)
    now = finite(now, 0)
    return {
        schemaVersion = Schema.CURRENT_VERSION,
        anatomy = {
            zones = {},
            nextInjurySeq = 1,
            healedCount = 0,
            lastTick = now,
        },
        physiology = {
            pain = 0,
            bloodLoss = 0,
            fatigue = 0,
            lastUpdate = now,
        },
        medical = {
            processedRequests = {},
            processedSeq = 0,
            lastActionAt = 0,
        },
        mind = {
            stress = 0,
            fear = 0,
        },
        exposure = {},
        metadata = {
            createdAt = now,
            updatedAt = now,
            createdVersion = BH.VERSION,
            updatedVersion = BH.VERSION,
        },
    }
end

function Schema.NewZoneState()
    return {
        injuries = {},
        updatedAt = 0,
    }
end

function Schema.ValidZoneId(zoneId)
    if BH.Anatomy and BH.Anatomy.Zones then
        return BH.Anatomy.Zones.Get(zoneId) ~= nil
    end
    return type(zoneId) == "string" and #zoneId > 0
end

function Schema.ValidKind(kind)
    return VALID_KIND[kind] == true
end

function Schema.ValidSource(source)
    return VALID_SOURCE[source] == true
end

local function repairInjury(zoneId, injury, issues)
    if not isTable(injury) then
        issues[#issues + 1] = "injury is not a table"
        return nil
    end
    if type(injury.id) ~= "string" or injury.id == "" or #injury.id > 96 then
        issues[#issues + 1] = "injury has invalid id"
        return nil
    end
    if injury.zone ~= nil and injury.zone ~= zoneId then
        issues[#issues + 1] = "injury zone mismatch"
        injury.zone = zoneId
    end
    injury.zone = zoneId

    if not Schema.ValidKind(injury.kind) then
        issues[#issues + 1] = "injury has invalid kind"
        injury.kind = "abrasion"
    end
    if not Schema.ValidSource(injury.source) then
        injury.source = "unknown"
    end
    if not Schema.VALID_STATUS[injury.status] then
        injury.status = "active"
    end

    injury.severity = clamp(injury.severity, 0, 100, 10)
    injury.bleeding = clamp(injury.bleeding, 0, 100, 0)
    injury.contamination = clamp(injury.contamination, 0, 100, 0)
    injury.infection = clamp(injury.infection, 0, 100, 0)
    injury.pain = clamp(injury.pain, 0, 100, 0)
    injury.healing = clamp(injury.healing, 0, 100, 0)
    injury.createdAt = finite(injury.createdAt, 0)
    injury.updatedAt = finite(injury.updatedAt, injury.createdAt)
    injury.treatmentCount = math.floor(clamp(injury.treatmentCount, 0, 100000, 0))

    injury.bandaged = injury.bandaged == true
    injury.splinted = injury.splinted == true
    injury.stitched = injury.stitched == true
    injury.cleaned = injury.cleaned == true
    injury.examined = injury.examined == true
    injury.bandageDirty = injury.bandageDirty == true

    if type(injury.meta) ~= "table" then
        injury.meta = {}
    end

    return injury
end

local function countInjuries(data)
    local total = 0
    for _, zone in pairs(data.anatomy.zones) do
        for _ in pairs(zone.injuries) do
            total = total + 1
        end
    end
    return total
end

local function trimInjuries(data, issues)
    local maximum = BH.Config.Get("maxInjuries") or 64
    if countInjuries(data) <= maximum then
        return
    end

    local candidates = {}
    for zoneId, zone in pairs(data.anatomy.zones) do
        for injuryId, injury in pairs(zone.injuries) do
            candidates[#candidates + 1] = {
                zoneId = zoneId,
                injuryId = injuryId,
                injury = injury,
            }
        end
    end

    table.sort(candidates, function(left, right)
        local leftHealed = left.injury.status == "healed" and 1 or 0
        local rightHealed = right.injury.status == "healed" and 1 or 0
        if leftHealed ~= rightHealed then
            return leftHealed > rightHealed
        end
        return (left.injury.severity or 0) < (right.injury.severity or 0)
    end)

    local over = countInjuries(data) - maximum
    for index = 1, math.min(over, #candidates) do
        local candidate = candidates[index]
        data.anatomy.zones[candidate.zoneId].injuries[candidate.injuryId] = nil
    end
    issues[#issues + 1] = string.format("trimmed %d injuries", over)
end

function Schema.Validate(data)
    local issues = {}
    if not isTable(data) then
        return nil, { "character data is not a table" }
    end

    data.schemaVersion = Schema.CURRENT_VERSION
    data.anatomy = isTable(data.anatomy) and data.anatomy or {}
    data.anatomy.zones = isTable(data.anatomy.zones) and data.anatomy.zones or {}
    data.anatomy.nextInjurySeq = math.floor(clamp(data.anatomy.nextInjurySeq, 1, 1000000000, 1))
    data.anatomy.healedCount = math.floor(clamp(data.anatomy.healedCount, 0, 1000000000, 0))
    data.anatomy.lastTick = finite(data.anatomy.lastTick, 0)

    local maximumPerZone = BH.Config.Get("maxInjuriesPerZone") or 8
    local maximumSequence = 0

    for zoneId, zone in pairs(data.anatomy.zones) do
        if not Schema.ValidZoneId(zoneId) or not isTable(zone) then
            data.anatomy.zones[zoneId] = nil
            issues[#issues + 1] = "removed invalid zone"
        else
            zone.injuries = isTable(zone.injuries) and zone.injuries or {}
            zone.updatedAt = finite(zone.updatedAt, 0)

            local injuryCount = 0
            for injuryId, injury in pairs(zone.injuries) do
                local repaired = repairInjury(zoneId, injury, issues)
                if repaired then
                    zone.injuries[injuryId] = repaired
                    injuryCount = injuryCount + 1
                    local numeric = tonumber(string.match(injury.id, "(%d+)$"))
                    if numeric and numeric > maximumSequence then
                        maximumSequence = numeric
                    end
                else
                    zone.injuries[injuryId] = nil
                end
            end

            if injuryCount > maximumPerZone then
                local removable = {}
                for injuryId, injury in pairs(zone.injuries) do
                    removable[#removable + 1] = { id = injuryId, injury = injury }
                end
                table.sort(removable, function(left, right)
                    return (left.injury.severity or 0) < (right.injury.severity or 0)
                end)
                local over = injuryCount - maximumPerZone
                for index = 1, over do
                    if removable[index] then
                        zone.injuries[removable[index].id] = nil
                    end
                end
                issues[#issues + 1] = "trimmed injuries in zone " .. zoneId
            end
        end
    end

    if data.anatomy.nextInjurySeq <= maximumSequence then
        data.anatomy.nextInjurySeq = maximumSequence + 1
    end

    data.physiology = isTable(data.physiology) and data.physiology or {}
    data.physiology.pain = clamp(data.physiology.pain, 0, 100, 0)
    data.physiology.bloodLoss = clamp(data.physiology.bloodLoss, 0, 100, 0)
    data.physiology.fatigue = clamp(data.physiology.fatigue, 0, 100, 0)
    data.physiology.lastUpdate = finite(data.physiology.lastUpdate, 0)

    data.medical = isTable(data.medical) and data.medical or {}
    data.medical.processedRequests = isTable(data.medical.processedRequests) and data.medical.processedRequests or {}
    data.medical.processedSeq = math.floor(clamp(data.medical.processedSeq, 0, 1000000000, 0))
    data.medical.lastActionAt = finite(data.medical.lastActionAt, 0)

    local requestLimit = BH.Config.Get("maxProcessedRequests") or 32
    local requestCount = 0
    for _ in pairs(data.medical.processedRequests) do
        requestCount = requestCount + 1
    end
    if requestCount > requestLimit then
        local oldest = {}
        for requestId in pairs(data.medical.processedRequests) do
            oldest[#oldest + 1] = requestId
        end
        table.sort(oldest, function(left, right)
            return tostring(left) < tostring(right)
        end)
        for index = 1, requestCount - requestLimit do
            data.medical.processedRequests[oldest[index]] = nil
        end
        issues[#issues + 1] = "trimmed processed requests"
    end

    data.mind = isTable(data.mind) and data.mind or {}
    data.mind.stress = clamp(data.mind.stress, 0, 100, 0)
    data.mind.fear = clamp(data.mind.fear, 0, 100, 0)

    data.exposure = isTable(data.exposure) and data.exposure or {}
    data.metadata = isTable(data.metadata) and data.metadata or {}
    data.metadata.createdAt = finite(data.metadata.createdAt, 0)
    data.metadata.updatedAt = finite(data.metadata.updatedAt, data.metadata.createdAt)
    data.metadata.createdVersion = BH.Util.StringOr(data.metadata.createdVersion, BH.VERSION)
    data.metadata.updatedVersion = BH.VERSION

    trimInjuries(data, issues)
    return data, issues
end

local function migrateV0(raw)
    local migrated = Schema.NewCharacterData(0)

    -- Preserve a partially shaped anatomy table if one exists.
    if isTable(raw.anatomy) then
        migrated.anatomy = BH.Util.DeepCopy(raw.anatomy)
        migrated.anatomy.zones = isTable(migrated.anatomy.zones) and migrated.anatomy.zones or {}
    end

    -- Very early prototypes stored anatomy as a flat injury list.
    if isTable(raw.injuries) then
        for index = 1, #raw.injuries do
            local injury = raw.injuries[index]
            if isTable(injury) and type(injury.zone) == "string" then
                local zone = migrated.anatomy.zones[injury.zone]
                if not zone then
                    zone = Schema.NewZoneState()
                    migrated.anatomy.zones[injury.zone] = zone
                end
                zone.injuries = zone.injuries or {}
                injury.id = injury.id or string.format("%s-%06d", injury.zone, index)
                zone.injuries[injury.id] = injury
            end
        end
    end

    -- Preserve known top-level fields if they already have a compatible shape.
    for _, key in ipairs({ "physiology", "medical", "mind", "exposure", "metadata" }) do
        if isTable(raw[key]) then
            migrated[key] = BH.Util.DeepCopy(raw[key])
        end
    end
    migrated.schemaVersion = Schema.CURRENT_VERSION
    return migrated
end

function Schema.Migrate(raw)
    if raw == nil then
        return Schema.NewCharacterData(0), {
            fromVersion = 0,
            toVersion = Schema.CURRENT_VERSION,
            migrated = true,
        }
    end
    if not isTable(raw) then
        return nil, { error = "character data is not a table" }
    end

    local version = tonumber(raw.schemaVersion) or 0
    if version > Schema.CURRENT_VERSION then
        return nil, {
            error = string.format("character schema %d is newer than supported %d", version, Schema.CURRENT_VERSION),
            future = true,
        }
    end

    local data = raw
    local changed = false
    if version < 1 then
        data = migrateV0(raw)
        changed = true
    end

    local validated, issues = Schema.Validate(data)
    if not validated then
        return nil, { error = issues and issues[1] or "validation failed" }
    end

    return validated, {
        fromVersion = version,
        toVersion = Schema.CURRENT_VERSION,
        migrated = changed,
        issues = issues or {},
    }
end

function Schema.DropProcessedRequests(data)
    data.medical.processedRequests = {}
    data.medical.processedSeq = 0
end

return Schema

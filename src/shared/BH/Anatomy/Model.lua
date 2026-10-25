-- Beautiful Humans / anatomical state and injury lifecycle.
-- The model is additive: the base game's BodyDamage remains authoritative for
-- health, bleeding and infection. BH stores structured injury records that add
-- stable identity, treatment state and functional consequences.

BH = BH or {}

if BH.Anatomy and BH.Anatomy.Model then
    return
end

require "BH/Core"
require "BH/Persistence/Persistence"
require "BH/Anatomy/Zones"
require "BH/Anatomy/Rules"

BH.Anatomy = BH.Anatomy or {}

local Model = {}
BH.Anatomy.Model = Model

local Zones = BH.Anatomy.Zones
local Rules = BH.Anatomy.Rules
local Schema = BH.Persistence.Schema

local function nowHours()
    if BH.Persistence and BH.Persistence.GetGameTimeHours then
        return BH.Persistence.GetGameTimeHours()
    end
    return 0
end

local function ensureAnatomy(ext)
    ext.anatomy = ext.anatomy or {}
    ext.anatomy.zones = ext.anatomy.zones or {}
    ext.anatomy.nextInjurySeq = ext.anatomy.nextInjurySeq or 1
    ext.anatomy.healedCount = ext.anatomy.healedCount or 0
    ext.anatomy.lastTick = ext.anatomy.lastTick or 0
    return ext.anatomy
end

local function ensureZoneState(ext, zoneId)
    local anatomy = ensureAnatomy(ext)
    local zoneState = anatomy.zones[zoneId]
    if not zoneState then
        zoneState = Schema.NewZoneState()
        anatomy.zones[zoneId] = zoneState
    end
    zoneState.injuries = zoneState.injuries or {}
    return zoneState
end

local function countZoneInjuries(zoneState)
    local count = 0
    if zoneState and zoneState.injuries then
        for _ in pairs(zoneState.injuries) do
            count = count + 1
        end
    end
    return count
end

local function summarize(injury)
    return {
        id = injury.id,
        zone = injury.zone,
        kind = injury.kind,
        severity = BH.Util.Round(injury.severity or 0, 1),
        bleeding = BH.Util.Round(injury.bleeding or 0, 1),
        contamination = BH.Util.Round(injury.contamination or 0, 1),
        infection = BH.Util.Round(injury.infection or 0, 1),
        status = injury.status,
        bandaged = injury.bandaged == true,
        splinted = injury.splinted == true,
        stitched = injury.stitched == true,
    }
end

Model.Summarize = summarize

function Model.GetZoneState(ext, zoneId, create)
    if type(ext) ~= "table" then
        return nil
    end
    local anatomy = ensureAnatomy(ext)
    local zoneState = anatomy.zones[zoneId]
    if not zoneState and create then
        zoneState = ensureZoneState(ext, zoneId)
    end
    return zoneState
end

function Model.FindInjury(ext, injuryId)
    if type(ext) ~= "table" or type(injuryId) ~= "string" then
        return nil
    end
    local anatomy = ensureAnatomy(ext)
    for zoneId, zoneState in pairs(anatomy.zones) do
        if zoneState.injuries and zoneState.injuries[injuryId] then
            return zoneState.injuries[injuryId], zoneId
        end
    end
    return nil
end

function Model.GetActiveInjuries(ext)
    local result = {}
    if type(ext) ~= "table" then
        return result
    end
    local anatomy = ensureAnatomy(ext)
    for zoneId, zoneState in pairs(anatomy.zones) do
        for _, injury in pairs(zoneState.injuries or {}) do
            if injury.status ~= "healed" then
                result[#result + 1] = injury
            end
        end
    end
    table.sort(result, function(left, right)
        if left.severity == right.severity then
            return left.id < right.id
        end
        return left.severity > right.severity
    end)
    return result
end

local function emitInjuryCreated(ext, injury, opts)
    BH.Events.Emit(BH.Events.Names.CHARACTER_INJURY_CREATED, {
        characterKey = opts.characterKey or (ext.metadata and ext.metadata.ownerKey) or "unknown",
        zone = injury.zone,
        injury = summarize(injury),
    })
end

function Model.AddInjury(ext, zoneId, kind, severity, source, opts)
    if type(ext) ~= "table" then
        return nil, "invalid character data"
    end
    local zone = Zones.Get(zoneId)
    if not zone then
        return nil, "unknown anatomy zone"
    end
    if not Rules.KindWeight[kind] then
        return nil, "unknown injury kind"
    end
    if not BH.Util.IsFiniteNumber(severity) then
        return nil, "invalid severity"
    end

    opts = type(opts) == "table" and opts or {}
    source = source or "unknown"
    if not Schema.ValidSource(source) then
        source = "unknown"
    end

    local zoneState = ensureZoneState(ext, zoneId)
    severity = BH.Util.Clamp(severity, 1, 100)

    if type(opts.dedupeKey) == "string" and opts.dedupeKey ~= "" then
        for _, existing in pairs(zoneState.injuries) do
            if existing.meta and existing.meta.dedupeKey == opts.dedupeKey and existing.status ~= "healed" then
                return existing, "duplicate"
            end
        end
    end

    local maximumPerZone = BH.Config.Get("maxInjuriesPerZone") or 8
    if countZoneInjuries(zoneState) >= maximumPerZone then
        local sameKind = nil
        local lowest = nil
        for _, existing in pairs(zoneState.injuries) do
            if existing.status ~= "healed" and existing.kind == kind then
                if not sameKind or existing.severity < sameKind.severity then
                    sameKind = existing
                end
            end
            if not lowest or existing.severity < lowest.severity then
                lowest = existing
            end
        end

        local target = sameKind or lowest
        if target then
            target.severity = BH.Util.Clamp((target.severity or 0) + severity * 0.45, 1, 100)
            target.bleeding = BH.Util.Clamp((target.bleeding or 0) + severity * 0.25, 0, 100)
            target.contamination = BH.Util.Clamp((target.contamination or 0) + severity * 0.10, 0, 100)
            target.updatedAt = nowHours()
            target.meta = target.meta or {}
            target.meta.mergedCount = (target.meta.mergedCount or 0) + 1
            target.meta.lastMergeKind = kind
            BH.Persistence.Touch(ext)
            BH.Log.Warn("anatomy", "Injury merged at zone cap", {
                zone = zoneId,
                target = target.id,
                kind = kind,
            })
            return target, "merged"
        end
        return nil, "zone injury cap reached"
    end

    local anatomy = ensureAnatomy(ext)
    local sequence = anatomy.nextInjurySeq or 1
    local injuryId = string.format("%s-%06d", zoneId, sequence)
    while zoneState.injuries[injuryId] do
        sequence = sequence + 1
        injuryId = string.format("%s-%06d", zoneId, sequence)
    end
    anatomy.nextInjurySeq = sequence + 1

    local now = opts.now or nowHours()
    local bleedingInitial = opts.bleeding
    if not BH.Util.IsFiniteNumber(bleedingInitial) then
        bleedingInitial = (Rules.InitialBleeding[kind] or 0) * (severity / 100)
    end
    local contaminationInitial = opts.contamination
    if not BH.Util.IsFiniteNumber(contaminationInitial) then
        contaminationInitial = (Rules.InitialContamination[kind] or 0) * (severity / 100)
    end

    local injury = {
        id = injuryId,
        zone = zoneId,
        kind = kind,
        severity = severity,
        bleeding = BH.Util.Clamp(bleedingInitial, 0, 100),
        contamination = BH.Util.Clamp(contaminationInitial, 0, 100),
        infection = BH.Util.Clamp(opts.infection or 0, 0, 100),
        pain = BH.Util.Clamp((Rules.PainFactor[kind] or 0.5) * severity, 0, 100),
        healing = 0,
        status = "active",
        source = source,
        createdAt = now,
        updatedAt = now,
        treatmentCount = 0,
        bandaged = false,
        bandageDirty = false,
        splinted = false,
        stitched = false,
        cleaned = false,
        examined = false,
        meta = {
            dedupeKey = opts.dedupeKey,
            initialSeverity = severity,
            mergedCount = 0,
        },
    }

    if type(opts.meta) == "table" then
        for key, value in pairs(opts.meta) do
            injury.meta[key] = value
        end
    end

    zoneState.injuries[injuryId] = injury
    zoneState.updatedAt = now

    BH.Persistence.Touch(ext)
    emitInjuryCreated(ext, injury, opts)
    if BH.Physiology and BH.Physiology.Recalculate then
        BH.Physiology.Recalculate(ext)
    end
    return injury
end

function Model.HealInjury(ext, injuryId, reason)
    local injury, zoneId = Model.FindInjury(ext, injuryId)
    if not injury then
        return false, "injury not found"
    end
    local zoneState = ensureZoneState(ext, zoneId)
    zoneState.injuries[injuryId] = nil
    ext.anatomy.healedCount = (ext.anatomy.healedCount or 0) + 1
    zoneState.updatedAt = nowHours()

    BH.Persistence.Touch(ext)
    BH.Events.Emit(BH.Events.Names.CHARACTER_INJURY_HEALED, {
        characterKey = ext.metadata and ext.metadata.ownerKey or "unknown",
        zone = zoneId,
        injuryId = injuryId,
        reason = reason or "healed",
        injury = summarize(injury),
    })
    if BH.Physiology and BH.Physiology.Recalculate then
        BH.Physiology.Recalculate(ext)
    end
    return true
end

local function updateInfectionAndBleeding(injury, minutes)
    local previousBleedingBucket = math.floor((injury.bleeding or 0) / 10)

    if injury.bandaged then
        injury.bleeding = math.max(0, (injury.bleeding or 0) - BH.Config.Get("bleedingBandageDecayPerMinute") * minutes)
    else
        injury.bleeding = math.max(0, (injury.bleeding or 0) - BH.Config.Get("bleedingClotPerMinute") * minutes)
    end

    if injury.cleaned then
        injury.contamination = math.max(0, (injury.contamination or 0) - BH.Config.Get("contaminationDecayPerMinute") * minutes)
        injury.infection = math.max(0, (injury.infection or 0) - 0.04 * minutes)
    elseif (injury.contamination or 0) >= BH.Config.Get("infectionThreshold") then
        local growth = BH.Config.Get("infectionGrowthPerMinute") * minutes
        injury.infection = BH.Util.Clamp((injury.infection or 0) + growth, 0, 100)
    end

    if injury.infection >= 100 then
        injury.status = "infected"
    end

    local currentBleedingBucket = math.floor((injury.bleeding or 0) / 10)
    if currentBleedingBucket ~= previousBleedingBucket then
        BH.Events.Emit(BH.Events.Names.CHARACTER_BLEEDING_CHANGED, {
            zone = injury.zone,
            injuryId = injury.id,
            bleeding = BH.Util.Round(injury.bleeding, 1),
            bandaged = injury.bandaged == true,
        })
    end
end

local function updateHealing(ext, injury, minutes)
    if (injury.bleeding or 0) > 0.1 then
        if injury.status ~= "infected" then
            injury.status = "active"
        end
        return false
    end
    if injury.status == "infected" and (injury.infection or 0) >= 80 then
        return false
    end

    local rate = Rules.HealingPerMinute[injury.kind] or 0.05
    if injury.bandaged or injury.cleaned then
        rate = rate * 1.20
    end
    if injury.splinted then
        rate = rate * 1.15
    end
    rate = rate * BH.Config.Get("healingRateMultiplier")
    rate = rate * (1 - (injury.infection or 0) / 150)

    injury.severity = math.max(0, (injury.severity or 0) - rate * minutes)
    local initial = injury.meta and injury.meta.initialSeverity or 100
    if initial > 0 then
        injury.healing = BH.Util.Clamp(100 - (injury.severity / initial) * 100, 0, 100)
    end

    if injury.status ~= "infected" then
        injury.status = injury.severity < initial and "healing" or "active"
    end

    if injury.severity <= 0.5 then
        return true
    end
    return false
end

function Model.Tick(ext, minutes)
    if type(ext) ~= "table" or not BH.Util.IsFiniteNumber(minutes) or minutes <= 0 then
        return 0
    end
    minutes = math.min(minutes, 1440)

    local anatomy = ensureAnatomy(ext)
    local now = nowHours()
    local healed = 0

    for _, zoneState in pairs(anatomy.zones) do
        local ids = {}
        for injuryId in pairs(zoneState.injuries or {}) do
            ids[#ids + 1] = injuryId
        end
        for index = 1, #ids do
            local injury = zoneState.injuries[ids[index]]
            if injury then
                injury.updatedAt = now
                updateInfectionAndBleeding(injury, minutes)
                if updateHealing(ext, injury, minutes) then
                    Model.HealInjury(ext, injury.id, "recovered")
                    healed = healed + 1
                end
            end
        end
        zoneState.updatedAt = now
    end

    anatomy.lastTick = now
    BH.Persistence.Touch(ext)
    if BH.Physiology and BH.Physiology.Recalculate then
        BH.Physiology.Recalculate(ext)
    end
    return healed
end

function Model.GetZoneImpairment(ext, zoneId)
    local zoneState = Model.GetZoneState(ext, zoneId, false)
    if not zoneState then
        return 0
    end
    return Rules.ZoneImpairment(zoneState.injuries)
end

function Model.GetZoneImpairments(ext)
    local result = {}
    if type(ext) ~= "table" then
        return result
    end
    for _, zone in ipairs(Zones.GetAll()) do
        result[zone.id] = Model.GetZoneImpairment(ext, zone.id)
    end
    return result
end

function Model.GetMobility(ext)
    return Rules.Mobility(Model.GetZoneImpairments(ext))
end

function Model.GetManipulation(ext)
    return Rules.Manipulation(Model.GetZoneImpairments(ext))
end

function Model.GetConsciousness(ext)
    return Rules.Consciousness(Model.GetZoneImpairments(ext))
end

function Model.GetRespiration(ext)
    return Rules.Respiration(Model.GetZoneImpairments(ext))
end

function Model.GetBalance(ext)
    return Rules.Balance(Model.GetZoneImpairments(ext))
end

function Model.GetTotalSeverity(ext)
    local total = 0
    local injuries = Model.GetActiveInjuries(ext)
    for index = 1, #injuries do
        total = total + (injuries[index].severity or 0)
    end
    return BH.Util.Clamp(total, 0, 100)
end

function Model.GetPainTarget(ext)
    local total = 0
    if type(ext) ~= "table" then
        return 0
    end
    for _, zoneState in pairs(ensureAnatomy(ext).zones) do
        total = total + Rules.PainFromInjuries(zoneState.injuries)
    end
    return BH.Util.Clamp(total, 0, 100)
end

BH.RegisterModule({
    id = "bh.anatomy",
    version = BH.VERSION,
    requires = { "bh.core", "bh.persistence" },
    description = "Anatomical zones, structured injuries and functional impairment",
    init = function(context)
        Zones.ResolveEngineIndices()
        context.log.Info("anatomy", "Anatomy ready", {
            zones = Zones.Count(),
            engineResolved = BodyPartType ~= nil,
        })
    end,
})

return Model

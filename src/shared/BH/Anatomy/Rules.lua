-- Beautiful Humans / anatomy rules.
-- Pure calculations: no game objects, no events, no persistence.

BH = BH or {}

if BH.Anatomy and BH.Anatomy.Rules then
    return
end

require "BH/Core"

BH.Anatomy = BH.Anatomy or {}

local Rules = {
    KindWeight = {
        abrasion = 0.25,
        bruise = 0.45,
        burn = 0.85,
        cut = 0.70,
        deep_wound = 1.00,
        fracture = 1.25,
        puncture = 0.80,
        sprain = 0.60,
        bite = 1.10,
    },
    InitialBleeding = {
        abrasion = 10,
        bruise = 0,
        burn = 5,
        cut = 45,
        deep_wound = 60,
        fracture = 10,
        puncture = 30,
        sprain = 0,
        bite = 55,
    },
    InitialContamination = {
        abrasion = 10,
        bruise = 0,
        burn = 15,
        cut = 15,
        deep_wound = 30,
        fracture = 5,
        puncture = 25,
        sprain = 0,
        bite = 50,
    },
    PainFactor = {
        abrasion = 0.18,
        bruise = 0.35,
        burn = 0.85,
        cut = 0.55,
        deep_wound = 0.90,
        fracture = 1.10,
        puncture = 0.65,
        sprain = 0.70,
        bite = 1.00,
    },
    HealingPerMinute = {
        abrasion = 0.20,
        bruise = 0.30,
        burn = 0.08,
        cut = 0.14,
        deep_wound = 0.08,
        fracture = 0.04,
        puncture = 0.10,
        sprain = 0.12,
        bite = 0.06,
    },
}
BH.Anatomy.Rules = Rules

function Rules.EffectiveSeverity(injury)
    if type(injury) ~= "table" then
        return 0
    end
    local severity = BH.Util.Clamp(injury.severity or 0, 0, 100)
    local weight = Rules.KindWeight[injury.kind] or 0.5
    local value = severity * weight
    if injury.splinted then
        value = value * 0.65
    end
    if injury.bandaged then
        value = value * 0.90
    end
    if injury.stitched then
        value = value * 0.85
    end
    return BH.Util.Clamp(value, 0, 125)
end

function Rules.ZoneImpairment(injuries)
    local values = {}
    if type(injuries) ~= "table" then
        return 0
    end
    for _, injury in pairs(injuries) do
        if type(injury) == "table" and injury.status ~= "healed" then
            values[#values + 1] = Rules.EffectiveSeverity(injury)
        end
    end
    table.sort(values, function(left, right)
        return left > right
    end)
    if #values == 0 then
        return 0
    end

    local impairment = values[1] / 100
    if values[2] then
        impairment = impairment + (values[2] / 100) * 0.20
    end
    if values[3] then
        impairment = impairment + (values[3] / 100) * 0.08
    end
    for index = 4, #values do
        impairment = impairment + (values[index] / 100) * 0.03
    end
    return BH.Util.Clamp(impairment, 0, 0.95)
end

function Rules.Mobility(zoneImpairments)
    local left = math.max(
        zoneImpairments.left_thigh or 0,
        zoneImpairments.left_shin or 0,
        zoneImpairments.left_foot or 0
    )
    local right = math.max(
        zoneImpairments.right_thigh or 0,
        zoneImpairments.right_shin or 0,
        zoneImpairments.right_foot or 0
    )
    local legs = math.max(left, right) * 0.70 + math.min(left, right) * 0.30
    local torso = math.max(zoneImpairments.abdomen or 0, zoneImpairments.groin or 0) * 0.25
    return BH.Util.Clamp(1 - BH.Util.Clamp(legs + torso, 0, 0.95), 0.05, 1)
end

function Rules.Manipulation(zoneImpairments)
    local left = math.max(zoneImpairments.left_hand or 0, zoneImpairments.left_forearm or 0, zoneImpairments.left_upper_arm or 0)
    local right = math.max(zoneImpairments.right_hand or 0, zoneImpairments.right_forearm or 0, zoneImpairments.right_upper_arm or 0)
    local best = math.min(left, right)
    local worst = math.max(left, right)
    return BH.Util.Clamp(1 - (best * 0.70 + worst * 0.20), 0.10, 1)
end

function Rules.Consciousness(zoneImpairments)
    local value = math.max(zoneImpairments.head or 0, zoneImpairments.neck or 0)
    return BH.Util.Clamp(1 - value * 0.80, 0.10, 1)
end

function Rules.Respiration(zoneImpairments)
    local value = math.max(zoneImpairments.chest or 0, zoneImpairments.neck or 0)
    return BH.Util.Clamp(1 - value * 0.70, 0.15, 1)
end

function Rules.Balance(zoneImpairments)
    local left = zoneImpairments.left_foot or 0
    local right = zoneImpairments.right_foot or 0
    return BH.Util.Clamp(1 - math.max(left, right) * 0.60 - math.min(left, right) * 0.20, 0.10, 1)
end

function Rules.PainFromInjuries(injuries)
    local pain = 0
    if type(injuries) ~= "table" then
        return 0
    end
    for _, injury in pairs(injuries) do
        if type(injury) == "table" and injury.status ~= "healed" then
            local factor = Rules.PainFactor[injury.kind] or 0.5
            pain = pain + (injury.severity or 0) * factor
        end
    end
    return BH.Util.Clamp(pain, 0, 100)
end

return Rules

-- Beautiful Humans / physiological consequences.
-- This module does not duplicate hunger, thirst or fatigue: it derives pain,
-- blood-loss load and functional capacity from BH injuries and exposes them to
-- medical and gameplay rules.

BH = BH or {}

if BH.Physiology and BH.Physiology._loaded then
    return
end

require "BH/Core"
require "BH/Anatomy/Model"

BH.Physiology = BH.Physiology or {}
local Physiology = BH.Physiology
Physiology._loaded = true

local function ensure(ext)
    ext.physiology = ext.physiology or {}
    ext.physiology.pain = BH.Util.Clamp(ext.physiology.pain or 0, 0, 100)
    ext.physiology.bloodLoss = BH.Util.Clamp(ext.physiology.bloodLoss or 0, 0, 100)
    ext.physiology.fatigue = BH.Util.Clamp(ext.physiology.fatigue or 0, 0, 100)
    ext.physiology.lastUpdate = ext.physiology.lastUpdate or 0
    return ext.physiology
end

local function moveTowards(current, target, maximumDelta)
    if target > current then
        return math.min(target, current + maximumDelta)
    end
    return math.max(target, current - maximumDelta)
end

function Physiology.Recalculate(ext)
    if type(ext) ~= "table" or not BH.Anatomy or not BH.Anatomy.Model then
        return nil
    end
    local physiology = ensure(ext)
    local model = BH.Anatomy.Model

    local painTarget = model.GetPainTarget(ext)
    local bloodTarget = 0
    local injuries = model.GetActiveInjuries(ext)
    for index = 1, #injuries do
        bloodTarget = bloodTarget + (injuries[index].bleeding or 0) * 0.8
    end
    bloodTarget = BH.Util.Clamp(bloodTarget, 0, 100)

    physiology.pain = painTarget
    physiology.bloodLoss = bloodTarget
    physiology.lastUpdate = BH.Persistence and BH.Persistence.GetGameTimeHours() or 0

    return physiology
end

function Physiology.Tick(ext, minutes)
    if type(ext) ~= "table" or not BH.Util.IsFiniteNumber(minutes) or minutes <= 0 then
        return
    end
    local physiology = ensure(ext)
    local beforePain = physiology.pain
    local beforeBlood = physiology.bloodLoss

    local painTarget = BH.Anatomy.Model.GetPainTarget(ext)
    local bloodTarget = 0
    local injuries = BH.Anatomy.Model.GetActiveInjuries(ext)
    for index = 1, #injuries do
        bloodTarget = bloodTarget + (injuries[index].bleeding or 0) * 0.8
    end
    bloodTarget = BH.Util.Clamp(bloodTarget, 0, 100)

    physiology.pain = moveTowards(physiology.pain, painTarget, 4.0 * minutes)
    physiology.bloodLoss = moveTowards(physiology.bloodLoss, bloodTarget, 1.5 * minutes)
    physiology.lastUpdate = BH.Persistence and BH.Persistence.GetGameTimeHours() or 0

    if math.abs(physiology.pain - beforePain) >= 0.5 or math.abs(physiology.bloodLoss - beforeBlood) >= 0.5 then
        BH.Events.Emit(BH.Events.Names.CHARACTER_PHYSIOLOGY_CHANGED, {
            characterKey = ext.metadata and ext.metadata.ownerKey or "unknown",
            pain = BH.Util.Round(physiology.pain, 1),
            bloodLoss = BH.Util.Round(physiology.bloodLoss, 1),
            fatigue = BH.Util.Round(physiology.fatigue, 1),
        })
    end
end

function Physiology.GetModifiers(ext)
    local physiology = ensure(ext)
    local model = BH.Anatomy.Model
    return {
        pain = physiology.pain,
        bloodLoss = physiology.bloodLoss,
        fatigue = physiology.fatigue,
        mobility = model.GetMobility(ext),
        manipulation = model.GetManipulation(ext),
        consciousness = model.GetConsciousness(ext),
        respiration = model.GetRespiration(ext),
        balance = model.GetBalance(ext),
    }
end

function Physiology.GetCapacity(ext)
    local modifiers = Physiology.GetModifiers(ext)
    local painPenalty = 1 - (modifiers.pain / 100) * 0.25
    local bloodPenalty = 1 - (modifiers.bloodLoss / 100) * 0.35
    local fatiguePenalty = 1 - (modifiers.fatigue / 100) * 0.20
    return BH.Util.Clamp(
        modifiers.mobility
            * modifiers.manipulation
            * modifiers.consciousness
            * modifiers.respiration
            * painPenalty
            * bloodPenalty
            * fatiguePenalty,
        0,
        1
    )
end

BH.RegisterModule({
    id = "bh.physiology",
    version = BH.VERSION,
    requires = { "bh.core", "bh.anatomy" },
    description = "Pain, blood-loss load and functional capacity derived from injuries",
    init = function(context)
        context.log.Info("physiology", "Physiology ready")
    end,
})

return Physiology

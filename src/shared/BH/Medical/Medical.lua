-- Beautiful Humans / medical rules.
-- Treatment definitions are validated here, but inventory, timed actions,
-- animation and networking belong to integration/UI layers.

BH = BH or {}

if BH.Medical and BH.Medical._loaded then
    return
end

require "BH/Core"
require "BH/Anatomy/Model"
require "BH/Physiology/Physiology"
require "BH/Medical/Treatments"

BH.Medical = BH.Medical or {}
local Medical = BH.Medical
Medical._loaded = true
Medical.Treatments = BH.Medical.Treatments

local Model = BH.Anatomy.Model
local Treatments = BH.Medical.Treatments

local function nowHours()
    return BH.Persistence and BH.Persistence.GetGameTimeHours() or 0
end

local function requirementSatisfied(requirement, ctx)
    if type(requirement) ~= "table" then
        return false, "invalid requirement"
    end
    if ctx.bypassItems == true then
        return true
    end
    if type(ctx.hasItem) ~= "function" then
        return false, "item check unavailable"
    end
    for index = 1, #(requirement.any or {}) do
        local item = requirement.any[index]
        local ok, present = pcall(ctx.hasItem, item)
        if ok and present then
            return true
        end
    end
    return false, "missing " .. tostring(requirement.label or "item")
end

function Medical.CanApply(ext, injuryId, actionId, ctx)
    if type(ext) ~= "table" then
        return false, "invalid character data"
    end
    ctx = type(ctx) == "table" and ctx or {}

    local injury = Model.FindInjury(ext, injuryId)
    if not injury then
        return false, "injury not found"
    end
    if injury.status == "healed" then
        return false, "injury already healed"
    end

    local treatment = Treatments.Get(actionId)
    if not treatment then
        return false, "unknown treatment"
    end
    if treatment.validKinds and not treatment.validKinds[injury.kind] then
        return false, "treatment is not suitable for this injury"
    end

    if actionId == "clean" and (injury.contamination or 0) <= 0.1 then
        return false, "wound is already clean"
    end
    if actionId == "bandage" and injury.bandaged then
        return false, "wound is already bandaged"
    end
    if actionId == "splint" and injury.splinted then
        return false, "wound is already splinted"
    end
    if actionId == "stitch" and injury.stitched then
        return false, "wound is already stitched"
    end
    if actionId == "remove_bandage" and not injury.bandaged then
        return false, "wound is not bandaged"
    end

    if BH.Config.Get("treatmentItemCheck") and #treatment.requirements > 0 then
        for index = 1, #treatment.requirements do
            local ok, reason = requirementSatisfied(treatment.requirements[index], ctx)
            if not ok then
                return false, reason, treatment, injury
            end
        end
    end

    return true, nil, treatment, injury
end

local function isProcessed(ext, requestId)
    if type(requestId) ~= "string" or requestId == "" then
        return false
    end
    return ext.medical ~= nil
        and ext.medical.processedRequests ~= nil
        and ext.medical.processedRequests[requestId] == true
end

local function markProcessed(ext, requestId)
    if type(requestId) ~= "string" or requestId == "" then
        return false
    end
    ext.medical = ext.medical or {}
    ext.medical.processedRequests = ext.medical.processedRequests or {}
    if ext.medical.processedRequests[requestId] then
        return true
    end

    ext.medical.processedRequests[requestId] = true
    ext.medical.processedSeq = (ext.medical.processedSeq or 0) + 1

    local limit = BH.Config.Get("maxProcessedRequests") or 32
    local count = 0
    for _ in pairs(ext.medical.processedRequests) do
        count = count + 1
    end
    if count > limit then
        local keys = {}
        for key in pairs(ext.medical.processedRequests) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for index = 1, count - limit do
            ext.medical.processedRequests[keys[index]] = nil
        end
    end
    return false
end

local function applyEffects(ext, injury, actionId, ctx)
    ext.medical = ext.medical or {}
    ext.medical.lastActionAt = ext.medical.lastActionAt or 0
    local changes = {}
    local now = nowHours()

    if actionId == "examine" then
        injury.examined = true
        injury.meta.examinedAt = now
        changes.examined = true
    elseif actionId == "clean" then
        local before = injury.contamination or 0
        injury.contamination = math.max(0, before - 55)
        injury.infection = math.max(0, (injury.infection or 0) - 5)
        injury.cleaned = true
        injury.meta.cleanedAt = now
        changes.contamination = BH.Util.Round(injury.contamination - before, 1)
    elseif actionId == "bandage" then
        local before = injury.bleeding or 0
        injury.bleeding = math.max(0, before - 80)
        injury.bandaged = true
        injury.bandageDirty = ctx.itemIsDirty == true
        injury.meta.bandagedAt = now
        changes.bleeding = BH.Util.Round(injury.bleeding - before, 1)
    elseif actionId == "splint" then
        injury.splinted = true
        injury.meta.splintedAt = now
        changes.splinted = true
    elseif actionId == "stitch" then
        local before = injury.bleeding or 0
        injury.stitched = true
        injury.bleeding = math.max(0, before - 50)
        injury.meta.stitchedAt = now
        changes.stitched = true
        changes.bleeding = BH.Util.Round(injury.bleeding - before, 1)
    elseif actionId == "remove_bandage" then
        injury.bandaged = false
        injury.bandageDirty = false
        if (injury.severity or 0) > 40 then
            injury.bleeding = math.max(injury.bleeding or 0, (injury.severity or 0) * 0.25)
        end
        injury.meta.bandageRemovedAt = now
        changes.bandaged = false
    end

    injury.updatedAt = now
    injury.treatmentCount = (injury.treatmentCount or 0) + 1
    ext.medical.lastActionAt = now
    return changes
end

function Medical.Apply(ext, injuryId, actionId, ctx)
    ctx = type(ctx) == "table" and ctx or {}

    if isProcessed(ext, ctx.requestId) then
        return {
            ok = false,
            duplicate = true,
            error = "request already processed",
            action = actionId,
            injuryId = injuryId,
        }
    end

    local ok, reason, treatment, injury = Medical.CanApply(ext, injuryId, actionId, ctx)
    if not ok then
        return { ok = false, error = reason, action = actionId, injuryId = injuryId }
    end

    markProcessed(ext, ctx.requestId)
    local changes = applyEffects(ext, injury, actionId, ctx)

    local consume = {}
    for index = 1, #treatment.requirements do
        if treatment.requirements[index].consume then
            consume[#consume + 1] = treatment.requirements[index]
        end
    end

    BH.Persistence.Touch(ext)
    if BH.Physiology and BH.Physiology.Recalculate then
        BH.Physiology.Recalculate(ext)
    end

    BH.Events.Emit(BH.Events.Names.CHARACTER_TREATMENT_APPLIED, {
        characterKey = ext.metadata and ext.metadata.ownerKey or "unknown",
        injuryId = injury.id,
        zone = injury.zone,
        action = actionId,
        changes = changes,
        injury = Model.Summarize(injury),
    })

    return {
        ok = true,
        duplicate = false,
        action = actionId,
        injuryId = injuryId,
        changes = changes,
        consume = consume,
        injury = Model.Summarize(injury),
    }
end

function Medical.GetAvailableActions(ext, injuryId, ctx)
    local result = {}
    for index = 1, #Treatments.order do
        local actionId = Treatments.order[index]
        local treatment = Treatments.Get(actionId)
        local ok, reason = Medical.CanApply(ext, injuryId, actionId, ctx)
        result[#result + 1] = {
            id = actionId,
            label = treatment and treatment.label or actionId,
            duration = treatment and treatment.duration or 0,
            available = ok,
            reason = reason,
        }
    end
    return result
end

function Medical.GetDiagnosis(ext, injuryId)
    local injury = Model.FindInjury(ext, injuryId)
    if not injury then
        return nil
    end
    local summary = Model.Summarize(injury)
    if not injury.examined then
        summary.severityExact = false
        summary.severityBand = "unknown"
    else
        summary.severityExact = true
        if injury.severity >= 70 then
            summary.severityBand = "severe"
        elseif injury.severity >= 40 then
            summary.severityBand = "moderate"
        else
            summary.severityBand = "minor"
        end
    end
    return summary
end

BH.RegisterModule({
    id = "bh.medical",
    version = BH.VERSION,
    requires = { "bh.core", "bh.anatomy", "bh.physiology" },
    description = "Wound diagnosis, treatment validation and treatment effects",
    init = function(context)
        context.log.Info("medical", "Medical ready", {
            treatments = #Treatments.order,
        })
    end,
})

return Medical

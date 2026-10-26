local function inventory(tags)
    local available = {}
    for index = 1, #tags do
        available[tags[index]] = true
    end
    return {
        hasItem = function(tag)
            return available[tag] == true
        end,
    }
end

local function newInjury(kind, severity, zone)
    local data = BH.Persistence.NewCharacterData()
    local injury = BH.Anatomy.Model.AddInjury(data, zone or "left_thigh", kind or "cut", severity or 60, "debug")
    return data, injury
end

describe("Medical", function()
    it("rejects bandaging without a bandage", function()
        local data, injury = newInjury("cut", 60)
        local ok, reason = BH.Medical.CanApply(data, injury.id, "bandage", { hasItem = function() return false end })
        falsy(ok)
        contains(reason, "bandage")
    end)

    it("applies a bandage and stops bleeding", function()
        local data, injury = newInjury("cut", 60)
        local result = BH.Medical.Apply(data, injury.id, "bandage", {
            hasItem = function(tag) return tag == "Bandage" end,
            requestId = "bandage-1",
        })
        truthy(result.ok)
        truthy(injury.bandaged)
        truthy(injury.bleeding < 1)
        eq(injury.treatmentCount, 1)
        eq(#result.consume, 1)
    end)

    it("is idempotent for a repeated request id", function()
        local data, injury = newInjury("cut", 60)
        local context = {
            hasItem = function(tag) return tag == "Bandage" end,
            requestId = "same-request",
        }
        local first = BH.Medical.Apply(data, injury.id, "bandage", context)
        truthy(first.ok)
        local second = BH.Medical.Apply(data, injury.id, "bandage", context)
        falsy(second.ok)
        truthy(second.duplicate)
        eq(injury.treatmentCount, 1)
    end)

    it("rejects a second bandage while one is present", function()
        local data, injury = newInjury("cut", 60)
        local context = {
            hasItem = function(tag) return tag == "Bandage" end,
            requestId = "bandage-2",
        }
        truthy(BH.Medical.Apply(data, injury.id, "bandage", context).ok)
        local ok, reason = BH.Medical.CanApply(data, injury.id, "bandage", context)
        falsy(ok)
        contains(reason, "already bandaged")
    end)

    it("removing a bandage can restart bleeding", function()
        local data, injury = newInjury("cut", 90)
        injury.bandaged = true
        injury.bleeding = 0
        local result = BH.Medical.Apply(data, injury.id, "remove_bandage", {
            requestId = "remove-1",
        })
        truthy(result.ok)
        falsy(injury.bandaged)
        truthy(injury.bleeding > 0)
    end)

    it("splints a fracture when both materials are present", function()
        local data, injury = newInjury("fracture", 70)
        local items = inventory({ "Splint", "Bandage" })
        local result = BH.Medical.Apply(data, injury.id, "splint", {
            hasItem = items.hasItem,
            requestId = "splint-1",
        })
        truthy(result.ok)
        truthy(injury.splinted)
        eq(#result.consume, 2)
    end)

    it("rejects a splint without binding", function()
        local data, injury = newInjury("fracture", 70)
        local ok, reason = BH.Medical.CanApply(data, injury.id, "splint", {
            hasItem = function(tag) return tag == "Splint" end,
        })
        falsy(ok)
        contains(reason, "binding")
    end)

    it("cleans contamination but rejects cleaning a clean wound", function()
        local data, injury = newInjury("cut", 60)
        local context = {
            hasItem = function(tag) return tag == "Water" end,
            requestId = "clean-1",
        }
        local before = injury.contamination
        local result = BH.Medical.Apply(data, injury.id, "clean", context)
        truthy(result.ok)
        truthy(injury.contamination < before)
        local ok, reason = BH.Medical.CanApply(data, injury.id, "clean", context)
        falsy(ok)
        contains(reason, "already clean")
    end)

    it("reports unknown actions and invalid injury ids", function()
        local data, injury = newInjury("cut", 60)
        local ok, reason = BH.Medical.CanApply(data, injury.id, "amputate", {})
        falsy(ok)
        contains(reason, "unknown treatment")

        local missing, missingReason = BH.Medical.CanApply(data, "no-such-injury", "bandage", {})
        falsy(missing)
        contains(missingReason, "not found")
    end)

    it("hides exact severity until examined", function()
        local data, injury = newInjury("cut", 60)
        local diagnosis = BH.Medical.GetDiagnosis(data, injury.id)
        falsy(diagnosis.severityExact)
        eq(diagnosis.severityBand, "unknown")

        BH.Medical.Apply(data, injury.id, "examine", { requestId = "examine-1" })
        local examined = BH.Medical.GetDiagnosis(data, injury.id)
        truthy(examined.severityExact)
        truthy(examined.severityBand ~= "unknown")
    end)

    it("lists available actions without changing state", function()
        local data, injury = newInjury("fracture", 60)
        local actions = BH.Medical.GetAvailableActions(data, injury.id, {
            hasItem = function(tag) return tag == "Splint" or tag == "Bandage" end,
        })
        truthy(#actions >= 5)
        local foundSplint = false
        for index = 1, #actions do
            if actions[index].id == "splint" then
                foundSplint = actions[index].available
            end
        end
        truthy(foundSplint)
    end)
end)

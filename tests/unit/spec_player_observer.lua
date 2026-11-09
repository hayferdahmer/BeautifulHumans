describe("Player observer / BodyPart API", function()
    it("reads Build 42 BodyPart injury methods using their actual names", function()
        local part = {
            bitten = function() return true end,
            isCut = function() return true end,
            scratched = function() return true end,
            isDeepWounded = function() return true end,
            getFractureTime = function() return 12 end,
            getBurnTime = function() return 8 end,
            getBleedingTime = function() return 5 end,
            bandaged = function() return true end,
            getWoundInfectionLevel = function() return 0.25 end,
            getHealth = function() return 72 end,
        }

        local state = BH.Integration.Player.ReadPartState(part)
        truthy(state.bitten)
        truthy(state.cut)
        truthy(state.scratched)
        truthy(state.deepWounded)
        truthy(state.fracture)
        truthy(state.burn)
        truthy(state.bleeding)
        truthy(state.bandaged)
        approx(state.infection, 0.25)
        eq(state.health, 72)
    end)

    it("keeps absent BodyPart methods on safe fallback values", function()
        local state = BH.Integration.Player.ReadPartState({})
        falsy(state.bitten)
        falsy(state.cut)
        falsy(state.scratched)
        falsy(state.deepWounded)
        falsy(state.fracture)
        falsy(state.burn)
        falsy(state.bleeding)
        falsy(state.bandaged)
        eq(state.infection, 0)
        eq(state.health, 100)
    end)
end)

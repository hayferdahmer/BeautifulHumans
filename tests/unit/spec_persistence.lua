local function fakePlayer(username)
    local player = {
        _modData = {},
        _username = username or "Tester",
        _onlineId = 17,
    }
    function player:getModData()
        return self._modData
    end
    function player:getUsername()
        return self._username
    end
    function player:getOnlineID()
        return self._onlineId
    end
    return player
end

local function clearCache()
    BH.Persistence.cache = BH.Util.WeakKeys()
end

describe("Persistence", function()
    it("creates and reuses a versioned character extension", function()
        clearCache()
        local player = fakePlayer()
        local first = BH.Persistence.GetCharacterData(player)
        truthy(first)
        eq(first.schemaVersion, 1)
        eq(first.anatomy.nextInjurySeq, 1)
        local second = BH.Persistence.GetCharacterData(player)
        eq(first, second)
    end)

    it("preserves injuries across a simulated reload", function()
        clearCache()
        local player = fakePlayer("Reload")
        local data = BH.Persistence.GetCharacterData(player)
        local injury = BH.Anatomy.Model.AddInjury(data, "left_thigh", "cut", 50, "debug")
        truthy(injury)
        eq(BH.Persistence.CountInjuries(data), 1)

        clearCache()
        local reloaded = BH.Persistence.GetCharacterData(player)
        eq(BH.Persistence.CountInjuries(reloaded), 1)
        local found = BH.Anatomy.Model.FindInjury(reloaded, injury.id)
        truthy(found)
        eq(found.zone, "left_thigh")
    end)

    it("does not duplicate an injury on reload", function()
        clearCache()
        local player = fakePlayer("NoDuplicate")
        local data = BH.Persistence.GetCharacterData(player)
        BH.Anatomy.Model.AddInjury(data, "right_hand", "abrasion", 20, "debug")

        clearCache()
        local reloaded = BH.Persistence.GetCharacterData(player)
        BH.Anatomy.Model.AddInjury(reloaded, "right_hand", "abrasion", 20, "debug")
        eq(BH.Persistence.CountInjuries(reloaded), 2)

        local ids = {}
        for _, injury in ipairs(BH.Anatomy.Model.GetActiveInjuries(reloaded)) do
            falsy(ids[injury.id])
            ids[injury.id] = true
        end
    end)

    it("quarantines corrupt records and creates a clean extension", function()
        clearCache()
        local player = fakePlayer("Corrupt")
        player._modData.BH = "not a table"
        local data, reason = BH.Persistence.GetCharacterData(player)
        truthy(data)
        eq(data.schemaVersion, 1)
        contains(tostring(reason), "not a table")
        eq(type(player._modData.BH_QUARANTINE), "table")
        eq(type(player._modData.BH_QUARANTINE.reason), "string")
    end)

    it("rejects a future schema without destroying the save slot", function()
        clearCache()
        local player = fakePlayer("Future")
        player._modData.BH = { schemaVersion = 99 }
        local data = BH.Persistence.GetCharacterData(player)
        truthy(data)
        eq(data.schemaVersion, 1)
        eq(player._modData.BH_QUARANTINE.reason ~= nil, true)
    end)

    it("migrates a v0 flat injury list", function()
        clearCache()
        local player = fakePlayer("Legacy")
        player._modData.BH = {
            schemaVersion = 0,
            injuries = {
                { id = "old-1", zone = "left_thigh", kind = "cut", severity = 30, source = "debug" },
            },
        }
        local data = BH.Persistence.GetCharacterData(player)
        truthy(data)
        eq(data.schemaVersion, 1)
        eq(BH.Persistence.CountInjuries(data), 1)
        local injury = BH.Anatomy.Model.FindInjury(data, "old-1")
        truthy(injury)
        eq(injury.zone, "left_thigh")
    end)

    it("repairs invalid fields instead of throwing", function()
        clearCache()
        local player = fakePlayer("Repair")
        player._modData.BH = {
            schemaVersion = 1,
            anatomy = {
                zones = {
                    left_thigh = {
                        injuries = {
                            ["bad-1"] = { id = "bad-1", zone = "left_thigh", kind = "nonsense", severity = 9999 },
                        },
                    },
                },
            },
        }
        local data = BH.Persistence.GetCharacterData(player)
        truthy(data)
        local injury = BH.Anatomy.Model.FindInjury(data, "bad-1")
        truthy(injury)
        eq(injury.kind, "abrasion")
        truthy(injury.severity <= 100)
    end)
end)

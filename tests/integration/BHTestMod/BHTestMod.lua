-- Beautiful Humans / runtime test mod.
-- Loaded by Project Zomboid after BeautifulHumansCore. Prints a single
-- machine-readable result line and stores a small report in global modData.

BH = BH or {}

if BH.TestMod and BH.TestMod._loaded then
    return
end

require "BH/Core"
require "BH/Persistence/Persistence"
require "BH/Anatomy/Model"
require "BH/Medical/Medical"

BH.TestMod = {
    _loaded = true,
    results = {},
}

local Test = BH.TestMod

local function check(name, condition, detail)
    Test.results[#Test.results + 1] = {
        name = name,
        ok = condition == true,
        detail = detail and tostring(detail) or nil,
    }
    if not condition then
        print("[BHTest] FAIL " .. name .. (detail and (" :: " .. tostring(detail)) or ""))
    end
end

local function fakePlayer()
    local player = {
        _modData = {},
        _username = "BHTestPlayer",
    }
    function player:getModData()
        return self._modData
    end
    function player:getUsername()
        return self._username
    end
    function player:getOnlineID()
        return 999
    end
    return player
end

function Test.Run()
    check("core version", type(BH.VERSION) == "string" and #BH.VERSION > 0, BH.VERSION)
    check("core module", BH.Modules.GetStatus("bh.core") == "ready", BH.Modules.GetStatus("bh.core"))
    check("anatomy module", BH.Modules.GetStatus("bh.anatomy") == "ready", BH.Modules.GetStatus("bh.anatomy"))
    check("medical module", BH.Modules.GetStatus("bh.medical") == "ready", BH.Modules.GetStatus("bh.medical"))
    check("zone count", BH.Anatomy.Zones.Count() == 17, BH.Anatomy.Zones.Count())

    local player = fakePlayer()
    local data = BH.Persistence.GetCharacterData(player)
    check("persistence", data ~= nil and data.schemaVersion == 1, data and data.schemaVersion)

    if data then
        local injury = BH.Anatomy.Model.AddInjury(data, "left_thigh", "cut", 55, "debug", {
            characterKey = "test",
        })
        check("injury creation", injury ~= nil, injury and injury.id)
        if injury then
            local result = BH.Medical.Apply(data, injury.id, "bandage", {
                bypassItems = true,
                requestId = "integration-bandage-1",
            })
            check("treatment", result.ok == true, result.error)
            check("bleeding stopped", injury.bleeding < 1, injury.bleeding)
        end

        BH.Persistence.cache = BH.Util.WeakKeys()
        local reloaded = BH.Persistence.GetCharacterData(player)
        check("reload", BH.Persistence.CountInjuries(reloaded) == 1, BH.Persistence.CountInjuries(reloaded))
    end

    local eventSeen = false
    local token = BH.Events.On("Test.Runtime", function()
        eventSeen = true
    end, 0)
    BH.Events.Emit("Test.Runtime", {})
    BH.Events.Off(token)
    check("event bus", eventSeen)

    local failures = 0
    for index = 1, #Test.results do
        if not Test.results[index].ok then
            failures = failures + 1
        end
    end

    Test.passed = failures == 0
    Test.failures = failures

    local report = {
        passed = Test.passed,
        failures = failures,
        total = #Test.results,
        version = BH.VERSION,
        gameVersion = BH.GetGameVersionString(),
        results = Test.results,
    }

    local ok, modData = pcall(function()
        return ModData.getOrCreate("BH_TEST_RESULTS")
    end)
    if ok and type(modData) == "table" then
        modData.report = report
    end

    print(string.format("BH_TEST_RESULT %s total=%d failures=%d version=%s",
        Test.passed and "PASS" or "FAIL",
        #Test.results,
        failures,
        BH.VERSION))
    return Test.passed
end

BH.RegisterModule({
    id = "bh.testmod",
    version = "0.1.0",
    requires = { "bh.core", "bh.persistence", "bh.anatomy", "bh.physiology", "bh.medical" },
    init = function(context)
        context.log.Info("testmod", "Test module initialised")
    end,
})

local function runOnce()
    if Test._ran then
        return
    end
    Test._ran = true

    local ok, errorMessage = pcall(BH.Start)
    if not ok then
        print("[BHTest] FAIL core start :: " .. tostring(errorMessage))
        print("BH_TEST_RESULT FAIL total=0 failures=1")
        return
    end
    Test.Run()
end

local registered = false
if Events then
    if Events.OnGameStart then
        Events.OnGameStart.Add(runOnce)
        registered = true
    end
    if Events.OnServerStarted then
        Events.OnServerStarted.Add(runOnce)
        registered = true
    end
end

if not registered then
    print("[BHTest] FAIL no supported game-start event")
end

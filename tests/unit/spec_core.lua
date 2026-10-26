describe("Core and modules", function()
    it("resolves dependencies before consumers", function()
        local Modules = BH.Modules
        Modules.Reset()
        BH.RegisterModule({ id = "test.consumer", version = "1", requires = { "test.provider" }, init = function() end })
        BH.RegisterModule({ id = "test.provider", version = "1", init = function() end })

        local order = Modules.Resolve()
        eq(#order, 2)
        eq(order[1], "test.provider")
        eq(order[2], "test.consumer")
        Modules.Reset()
    end)

    it("does not register duplicate module ids", function()
        local Modules = BH.Modules
        Modules.Reset()
        truthy(Modules.Register({ id = "test.duplicate", version = "1", init = function() end }))
        local ok, reason = Modules.Register({ id = "test.duplicate", version = "1", init = function() end })
        falsy(ok)
        contains(reason, "duplicate")
        Modules.Reset()
    end)

    it("blocks only the module with a missing dependency", function()
        local Modules = BH.Modules
        Modules.Reset()
        BH.RegisterModule({ id = "test.blocked", version = "1", requires = { "test.missing" }, init = function() end })
        BH.RegisterModule({ id = "test.independent", version = "1", init = function() end })

        local order, report = Modules.Resolve()
        eq(#order, 1)
        eq(order[1], "test.independent")
        truthy(report.missing["test.missing"])
        truthy(report.blocked["test.blocked"])
        Modules.Reset()
    end)

    it("detects cycles without hanging", function()
        local Modules = BH.Modules
        Modules.Reset()
        BH.RegisterModule({ id = "test.a", version = "1", requires = { "test.b" }, init = function() end })
        BH.RegisterModule({ id = "test.b", version = "1", requires = { "test.a" }, init = function() end })

        local order, report = Modules.Resolve()
        eq(#order, 0)
        truthy(#report.cycles > 0)
        truthy(report.blocked["test.a"])
        truthy(report.blocked["test.b"])
        Modules.Reset()
    end)

    it("initialises independent modules when another module fails", function()
        local Modules = BH.Modules
        Modules.Reset()
        BH.RegisterModule({ id = "test.failure", version = "1", init = function() error("boom") end })
        BH.RegisterModule({ id = "test.dependent", version = "1", requires = { "test.failure" }, init = function() end })
        BH.RegisterModule({ id = "test.survivor", version = "1", init = function() end })

        local results = Modules.InitAll({})
        eq(results["test.failure"].status, "failed")
        eq(results["test.dependent"].status, "skipped")
        eq(results["test.survivor"].status, "ready")
        Modules.Reset()
    end)
end)

describe("Event bus", function()
    it("orders subscribers by priority and registration order", function()
        BH.Events.Clear()
        local order = {}
        BH.Events.On("Test.Order", function() order[#order + 1] = "normal" end, 0)
        BH.Events.On("Test.Order", function() order[#order + 1] = "high" end, 10)
        BH.Events.On("Test.Order", function() order[#order + 1] = "second-normal" end, 0)

        local delivered = BH.Events.Emit("Test.Order", {})
        eq(delivered, 3)
        eq(order[1], "high")
        eq(order[2], "normal")
        eq(order[3], "second-normal")
        BH.Events.Clear()
    end)

    it("isolates a failing subscriber", function()
        BH.Events.Clear()
        local reached = false
        BH.Events.On("Test.Error", function() error("handler failure") end, 10)
        BH.Events.On("Test.Error", function() reached = true end, 0)

        local delivered = BH.Events.Emit("Test.Error", {})
        eq(delivered, 1)
        truthy(reached)
        BH.Events.Clear()
    end)

    it("blocks re-entrant emission of the same event", function()
        BH.Events.Clear()
        local calls = 0
        BH.Events.On("Test.Reentrant", function()
            calls = calls + 1
            BH.Events.Emit("Test.Reentrant", {})
        end, 0)

        BH.Events.Emit("Test.Reentrant", {})
        eq(calls, 1)
        BH.Events.Clear()
    end)

    it("removes a subscriber by token", function()
        BH.Events.Clear()
        local calls = 0
        local token = BH.Events.On("Test.Off", function() calls = calls + 1 end, 0)
        BH.Events.Emit("Test.Off", {})
        BH.Events.Off(token)
        BH.Events.Emit("Test.Off", {})
        eq(calls, 1)
        BH.Events.Clear()
    end)
end)

describe("Configuration", function()
    it("rejects invalid values and keeps defaults", function()
        BH.Config.Reset()
        local before = BH.Config.Get("tickInterval")
        local ok = BH.Config.Set("tickInterval", -5)
        falsy(ok)
        eq(BH.Config.Get("tickInterval"), before)
        truthy(BH.Config.Set("tickInterval", 45))
        eq(BH.Config.Get("tickInterval"), 45)
        BH.Config.Reset()
    end)
end)

describe("Simulation clock", function()
    it("returns elapsed time from an injected source", function()
        local value = 10
        local clock = BH.Simulation.Clock.New(function() return value end)
        local now, elapsed = clock:Read()
        eq(now, 10)
        eq(elapsed, 0)
        value = 12.5
        now, elapsed = clock:Read()
        eq(now, 12.5)
        eq(elapsed, 2.5)
    end)

    it("clamps backwards time and never returns negative elapsed", function()
        local value = 8
        local clock = BH.Simulation.Clock.New(function() return value end)
        clock:Read()
        value = 3
        local now, elapsed = clock:Read()
        eq(now, 8)
        eq(elapsed, 0)
    end)

    it("rejects invalid sources and non-finite readings", function()
        local clock = BH.Simulation.Clock.New(function() return 0 / 0 end)
        local now, elapsed, reason = clock:Read()
        eq(now, nil)
        eq(elapsed, 0)
        truthy(reason)
        local invalid = BH.Simulation.Clock.New("not a function")
        eq(invalid, nil)
    end)

    it("supports explicit reset", function()
        local clock = BH.Simulation.Clock.New(function() return 15 end)
        clock:Read()
        truthy(clock:Reset(2))
        local now, elapsed = clock:Read()
        eq(now, 15)
        eq(elapsed, 13)
        falsy(clock:Reset(math.huge))
    end)
end)

describe("Simulation scheduler", function()
    it("waits for the interval and passes elapsed game time", function()
        local scheduler = BH.Simulation.Scheduler.New()
        local calls = {}
        truthy(scheduler:Register({
            id = "test.metabolism",
            interval = 2,
            onTick = function(elapsed, now)
                calls[#calls + 1] = { elapsed = elapsed, now = now }
            end,
        }))
        local ok, first = scheduler:Tick(10)
        truthy(ok)
        eq(first.executed, 0)
        scheduler:Tick(11.9)
        eq(#calls, 0)
        scheduler:Tick(12)
        eq(#calls, 1)
        eq(calls[1].elapsed, 2)
        eq(calls[1].now, 12)
    end)

    it("runs a delayed process once with accumulated elapsed time", function()
        local scheduler = BH.Simulation.Scheduler.New()
        local elapsedReceived = 0
        scheduler:Register({
            id = "test.catchup",
            interval = 1,
            onTick = function(elapsed) elapsedReceived = elapsed end,
        })
        scheduler:Tick(0)
        local ok, stats = scheduler:Tick(100000)
        truthy(ok)
        eq(stats.executed, 1)
        eq(elapsedReceived, 100000)
        scheduler:Tick(100000)
        eq(elapsedReceived, 100000)
    end)

    it("orders due processes by priority and stable id", function()
        local scheduler = BH.Simulation.Scheduler.New()
        local order = {}
        scheduler:Register({ id = "test.z", interval = 1, priority = 1, onTick = function() order[#order + 1] = "z" end })
        scheduler:Register({ id = "test.b", interval = 1, priority = 5, onTick = function() order[#order + 1] = "b" end })
        scheduler:Register({ id = "test.a", interval = 1, priority = 5, onTick = function() order[#order + 1] = "a" end })
        scheduler:Tick(0)
        scheduler:Tick(1)
        eq(order[1], "a")
        eq(order[2], "b")
        eq(order[3], "z")
    end)

    it("enforces the per-tick execution budget and defers excess work", function()
        local scheduler = BH.Simulation.Scheduler.New({ maxExecutionsPerTick = 1 })
        local count = 0
        scheduler:Register({ id = "test.a", interval = 1, onTick = function() count = count + 1 end })
        scheduler:Register({ id = "test.b", interval = 1, onTick = function() count = count + 1 end })
        scheduler:Tick(0)
        local ok, stats = scheduler:Tick(1)
        truthy(ok)
        eq(stats.executed, 1)
        eq(stats.deferred, 1)
        eq(count, 1)
    end)

    it("isolates callback failures and does not retry in a tight loop", function()
        local scheduler = BH.Simulation.Scheduler.New()
        local good = 0
        local failedElapsed = {}
        scheduler:Register({ id = "test.bad", interval = 1, onTick = function(elapsed)
            failedElapsed[#failedElapsed + 1] = elapsed
            error("broken")
        end })
        scheduler:Register({ id = "test.good", interval = 1, onTick = function() good = good + 1 end })
        scheduler:Tick(0)
        local ok, stats = scheduler:Tick(1)
        truthy(ok)
        eq(stats.failed, 1)
        eq(good, 1)
        local status = scheduler:GetProcess("test.bad")
        eq(status.failures, 1)
        truthy(status.lastError)
        scheduler:Tick(1)
        eq(good, 1)
        scheduler:Tick(2)
        eq(failedElapsed[1], 1)
        eq(failedElapsed[2], 2)
    end)

    it("rejects duplicates, invalid definitions and re-entrant ticks", function()
        local scheduler = BH.Simulation.Scheduler.New()
        local ok = scheduler:Register({ id = "test.once", interval = 1, onTick = function()
            local nested, reason = scheduler:Tick(1)
            falsy(nested)
            contains(reason, "re-entrant")
        end })
        truthy(ok)
        local duplicate, reason = scheduler:Register({ id = "test.once", interval = 1, onTick = function() end })
        falsy(duplicate)
        contains(reason, "duplicate")
        falsy(scheduler:Register({ id = "bad id", interval = 1, onTick = function() end }))
        falsy(scheduler:Register({ id = "test.zero", interval = 0, onTick = function() end }))
        falsy(scheduler:Register({ id = "test.no_callback", interval = 1 }))
        scheduler:Tick(0)
        scheduler:Tick(1)
    end)

    it("releases the running guard after an unexpected scheduler-internal error", function()
        local scheduler = BH.Simulation.Scheduler.New()
        scheduler.processes = setmetatable({}, {
            __pairs = function() error("internal iteration failure") end,
        })
        local ok = scheduler:Tick(1)
        falsy(ok)
        falsy(scheduler.running)
        scheduler.processes = {}
        local recovered = scheduler:Tick(2)
        truthy(recovered)
    end)

    it("supports disable, enable and unregister", function()
        local scheduler = BH.Simulation.Scheduler.New()
        local calls = 0
        scheduler:Register({ id = "test.toggle", interval = 1, onTick = function() calls = calls + 1 end })
        scheduler:Tick(0)
        truthy(scheduler:SetEnabled("test.toggle", false))
        scheduler:Tick(2)
        eq(calls, 0)
        truthy(scheduler:SetEnabled("test.toggle", true))
        scheduler:Tick(3)
        eq(calls, 1)
        scheduler:Tick(4)
        eq(calls, 2)
        truthy(scheduler:Unregister("test.toggle"))
        falsy(scheduler:Unregister("test.toggle"))
        eq(scheduler:Count(), 0)
    end)
end)

describe("Simulation LOD", function()
    it("keeps important and observed entities at full detail", function()
        eq(BH.Simulation.LOD.Resolve({ distance = 500, threatened = true }), 0)
        eq(BH.Simulation.LOD.Resolve({ distance = 500, observed = true }), 0)
        eq(BH.Simulation.LOD.Resolve({ distance = 500, interacting = true }), 0)
    end)

    it("selects active, nearby, regional and global levels", function()
        local LOD = BH.Simulation.LOD
        eq(LOD.Resolve({ distance = 10 }), LOD.LEVEL_ACTIVE)
        eq(LOD.Resolve({ distance = 60 }), LOD.LEVEL_NEARBY)
        eq(LOD.Resolve({ distance = 250, regionLoaded = true }), LOD.LEVEL_REGIONAL)
        eq(LOD.Resolve({ distance = 250 }), LOD.LEVEL_GLOBAL)
    end)

    it("uses safe defaults for malformed distance and options", function()
        eq(BH.Simulation.LOD.Resolve({ distance = -1 }), 3)
        eq(BH.Simulation.LOD.Resolve({ distance = "close" }), 3)
        eq(BH.Simulation.LOD.Resolve({ distance = 50 }, { activeRadius = 100, nearbyRadius = 20 }), 0)
        eq(BH.Simulation.LOD.GetProfile(99), nil)
        truthy(BH.Simulation.LOD.IsValid(2))
        falsy(BH.Simulation.LOD.IsValid(2.5))
    end)
end)


describe("Dedicated server simulation runtime", function()
    it("processes all online players with elapsed game minutes", function()
        local players = {
            values = { "first", "second", "third" },
            size = function(self) return #self.values end,
            get = function(self, index) return self.values[index + 1] end,
        }
        local seen = {}
        local ok, stats = BH.Simulation.ServerRuntime.ProcessOnlinePlayers(
            players,
            0.5,
            function(player, minutes)
                seen[#seen + 1] = { player = player, minutes = minutes }
            end
        )
        truthy(ok)
        eq(stats.players, 3)
        eq(stats.processed, 3)
        eq(stats.failed, 0)
        eq(seen[1].player, "first")
        eq(seen[2].minutes, 30)
        eq(seen[3].player, "third")
    end)

    it("does not execute canonical player simulation from multiplayer client updates", function()
        local Player = BH.Integration.Player
        local oldIsServer, oldIsClient, oldIsMultiplayer = isServer, isClient, isMultiplayer
        local oldProcess = Player.ProcessSimulation
        local calls = 0
        Player.ProcessSimulation = function() calls = calls + 1 end
        isServer = function() return false end
        isClient = function() return true end
        isMultiplayer = function() return true end
        Player.OnUpdate({ getOnlineID = function() return 999 end })
        eq(calls, 0)
        Player.ProcessSimulation = oldProcess
        isServer, isClient, isMultiplayer = oldIsServer, oldIsClient, oldIsMultiplayer
    end)


    it("uses the local update path when the game explicitly reports single-player", function()
        local Player = BH.Integration.Player
        local oldIsServer, oldIsClient, oldIsMultiplayer = isServer, isClient, isMultiplayer
        local oldProcess = Player.ProcessSimulation
        local oldGetTime = BH.Persistence.GetGameTimeHours
        local player = { getOnlineID = function() return 1001 end }
        local key = Player.Key(player)
        local calls = 0

        isServer = function() return false end
        isClient = function() return false end
        isMultiplayer = function() return false end
        BH.Persistence.GetGameTimeHours = function() return 50 end
        Player.tickCounters[key] = (BH.Config.Get("tickInterval") or 30) - 1
        Player.lastTickAt[key] = nil
        Player.ProcessSimulation = function(_, minutes)
            calls = calls + 1
            eq(minutes, 0.5)
            return true
        end

        Player.OnUpdate(player)
        eq(calls, 1)

        Player.ProcessSimulation = oldProcess
        BH.Persistence.GetGameTimeHours = oldGetTime
        isServer, isClient, isMultiplayer = oldIsServer, oldIsClient, oldIsMultiplayer
        Player.tickCounters[key] = nil
        Player.lastTickAt[key] = nil
        Player.pendingSimulationMinutes[key] = nil
    end)

    it("isolates one player's processing failure", function()
        local players = {
            values = { "bad", "good" },
            size = function(self) return #self.values end,
            get = function(self, index) return self.values[index + 1] end,
        }
        local ok, stats = BH.Simulation.ServerRuntime.ProcessOnlinePlayers(
            players,
            1 / 60,
            function(player)
                if player == "bad" then error("simulated failure") end
            end
        )
        truthy(ok)
        eq(stats.processed, 1)
        eq(stats.failed, 1)
    end)


    it("bounds catch-up per player and carries remaining time forward", function()
        local players = {
            values = { "catchup-alpha" },
            size = function(self) return #self.values end,
            get = function(self, index)
                local name = self.values[index + 1]
                return { getOnlineID = function() return name end }
            end,
        }
        local steps = {}
        local ok, first = BH.Simulation.ServerRuntime.ProcessOnlinePlayers(
            players, 2, function(_, minutes) steps[#steps + 1] = minutes end, 30
        )
        truthy(ok)
        eq(first.processedMinutes, 30)
        eq(first.pendingMinutes, 90)
        eq(steps[1], 30)

        local okAgain, second = BH.Simulation.ServerRuntime.ProcessOnlinePlayers(
            players, 0.25, function(_, minutes) steps[#steps + 1] = minutes end, 30
        )
        truthy(okAgain)
        eq(second.processedMinutes, 30)
        eq(second.pendingMinutes, 75)
        eq(steps[2], 30)
        eq(BH.Simulation.ServerRuntime.GetPlayerDebt("id:catchup-alpha"), 75)
    end)

    it("retains only the failed player's debt and does not replay successful players", function()
        local players = {
            values = { "catchup-broken", "catchup-healthy" },
            size = function(self) return #self.values end,
            get = function(self, index)
                local name = self.values[index + 1]
                return { getOnlineID = function() return name end }
            end,
        }
        local healthyCalls = 0
        local ok, stats = BH.Simulation.ServerRuntime.ProcessOnlinePlayers(
            players, 0.5, function(player)
                if player:getOnlineID() == "catchup-broken" then
                    error("temporary failure")
                end
                healthyCalls = healthyCalls + 1
            end, 60
        )
        truthy(ok)
        eq(stats.failed, 1)
        eq(stats.processed, 1)
        eq(healthyCalls, 1)
        eq(BH.Simulation.ServerRuntime.GetPlayerDebt("id:catchup-broken"), 30)
        eq(BH.Simulation.ServerRuntime.GetPlayerDebt("id:catchup-healthy"), 0)
    end)

    it("rejects invalid elapsed time and invalid player collections", function()
        local ok = BH.Simulation.ServerRuntime.ProcessOnlinePlayers({}, 0)
        falsy(ok)
        ok = BH.Simulation.ServerRuntime.ProcessOnlinePlayers(nil, 1)
        falsy(ok)
        ok = BH.Simulation.ServerRuntime.ProcessOnlinePlayers({
            size = function() return "invalid" end,
        }, 1)
        falsy(ok)
    end)
end)

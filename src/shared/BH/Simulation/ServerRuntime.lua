-- Beautiful Humans / dedicated-server simulation runtime.
-- The server owns persistent character simulation. Client update events are
-- intentionally not used here: OnPlayerUpdate is a local-player event.

BH = BH or {}
BH.Simulation = BH.Simulation or {}

if BH.Simulation.ServerRuntime then
    return BH.Simulation.ServerRuntime
end

local Runtime = {
    _lifecycleRegistered = false,
    _started = false,
    _clock = nil,
    _tickCallback = nil,
    _clockErrorLogged = false,
}

local function isDedicatedServer()
    if type(isServer) ~= "function" then
        return false
    end
    local ok, result = pcall(isServer)
    return ok and result == true
end

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function listSize(players)
    local ok, count = pcall(function()
        return players:size()
    end)
    if not ok or not finite(count) or count < 0 then
        return nil
    end
    return math.floor(count)
end

-- Kept independently testable: the production adapter supplies getOnlinePlayers().
function Runtime.ProcessOnlinePlayers(players, elapsedHours, processor)
    if not finite(elapsedHours) or elapsedHours <= 0 then
        return false, "elapsed game time must be positive and finite"
    end
    if not players then
        return false, "online player collection is unavailable"
    end
    if type(processor) ~= "function" then
        processor = function(player, elapsedMinutes)
            local observer = BH.Integration and BH.Integration.Player
            if not observer or type(observer.OnServerSimulationTick) ~= "function" then
                error("server player simulation processor is unavailable")
            end
            return observer.OnServerSimulationTick(player, elapsedMinutes)
        end
    end

    local count = listSize(players)
    if count == nil then
        return false, "online player collection has no valid size()"
    end

    local elapsedMinutes = math.min(elapsedHours * 60, 1440)
    local stats = { players = count, processed = 0, failed = 0 }

    for index = 0, count - 1 do
        local ok, player = pcall(function()
            return players:get(index)
        end)
        if ok and player then
            local processOk, processError = pcall(processor, player, elapsedMinutes)
            if processOk then
                stats.processed = stats.processed + 1
            else
                stats.failed = stats.failed + 1
                if BH.Log then
                    BH.Log.Error("simulation", "Server player simulation failed", {
                        index = index,
                        error = tostring(processError),
                    })
                end
            end
        else
            stats.failed = stats.failed + 1
            if BH.Log then
                BH.Log.Warn("simulation", "Could not read online player", {
                    index = index,
                    error = tostring(player),
                })
            end
        end
    end

    return true, stats
end

function Runtime.OnTick()
    if not Runtime._started or not Runtime._clock then
        return
    end

    local now, _, clockError = Runtime._clock:Read()
    if now == nil then
        if not Runtime._clockErrorLogged and BH.Log then
            Runtime._clockErrorLogged = true
            BH.Log.Error("simulation", "Server game clock unavailable", tostring(clockError))
        end
        return
    end

    local scheduler = BH.Simulation and BH.Simulation.scheduler
    if not scheduler then
        return
    end

    local ok, result = scheduler:Tick(now)
    if not ok and BH.Log then
        BH.Log.Error("simulation", "Server scheduler tick rejected", tostring(result))
    end
end

function Runtime.Start()
    if Runtime._started then
        return true
    end
    if not isDedicatedServer() then
        return false, "not running in a dedicated server process"
    end
    if not Events or not Events.OnTick then
        return false, "server OnTick event is unavailable"
    end
    if not BH.Simulation or not BH.Simulation.Scheduler or not BH.Simulation.Clock then
        return false, "simulation foundation is not loaded"
    end

    local scheduler = BH.Simulation.scheduler or BH.Simulation.CreateScheduler()
    BH.Simulation.scheduler = scheduler

    local registered, registerError = scheduler:Register({
        id = "bh.server.players",
        interval = 1 / 60,
        priority = 100,
        onTick = function(elapsedHours)
            local ok, players = pcall(function()
                return getOnlinePlayers()
            end)
            if not ok or not players then
                if BH.Log then
                    BH.Log.Warn("simulation", "Could not obtain online players", tostring(players))
                end
                return
            end
            local processed, statsOrError = Runtime.ProcessOnlinePlayers(players, elapsedHours)
            if not processed and BH.Log then
                BH.Log.Error("simulation", "Online player processing rejected", tostring(statsOrError))
            end
        end,
    })

    if not registered and not scheduler:GetProcess("bh.server.players") then
        return false, registerError
    end

    local clock, clockError = BH.Simulation.CreateGameClock()
    if not clock then
        scheduler:Unregister("bh.server.players")
        return false, clockError
    end

    Runtime._clock = clock
    Runtime._clockErrorLogged = false
    Runtime._tickCallback = Runtime.OnTick
    local eventOk, eventError = pcall(function()
        Events.OnTick.Add(Runtime._tickCallback)
    end)
    if not eventOk then
        Runtime._clock = nil
        Runtime._tickCallback = nil
        scheduler:Unregister("bh.server.players")
        return false, "could not register server OnTick: " .. tostring(eventError)
    end

    Runtime._started = true
    if BH.Log then
        BH.Log.Info("simulation", "Dedicated-server simulation runtime started", {
            process = "bh.server.players",
            intervalMinutes = 1,
            schedulerLimit = scheduler.maxExecutionsPerTick,
        })
    end
    return true
end

function Runtime.RegisterLifecycle()
    if Runtime._lifecycleRegistered then
        return true
    end
    if not isDedicatedServer() then
        return false, "not running in a dedicated server process"
    end
    if not Events or not Events.OnServerStarted then
        return false, "OnServerStarted event is unavailable"
    end

    local ok, errorMessage = pcall(function()
        Events.OnServerStarted.Add(function()
            local started, startError = Runtime.Start()
            if not started and BH.Log then
                BH.Log.Error("simulation", "Dedicated-server runtime did not start", tostring(startError))
            end
        end)
    end)
    if not ok then
        return false, tostring(errorMessage)
    end

    Runtime._lifecycleRegistered = true
    return true
end

function Runtime.IsStarted()
    return Runtime._started
end

BH.Simulation.ServerRuntime = Runtime
return Runtime

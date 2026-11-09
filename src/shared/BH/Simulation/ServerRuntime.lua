-- Beautiful Humans / server-authoritative simulation runtime.
-- Dedicated и host/listen-server используют один серверный владелец состояния.
-- Multiplayer-клиенты не запускают каноническую симуляцию через OnPlayerUpdate.

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
    _playerDebtMinutes = {},
    _maxPlayerMinutesPerPass = 60,
}

local function isServerProcess()
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

local function playerKey(player, index)
    local observer = BH.Integration and BH.Integration.Player
    if observer and type(observer.Key) == "function" then
        local ok, key = pcall(observer.Key, player)
        if ok and type(key) == "string" and key ~= "" then
            return key
        end
    end
    return "online-index:" .. tostring(index)
end

-- Каждый игрок имеет собственный долг игрового времени. Успешная обработка
-- уменьшает только его долг; ошибка не заставляет повторять уже обработанных.
-- За один проход выполняется не более maxMinutesPerPass минут симуляции.
function Runtime.ProcessOnlinePlayers(players, elapsedHours, processor, maxMinutesPerPass)
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
            local ok, result = observer.OnServerSimulationTick(player, elapsedMinutes)
            if ok == false then
                error(result or "player simulation rejected")
            end
            return result
        end
    end

    local count = listSize(players)
    if count == nil then
        return false, "online player collection has no valid size()"
    end

    local chunkLimit = maxMinutesPerPass or Runtime._maxPlayerMinutesPerPass
    if not finite(chunkLimit) or chunkLimit <= 0 then
        return false, "catch-up chunk limit must be positive and finite"
    end

    local addedMinutes = elapsedHours * 60
    local stats = {
        players = count,
        processed = 0,
        failed = 0,
        deferred = 0,
        processedMinutes = 0,
        pendingMinutes = 0,
    }

    for index = 0, count - 1 do
        local readOk, player = pcall(function()
            return players:get(index)
        end)
        if not readOk or not player then
            stats.failed = stats.failed + 1
            if BH.Log then
                BH.Log.Warn("simulation", "Could not read online player", {
                    index = index,
                    error = tostring(player),
                })
            end
        else
            local key = playerKey(player, index)
            local debt = (Runtime._playerDebtMinutes[key] or 0) + addedMinutes
            local step = math.min(debt, chunkLimit)
            local processOk, processError = pcall(processor, player, step)
            if processOk then
                debt = math.max(0, debt - step)
                Runtime._playerDebtMinutes[key] = debt > 0.000001 and debt or nil
                stats.processed = stats.processed + 1
                stats.processedMinutes = stats.processedMinutes + step
                if debt > 0.000001 then
                    stats.deferred = stats.deferred + 1
                    stats.pendingMinutes = stats.pendingMinutes + debt
                end
            else
                Runtime._playerDebtMinutes[key] = debt
                stats.failed = stats.failed + 1
                stats.pendingMinutes = stats.pendingMinutes + debt
                if BH.Log then
                    BH.Log.Error("simulation", "Server player simulation failed; time debt retained", {
                        player = key,
                        error = tostring(processError),
                        pendingMinutes = debt,
                    })
                end
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
    if not isServerProcess() then
        return false, "not running in a server process"
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
                error("could not obtain online players: " .. tostring(players))
            end
            local processed, statsOrError = Runtime.ProcessOnlinePlayers(players, elapsedHours)
            if not processed then
                error(statsOrError)
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
        BH.Log.Info("simulation", "Server-authoritative simulation runtime started", {
            process = "bh.server.players",
            intervalMinutes = 1,
            catchUpChunkMinutes = Runtime._maxPlayerMinutesPerPass,
            schedulerLimit = scheduler.maxExecutionsPerTick,
        })
    end
    return true
end

function Runtime.RegisterLifecycle()
    if Runtime._lifecycleRegistered then
        return true
    end
    if not isServerProcess() then
        return false, "not running in a server process"
    end
    if not Events or not Events.OnServerStarted then
        return false, "OnServerStarted event is unavailable"
    end

    local ok, errorMessage = pcall(function()
        Events.OnServerStarted.Add(function()
            if BH.Start then
                BH.Start()
            end
            local started, startError = Runtime.Start()
            if not started and BH.Log then
                BH.Log.Error("simulation", "Server runtime did not start", tostring(startError))
            end
        end)
    end)
    if not ok then
        return false, tostring(errorMessage)
    end

    Runtime._lifecycleRegistered = true
    return true
end

function Runtime.GetPlayerDebt(key)
    return Runtime._playerDebtMinutes[key] or 0
end

function Runtime.IsStarted()
    return Runtime._started
end

BH.Simulation.ServerRuntime = Runtime
return Runtime

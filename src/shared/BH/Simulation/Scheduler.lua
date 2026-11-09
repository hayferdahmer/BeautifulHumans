-- Beautiful Humans / bounded simulation scheduler.
-- A delayed process runs once with its full elapsed game time. The scheduler
-- never performs an unbounded catch-up loop after pauses or time jumps.

BH = BH or {}
BH.Simulation = BH.Simulation or {}

if BH.Simulation.Scheduler then
    return BH.Simulation.Scheduler
end

local Scheduler = {}
Scheduler.__index = Scheduler

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function validId(value)
    return type(value) == "string"
        and #value >= 1
        and #value <= 96
        and string.match(value, "^[%w_%.%-]+$") ~= nil
end

local function sortedProcesses(processes)
    local result = {}
    for _, process in pairs(processes) do
        result[#result + 1] = process
    end
    table.sort(result, function(left, right)
        if left.priority ~= right.priority then
            return left.priority > right.priority
        end
        return left.id < right.id
    end)
    return result
end

function Scheduler.New(options)
    options = type(options) == "table" and options or {}
    local limit = options.maxExecutionsPerTick or 32
    if not isFinite(limit) or limit < 1 then
        limit = 32
    end
    limit = math.floor(limit)

    return setmetatable({
        processes = {},
        lastNow = nil,
        maxExecutionsPerTick = limit,
        running = false,
        totals = { executed = 0, failed = 0, deferred = 0 },
    }, Scheduler)
end

function Scheduler:Register(definition)
    if type(definition) ~= "table" then
        return false, "process definition must be a table"
    end
    if not validId(definition.id) then
        return false, "invalid process id"
    end
    if self.processes[definition.id] then
        return false, "duplicate process id: " .. definition.id
    end
    if not isFinite(definition.interval) or definition.interval <= 0 then
        return false, "process interval must be a positive finite number"
    end
    if type(definition.onTick) ~= "function" then
        return false, "process onTick callback is required"
    end

    local priority = definition.priority or 0
    if not isFinite(priority) then
        return false, "process priority must be finite"
    end

    local process = {
        id = definition.id,
        interval = definition.interval,
        priority = priority,
        enabled = definition.enabled ~= false,
        onTick = definition.onTick,
        lastRun = self.lastNow,
        nextRun = self.lastNow and (self.lastNow + definition.interval) or nil,
        executions = 0,
        failures = 0,
        lastError = nil,
    }
    self.processes[process.id] = process
    return true, process.id
end

function Scheduler:Unregister(id)
    if not self.processes[id] then
        return false
    end
    self.processes[id] = nil
    return true
end

function Scheduler:SetEnabled(id, enabled)
    local process = self.processes[id]
    if not process or type(enabled) ~= "boolean" then
        return false
    end
    process.enabled = enabled
    if enabled and self.lastNow ~= nil then
        process.lastRun = self.lastNow
        process.nextRun = self.lastNow + process.interval
    end
    return true
end

function Scheduler:GetProcess(id)
    local process = self.processes[id]
    if not process then
        return nil
    end
    return {
        id = process.id,
        interval = process.interval,
        priority = process.priority,
        enabled = process.enabled,
        executions = process.executions,
        failures = process.failures,
        lastError = process.lastError,
        lastRun = process.lastRun,
        nextRun = process.nextRun,
    }
end

function Scheduler:Count()
    local count = 0
    for _ in pairs(self.processes) do
        count = count + 1
    end
    return count
end

-- now and interval values use the same unit (the game clock currently exposes
-- world-age hours). A process receives elapsed, now and a read-only-like
-- metadata snapshot; it owns its own domain state.
function Scheduler:Tick(now, executionBudget)
    if not isFinite(now) then
        return false, "scheduler time must be finite"
    end
    if self.running then
        return false, "scheduler tick is re-entrant"
    end
    if self.lastNow ~= nil and now < self.lastNow then
        now = self.lastNow
    end

    local budget = executionBudget or self.maxExecutionsPerTick
    if not isFinite(budget) or budget < 1 then
        return false, "execution budget must be a positive finite number"
    end
    budget = math.floor(budget)

    self.running = true
    local stats = { executed = 0, failed = 0, deferred = 0, now = now }
    local ok, fatalError = xpcall(function()
        local ordered = sortedProcesses(self.processes)
        for index = 1, #ordered do
            local process = ordered[index]
            if self.processes[process.id] == process and process.enabled then
                if process.nextRun == nil then
                    process.lastRun = now
                    process.nextRun = now + process.interval
                elseif now >= process.nextRun then
                    if stats.executed >= budget then
                        stats.deferred = stats.deferred + 1
                    else
                        local elapsed = math.max(0, now - (process.lastRun or now))
                        process.lastRun = now
                        process.nextRun = now + process.interval
                        local callbackOk, errorMessage = pcall(process.onTick, elapsed, now, {
                            id = process.id,
                            interval = process.interval,
                            priority = process.priority,
                        })
                        stats.executed = stats.executed + 1
                        process.executions = process.executions + 1
                        if not callbackOk then
                            stats.failed = stats.failed + 1
                            process.failures = process.failures + 1
                            process.lastError = tostring(errorMessage)
                        else
                            process.lastError = nil
                        end
                    end
                end
            end
        end
        self.lastNow = now
    end, function(err)
        return tostring(err)
    end)

    -- Always release the re-entrancy guard, even if scheduler internals fail.
    self.running = false
    if not ok then
        return false, fatalError
    end

    self.totals.executed = self.totals.executed + stats.executed
    self.totals.failed = self.totals.failed + stats.failed
    self.totals.deferred = self.totals.deferred + stats.deferred
    return true, stats
end

function Scheduler:GetStats()
    return {
        registered = self:Count(),
        executed = self.totals.executed,
        failed = self.totals.failed,
        deferred = self.totals.deferred,
        lastNow = self.lastNow,
        maxExecutionsPerTick = self.maxExecutionsPerTick,
    }
end

function Scheduler:Reset()
    self.processes = {}
    self.lastNow = nil
    self.running = false
    self.totals = { executed = 0, failed = 0, deferred = 0 }
end

BH.Simulation.Scheduler = Scheduler
return Scheduler

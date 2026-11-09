-- Beautiful Humans / simulation clock.
-- The clock accepts an injected time source so domain code stays independent
-- from Project Zomboid globals and can be tested deterministically.

BH = BH or {}
BH.Simulation = BH.Simulation or {}

if BH.Simulation.Clock then
    return BH.Simulation.Clock
end

local Clock = {}
Clock.__index = Clock

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function Clock.New(source)
    if type(source) ~= "function" then
        return nil, "clock source must be a function"
    end
    return setmetatable({
        source = source,
        last = nil,
        current = nil,
    }, Clock)
end

-- Returns current time and elapsed time since the previous successful read.
-- A backwards-moving source is clamped, preventing negative simulation time.
function Clock:Read()
    local ok, value = pcall(self.source)
    if not ok then
        return nil, 0, "clock source failed: " .. tostring(value)
    end
    if not isFinite(value) then
        return nil, 0, "clock source returned a non-finite value"
    end

    if self.last ~= nil and value < self.last then
        value = self.last
    end

    local elapsed = 0
    if self.last ~= nil then
        elapsed = value - self.last
    end

    self.last = value
    self.current = value
    return value, elapsed
end

function Clock:GetCurrent()
    return self.current
end

function Clock:Reset(value)
    if value ~= nil and not isFinite(value) then
        return false, "initial time must be a finite number"
    end
    self.last = value
    self.current = value
    return true
end

BH.Simulation.Clock = Clock
return Clock

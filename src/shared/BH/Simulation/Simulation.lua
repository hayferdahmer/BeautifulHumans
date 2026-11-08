-- Beautiful Humans / simulation foundation facade.
-- This module exposes pure services; game event scheduling is deliberately
-- not wired until the exact Build 42 server tick contract is verified.

BH = BH or {}
BH.Simulation = BH.Simulation or {}

if BH.Simulation._loaded then
    return BH.Simulation
end

require "BH/Simulation/Clock"
require "BH/Simulation/Scheduler"
require "BH/Simulation/LOD"

local Simulation = BH.Simulation
Simulation._loaded = true

function Simulation.CreateClock(source)
    return Simulation.Clock.New(source)
end

function Simulation.CreateGameClock()
    local function readWorldAgeHours()
        if not getGameTime then
            error("Project Zomboid game time is unavailable")
        end
        local gameTime = getGameTime()
        if not gameTime then
            error("Project Zomboid game time is unavailable")
        end
        return gameTime:getWorldAgeHours()
    end
    return Simulation.Clock.New(readWorldAgeHours)
end

function Simulation.CreateScheduler(options)
    return Simulation.Scheduler.New(options)
end

BH.RegisterModule({
    id = "bh.simulation",
    version = BH.VERSION,
    requires = { "bh.core" },
    description = "Game-time clock, bounded process scheduler and simulation LOD policy",
    init = function(context)
        Simulation.scheduler = Simulation.scheduler or Simulation.CreateScheduler()
        context.log.Info("simulation", "Simulation foundation ready", {
            schedulerLimit = Simulation.scheduler.maxExecutionsPerTick,
            lodLevels = 4,
        })
    end,
})

return Simulation

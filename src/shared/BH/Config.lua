-- Beautiful Humans / configuration.
-- Values are deliberately plain data so they can be validated and persisted.

BH = BH or {}

if BH.Config then
    return
end

local Config = {
    defaults = {
        enabled = true,
        debug = false,
        tickInterval = 30,
        maxInjuries = 64,
        maxInjuriesPerZone = 8,
        maxProcessedRequests = 32,
        injuryHistoryLimit = 0,
        bleedingClotPerMinute = 1.0,
        bleedingBandageDecayPerMinute = 8.0,
        contaminationDecayPerMinute = 1.5,
        infectionThreshold = 55.0,
        infectionGrowthPerMinute = 0.12,
        healingRateMultiplier = 1.0,
        treatmentItemCheck = true,
    },
    values = {},
    loaded = false,
}
BH.Config = Config

local validators = {
    enabled = function(value) return type(value) == "boolean" end,
    debug = function(value) return type(value) == "boolean" end,
    tickInterval = function(value) return type(value) == "number" and value >= 1 and value <= 600 end,
    maxInjuries = function(value) return type(value) == "number" and value >= 8 and value <= 512 end,
    maxInjuriesPerZone = function(value) return type(value) == "number" and value >= 1 and value <= 32 end,
    maxProcessedRequests = function(value) return type(value) == "number" and value >= 1 and value <= 256 end,
    injuryHistoryLimit = function(value) return type(value) == "number" and value >= 0 and value <= 64 end,
    bleedingClotPerMinute = function(value) return type(value) == "number" and value >= 0 and value <= 100 end,
    bleedingBandageDecayPerMinute = function(value) return type(value) == "number" and value >= 0 and value <= 100 end,
    contaminationDecayPerMinute = function(value) return type(value) == "number" and value >= 0 and value <= 100 end,
    infectionThreshold = function(value) return type(value) == "number" and value >= 0 and value <= 100 end,
    infectionGrowthPerMinute = function(value) return type(value) == "number" and value >= 0 and value <= 100 end,
    healingRateMultiplier = function(value) return type(value) == "number" and value >= 0 and value <= 10 end,
    treatmentItemCheck = function(value) return type(value) == "boolean" end,
}

local function applyDefaults()
    Config.values = {}
    for key, value in pairs(Config.defaults) do
        Config.values[key] = value
    end
end

function Config.Reset(overrides)
    applyDefaults()
    Config.loaded = true
    if type(overrides) == "table" then
        Config.Load(overrides)
    end
    return Config.values
end

function Config.Load(overrides)
    if type(overrides) ~= "table" then
        return false, "configuration must be a table"
    end
    for key, value in pairs(overrides) do
        local validator = validators[key]
        if validator and validator(value) then
            Config.values[key] = value
        elseif validators[key] then
            if BH.Log then
                BH.Log.Warn("config", "Rejected invalid value", { key = key, value = value })
            end
        end
    end
    return true
end

function Config.Get(key)
    if Config.values[key] ~= nil then
        return Config.values[key]
    end
    return Config.defaults[key]
end

function Config.Set(key, value)
    local validator = validators[key]
    if not validator then
        return false, "unknown configuration key"
    end
    if not validator(value) then
        return false, "invalid value"
    end
    Config.values[key] = value
    return true
end

function Config.GetSnapshot()
    local snapshot = {}
    for key, value in pairs(Config.values) do
        snapshot[key] = value
    end
    return snapshot
end

Config.Reset()

return Config

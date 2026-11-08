-- Beautiful Humans / simulation level-of-detail policy.
-- LOD is a policy decision only; it does not spawn, despawn or mutate entities.

BH = BH or {}
BH.Simulation = BH.Simulation or {}

if BH.Simulation.LOD then
    return BH.Simulation.LOD
end

local LOD = {}

LOD.LEVEL_ACTIVE = 0
LOD.LEVEL_NEARBY = 1
LOD.LEVEL_REGIONAL = 2
LOD.LEVEL_GLOBAL = 3

local profiles = {
    [0] = { name = "active", detail = "full", updateMultiplier = 1 },
    [1] = { name = "nearby", detail = "reduced", updateMultiplier = 4 },
    [2] = { name = "regional", detail = "aggregated", updateMultiplier = 20 },
    [3] = { name = "global", detail = "strategic", updateMultiplier = 100 },
}

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function LOD.Resolve(context, options)
    context = type(context) == "table" and context or {}
    options = type(options) == "table" and options or {}

    if context.forceActive == true
        or context.critical == true
        or context.interacting == true
        or context.threatened == true
        or context.observed == true then
        return LOD.LEVEL_ACTIVE
    end

    local distance = context.distance
    if not finite(distance) or distance < 0 then
        return LOD.LEVEL_GLOBAL
    end

    local activeRadius = options.activeRadius or 30
    local nearbyRadius = options.nearbyRadius or 100
    if not finite(activeRadius) or activeRadius < 0 then
        activeRadius = 30
    end
    if not finite(nearbyRadius) or nearbyRadius < activeRadius then
        nearbyRadius = math.max(100, activeRadius)
    end

    if distance <= activeRadius then
        return LOD.LEVEL_ACTIVE
    end
    if distance <= nearbyRadius then
        return LOD.LEVEL_NEARBY
    end
    if context.regionLoaded == true or context.regionRelevant == true then
        return LOD.LEVEL_REGIONAL
    end
    return LOD.LEVEL_GLOBAL
end

function LOD.GetProfile(level)
    local profile = profiles[level]
    if not profile then
        return nil
    end
    return {
        level = level,
        name = profile.name,
        detail = profile.detail,
        updateMultiplier = profile.updateMultiplier,
    }
end

function LOD.IsValid(level)
    return finite(level) and level == math.floor(level) and profiles[level] ~= nil
end

return LOD

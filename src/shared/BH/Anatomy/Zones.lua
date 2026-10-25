-- Beautiful Humans / anatomical zones.
-- The logical model maps one-to-one onto the 17 BodyPartType entries exposed by
-- Build 42. The engine index is resolved at runtime; fallback indices are kept
-- only so pure-Lua tests can run without the game.

BH = BH or {}

if BH.Anatomy and BH.Anatomy.Zones then
    return
end

require "BH/Core"

BH.Anatomy = BH.Anatomy or {}

local Zones = {
    list = {},
    byId = {},
    byEngineIndex = {},
}
BH.Anatomy.Zones = Zones

local definitions = {
    { id = "left_hand",      engine = "Left_Hand",      fallback = 0,  group = "left_arm",  label = "Left hand",      functions = { "manipulation" } },
    { id = "right_hand",     engine = "Right_Hand",     fallback = 1,  group = "right_arm", label = "Right hand",     functions = { "manipulation" } },
    { id = "left_forearm",   engine = "Left_Forearm",   fallback = 2,  group = "left_arm",  label = "Left forearm",   functions = { "manipulation" } },
    { id = "right_forearm",  engine = "Right_Forearm",  fallback = 3,  group = "right_arm", label = "Right forearm",  functions = { "manipulation" } },
    { id = "left_upper_arm", engine = "Left_UpperArm",  fallback = 4,  group = "left_arm",  label = "Left upper arm", functions = { "manipulation" } },
    { id = "right_upper_arm",engine = "Right_UpperArm", fallback = 5,  group = "right_arm", label = "Right upper arm",functions = { "manipulation" } },
    { id = "chest",          engine = "Torso_Upper",    fallback = 6,  group = "torso",     label = "Chest",          functions = { "respiration" }, vital = true },
    { id = "abdomen",        engine = "Torso_Lower",    fallback = 7,  group = "torso",     label = "Abdomen",        functions = { "mobility" }, vital = true },
    { id = "head",           engine = "Head",           fallback = 8,  group = "head",      label = "Head",           functions = { "consciousness" }, vital = true },
    { id = "neck",           engine = "Neck",           fallback = 9,  group = "head",      label = "Neck",           functions = { "consciousness", "respiration" }, vital = true },
    { id = "groin",          engine = "Groin",          fallback = 10, group = "torso",     label = "Groin",          functions = { "mobility" }, vital = true },
    { id = "left_thigh",     engine = "Left_Thigh",     fallback = 11, group = "left_leg",  label = "Left thigh",     functions = { "mobility" } },
    { id = "right_thigh",    engine = "Right_Thigh",    fallback = 12, group = "right_leg", label = "Right thigh",    functions = { "mobility" } },
    { id = "left_shin",      engine = "Left_Shin",      fallback = 13, group = "left_leg",  label = "Left shin",      functions = { "mobility" } },
    { id = "right_shin",     engine = "Right_Shin",     fallback = 14, group = "right_leg", label = "Right shin",     functions = { "mobility" } },
    { id = "left_foot",      engine = "Left_Foot",      fallback = 15, group = "left_leg",  label = "Left foot",      functions = { "mobility", "balance" } },
    { id = "right_foot",     engine = "Right_Foot",     fallback = 16, group = "right_leg", label = "Right foot",     functions = { "mobility", "balance" } },
}

local function addZone(definition)
    local zone = {
        id = definition.id,
        engine = definition.engine,
        fallback = definition.fallback,
        engineIndex = definition.fallback,
        group = definition.group,
        label = definition.label,
        functions = definition.functions or {},
        vital = definition.vital == true,
    }
    Zones.list[#Zones.list + 1] = zone
    Zones.byId[zone.id] = zone
end

for index = 1, #definitions do
    addZone(definitions[index])
end

function Zones.Get(zoneId)
    return Zones.byId[zoneId]
end

function Zones.GetAll()
    return Zones.list
end

function Zones.GetGroup(zoneId)
    local zone = Zones.byId[zoneId]
    return zone and zone.group or nil
end

function Zones.IsVital(zoneId)
    local zone = Zones.byId[zoneId]
    return zone and zone.vital == true
end

function Zones.HasFunction(zoneId, functionName)
    local zone = Zones.byId[zoneId]
    if not zone then
        return false
    end
    for index = 1, #zone.functions do
        if zone.functions[index] == functionName then
            return true
        end
    end
    return false
end

function Zones.ResolveEngineIndices()
    if not BodyPartType or not BodyPartType.ToIndex then
        return false
    end

    Zones.byEngineIndex = {}
    for index = 1, #Zones.list do
        local zone = Zones.list[index]
        local enumValue = BodyPartType[zone.engine]
        if enumValue ~= nil then
            local ok, engineIndex = pcall(function()
                return BodyPartType.ToIndex(enumValue)
            end)
            if ok and BH.Util.IsInteger(engineIndex) then
                zone.engineIndex = engineIndex
            end
        end
        if zone.engineIndex ~= nil then
            Zones.byEngineIndex[zone.engineIndex] = zone
        end
    end
    return true
end

function Zones.GetByEngineIndex(index)
    return Zones.byEngineIndex[index]
end

function Zones.Count()
    return #Zones.list
end

-- Populate the fallback index map immediately. ResolveEngineIndices() replaces
-- it with the game's authoritative values when BodyPartType is available.
for index = 1, #Zones.list do
    local zone = Zones.list[index]
    Zones.byEngineIndex[zone.engineIndex] = zone
end

return Zones

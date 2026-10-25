-- Beautiful Humans / treatment catalogue.
-- Definitions are data. Medical.lua owns validation and state changes.

BH = BH or {}

if BH.Medical and BH.Medical.Treatments then
    return
end

require "BH/Core"

BH.Medical = BH.Medical or {}

local Treatments = {
    order = { "examine", "clean", "bandage", "splint", "stitch", "remove_bandage" },
    definitions = {},
}
BH.Medical.Treatments = Treatments

local function define(definition)
    Treatments.definitions[definition.id] = definition
end

define({
    id = "examine",
    label = "Examine",
    duration = 20,
    requirements = {},
    validKinds = nil,
    description = "Assess the wound and reveal its current condition.",
})

define({
    id = "clean",
    label = "Clean wound",
    duration = 80,
    requirements = {
        { any = { "Disinfectant", "Alcohol", "AlcoholWipe", "Water" }, consume = false, label = "cleaning supply" },
    },
    validKinds = {
        abrasion = true, bite = true, cut = true, deep_wound = true,
        puncture = true, burn = true,
    },
    description = "Reduce contamination before bandaging.",
})

define({
    id = "bandage",
    label = "Bandage",
    duration = 120,
    requirements = {
        { any = { "Bandage", "RagBandage", "BandageDirty" }, consume = true, label = "bandage" },
    },
    validKinds = {
        abrasion = true, bite = true, cut = true, deep_wound = true,
        puncture = true, burn = true, fracture = true,
    },
    description = "Stop bleeding and protect the wound.",
})

define({
    id = "splint",
    label = "Splint",
    duration = 180,
    requirements = {
        { any = { "Splint", "Stick", "Plank" }, consume = true, label = "splint material" },
        { any = { "Bandage", "RagBandage" }, consume = true, label = "binding" },
    },
    validKinds = {
        fracture = true, sprain = true,
    },
    description = "Immobilise a fracture or severe sprain.",
})

define({
    id = "stitch",
    label = "Stitch wound",
    duration = 240,
    requirements = {
        { any = { "Needle", "SutureNeedle" }, consume = false, label = "needle" },
        { any = { "Thread", "SutureThread" }, consume = true, label = "thread" },
    },
    validKinds = {
        cut = true, deep_wound = true,
    },
    description = "Close a deep wound to reduce bleeding and speed healing.",
})

define({
    id = "remove_bandage",
    label = "Remove bandage",
    duration = 60,
    requirements = {},
    validKinds = nil,
    description = "Remove the current bandage.",
})

function Treatments.Get(actionId)
    return Treatments.definitions[actionId]
end

function Treatments.GetAll()
    return Treatments.order
end

return Treatments

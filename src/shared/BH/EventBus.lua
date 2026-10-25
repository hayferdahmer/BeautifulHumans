-- Beautiful Humans / internal event bus.
-- This is not the Project Zomboid Events table. It carries plain-data
-- notifications between BH modules and never keeps game object references.

BH = BH or {}

if BH.Events then
    return
end

local EventBus = {
    subscribers = {},
    sequence = 0,
    active = {},
    depth = 0,
    budget = 0,
    maxDepth = 16,
    maxDispatch = 2000,
}
BH.Events = EventBus

EventBus.Names = {
    CORE_BOOTED = "Core.Booted",
    CORE_STARTED = "Core.Started",
    CORE_MODULE_FAILED = "Core.ModuleFailed",

    CHARACTER_INJURY_CREATED = "Character.InjuryCreated",
    CHARACTER_INJURY_HEALED = "Character.InjuryHealed",
    CHARACTER_BLEEDING_CHANGED = "Character.BleedingChanged",
    CHARACTER_TREATMENT_APPLIED = "Character.TreatmentApplied",
    CHARACTER_PHYSIOLOGY_CHANGED = "Character.PhysiologyChanged",

    ZOMBIE_FUNCTION_CHANGED = "Zombie.FunctionChanged",
    ITEM_CONDITION_CHANGED = "Item.ConditionChanged",
}

local function validName(name)
    return type(name) == "string" and string.match(name, "^[A-Za-z0-9_%.%-]+$") ~= nil
end

local function sortSubscribers(list)
    table.sort(list, function(left, right)
        if left.priority == right.priority then
            return left.id < right.id
        end
        return left.priority > right.priority
    end)
end

function EventBus.On(name, callback, priority)
    if not validName(name) then
        return nil, "invalid event name"
    end
    if type(callback) ~= "function" then
        return nil, "callback must be a function"
    end
    if not BH.Util.IsFiniteNumber(priority) then
        priority = 0
    end

    EventBus.sequence = EventBus.sequence + 1
    local token = {
        id = EventBus.sequence,
        name = name,
        callback = callback,
        priority = priority,
        active = true,
    }

    local list = EventBus.subscribers[name]
    if not list then
        list = {}
        EventBus.subscribers[name] = list
    end
    list[#list + 1] = token
    sortSubscribers(list)

    return token
end

function EventBus.Off(tokenOrName, callback)
    local removed = 0

    if type(tokenOrName) == "table" then
        local token = tokenOrName
        local list = EventBus.subscribers[token.name]
        if not list then
            return 0
        end
        for index = #list, 1, -1 do
            if list[index] == token or list[index].id == token.id then
                list[index].active = false
                table.remove(list, index)
                removed = removed + 1
            end
        end
    elseif validName(tokenOrName) and type(callback) == "function" then
        local list = EventBus.subscribers[tokenOrName]
        if not list then
            return 0
        end
        for index = #list, 1, -1 do
            if list[index].callback == callback then
                list[index].active = false
                table.remove(list, index)
                removed = removed + 1
            end
        end
    end

    return removed
end

function EventBus.Emit(name, payload)
    if not validName(name) then
        return 0
    end

    local list = EventBus.subscribers[name]
    if not list or #list == 0 then
        return 0
    end

    if EventBus.active[name] then
        if BH.Log then
            BH.Log.Warn("events", "Blocked re-entrant event", { event = name })
        end
        return 0
    end

    if EventBus.depth >= EventBus.maxDepth then
        if BH.Log then
            BH.Log.Error("events", "Maximum event depth exceeded", { event = name, depth = EventBus.depth })
        end
        return 0
    end

    if EventBus.depth == 0 then
        EventBus.budget = EventBus.maxDispatch
    end

    EventBus.active[name] = true
    EventBus.depth = EventBus.depth + 1

    local snapshot = {}
    for index = 1, #list do
        snapshot[index] = list[index]
    end

    local delivered = 0
    for index = 1, #snapshot do
        local token = snapshot[index]
        if EventBus.budget <= 0 then
            if BH.Log then
                BH.Log.Error("events", "Dispatch budget exhausted", { event = name })
            end
            break
        end
        EventBus.budget = EventBus.budget - 1
        if token.active then
            local ok, errorMessage = pcall(token.callback, payload)
            if ok then
                delivered = delivered + 1
            elseif BH.Log then
                BH.Log.Error("events", "Subscriber failed", {
                    event = name,
                    subscriber = token.id,
                    error = tostring(errorMessage),
                })
            end
        end
    end

    EventBus.depth = EventBus.depth - 1
    EventBus.active[name] = nil

    return delivered
end

function EventBus.Clear()
    EventBus.subscribers = {}
    EventBus.active = {}
    EventBus.depth = 0
    EventBus.budget = 0
    EventBus.sequence = 0
end

return EventBus

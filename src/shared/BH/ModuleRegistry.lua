-- Beautiful Humans / module registry and dependency resolution.
-- Modules are declared once, resolved in dependency order, and initialised with
-- isolation: one failing module must not prevent unrelated modules from loading.

BH = BH or {}

if BH.Modules then
    return
end

local Modules = {
    defs = {},
    order = nil,
    results = {},
    lastReport = nil,
}
BH.Modules = Modules

local function validId(id)
    return type(id) == "string"
        and #id >= 3
        and #id <= 64
        and string.match(id, "^[a-z0-9_%.%-]+$") ~= nil
end

local function sortedKeys(value)
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

function Modules.Register(definition)
    if type(definition) ~= "table" then
        return false, "module definition must be a table"
    end
    if not validId(definition.id) then
        return false, "invalid module id"
    end
    if type(definition.version) ~= "string" or definition.version == "" then
        return false, "module version is required"
    end
    if type(definition.init) ~= "function" then
        return false, "module init must be a function"
    end
    if Modules.defs[definition.id] then
        return false, "duplicate module id: " .. definition.id
    end

    local requires = definition.requires or {}
    local optional = definition.optional or {}
    if type(requires) ~= "table" or type(optional) ~= "table" then
        return false, "module dependency lists must be tables"
    end

    local normalizedRequires = {}
    for index = 1, #requires do
        local dependency = requires[index]
        if not validId(dependency) then
            return false, "invalid dependency id in " .. definition.id
        end
        normalizedRequires[#normalizedRequires + 1] = dependency
    end

    local normalizedOptional = {}
    for index = 1, #optional do
        local dependency = optional[index]
        if not validId(dependency) then
            return false, "invalid optional dependency id in " .. definition.id
        end
        normalizedOptional[#normalizedOptional + 1] = dependency
    end

    Modules.defs[definition.id] = {
        id = definition.id,
        version = definition.version,
        requires = normalizedRequires,
        optional = normalizedOptional,
        init = definition.init,
        description = definition.description,
    }
    Modules.order = nil
    return true
end

function Modules.Get(id)
    return Modules.defs[id]
end

function Modules.Resolve()
    local state = {}
    local stack = {}
    local stackIndex = {}
    local order = {}
    local blocked = {}
    local missing = {}
    local cycles = {}

    local function markCycle(cycleStart)
        local names = {}
        for index = cycleStart, #stack do
            blocked[stack[index]] = true
            names[#names + 1] = stack[index]
        end
        cycles[#cycles + 1] = table.concat(names, " -> ")
    end

    local function visit(id)
        if state[id] == 2 then
            return not blocked[id]
        end
        if state[id] == 1 then
            markCycle(stackIndex[id] or 1)
            return false
        end

        local definition = Modules.defs[id]
        if not definition then
            missing[id] = true
            blocked[id] = true
            return false
        end

        state[id] = 1
        stack[#stack + 1] = id
        stackIndex[id] = #stack

        local healthy = true
        for index = 1, #definition.requires do
            local dependency = definition.requires[index]
            if not Modules.defs[dependency] then
                missing[dependency] = true
                blocked[id] = true
                healthy = false
            elseif not visit(dependency) then
                blocked[id] = true
                healthy = false
            end
        end

        for index = 1, #definition.optional do
            local dependency = definition.optional[index]
            if Modules.defs[dependency] then
                -- An optional module failure must not block its consumer.
                visit(dependency)
            end
        end

        stack[#stack] = nil
        stackIndex[id] = nil
        state[id] = 2

        if healthy and not blocked[id] then
            order[#order + 1] = id
        end
        return healthy and not blocked[id]
    end

    local ids = sortedKeys(Modules.defs)
    for index = 1, #ids do
        visit(ids[index])
    end

    local report = {
        order = order,
        missing = missing,
        cycles = cycles,
        blocked = blocked,
    }
    Modules.order = order
    Modules.lastReport = report
    return order, report
end

function Modules.InitAll(context)
    local order, report = Modules.Resolve()
    local failed = {}
    local results = {}

    for index = 1, #order do
        local id = order[index]
        local definition = Modules.defs[id]
        local dependencyFailed = false
        local failedDependencies = {}

        for dependencyIndex = 1, #definition.requires do
            local dependency = definition.requires[dependencyIndex]
            if failed[dependency] then
                dependencyFailed = true
                failedDependencies[#failedDependencies + 1] = dependency
            end
        end

        if dependencyFailed then
            failed[id] = true
            results[id] = {
                status = "skipped",
                error = "dependency failed: " .. table.concat(failedDependencies, ", "),
            }
            if BH.Log then
                BH.Log.Error("modules", "Module skipped after dependency failure", {
                    module = id,
                    dependencies = failedDependencies,
                })
            end
        else
            local ok, errorMessage = pcall(definition.init, context)
            if ok then
                results[id] = { status = "ready" }
            else
                failed[id] = true
                results[id] = { status = "failed", error = tostring(errorMessage) }
                if BH.Log then
                    BH.Log.Error("modules", "Module initialisation failed", {
                        module = id,
                        error = tostring(errorMessage),
                    })
                end
                if BH.Events then
                    BH.Events.Emit(BH.Events.Names.CORE_MODULE_FAILED, {
                        module = id,
                        error = tostring(errorMessage),
                    })
                end
            end
        end
    end

    Modules.results = results
    return results, report
end

function Modules.Reset()
    Modules.defs = {}
    Modules.order = nil
    Modules.results = {}
    Modules.lastReport = nil
end

function Modules.GetStatus(id)
    local result = Modules.results[id]
    if result then
        return result.status, result.error
    end
    if Modules.defs[id] then
        return "registered"
    end
    return "unknown"
end

return Modules

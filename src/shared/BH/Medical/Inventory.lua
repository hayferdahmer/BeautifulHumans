-- Beautiful Humans / server-side inventory adapter.
-- Maps the treatment catalogue's stable aliases to Project Zomboid item types.
-- All item lookup and consumption happens on the authoritative server.

BH = BH or {}

if BH.Medical and BH.Medical.Inventory then
    return
end

require "BH/Core"
require "BH/Medical/Treatments"

BH.Medical = BH.Medical or {}

local Inventory = {}
BH.Medical.Inventory = Inventory

local itemTypes = {
    Bandage = { "Base.Bandage" },
    RagBandage = { "Base.RippedSheets", "Base.RippedSheetsDirty" },
    BandageDirty = { "Base.BandageDirty" },
    Disinfectant = { "Base.Disinfectant" },
    Alcohol = { "Base.Alcohol" },
    AlcoholWipe = { "Base.AlcoholWipes" },
    Water = { "Base.Water" },
    Splint = { "Base.Splint" },
    Stick = { "Base.Stick" },
    Plank = { "Base.Plank" },
    Needle = { "Base.Needle" },
    SutureNeedle = { "Base.SutureNeedle" },
    Thread = { "Base.Thread" },
    SutureThread = { "Base.SutureThread" },
}

local function fullType(item)
    if not item then
        return nil
    end
    local ok, value = pcall(function()
        return item:getFullType()
    end)
    if ok and type(value) == "string" then
        return value
    end
    return nil
end

local function getItems(container)
    if not container then
        return nil, "inventory unavailable"
    end
    local ok, items = pcall(function()
        return container:getItems()
    end)
    if not ok or not items then
        return nil, "inventory item list unavailable"
    end

    local sizeOk, size = pcall(function()
        return items:size()
    end)
    if not sizeOk or type(size) ~= "number" then
        return nil, "inventory item list is unsupported"
    end

    local result = {}
    for index = 0, size - 1 do
        local itemOk, item = pcall(function()
            return items:get(index)
        end)
        if itemOk and item then
            result[#result + 1] = item
        end
    end
    return result
end

local function matches(item, alias)
    local actual = fullType(item)
    local expected = itemTypes[alias]
    if not actual or not expected then
        return false
    end
    for index = 1, #expected do
        if actual == expected[index] then
            return true
        end
    end
    return false
end

function Inventory.Resolve(container, requirements)
    local items, reason = getItems(container)
    if not items then
        return nil, reason
    end

    local selected = {}
    local selectedSet = {}
    local function find(alias)
        for index = 1, #items do
            local item = items[index]
            if not selectedSet[item] and matches(item, alias) then
                return item
            end
        end
        return nil
    end

    for requirementIndex = 1, #(requirements or {}) do
        local requirement = requirements[requirementIndex]
        local found = nil
        for aliasIndex = 1, #(requirement.any or {}) do
            found = find(requirement.any[aliasIndex])
            if found then
                break
            end
        end
        if not found then
            return nil, "missing " .. tostring(requirement.label or "item")
        end
        selected[#selected + 1] = {
            item = found,
            consume = requirement.consume == true,
        }
        selectedSet[found] = true
    end

    return selected
end

function Inventory.Consume(container, resolved)
    if not container then
        return false, "inventory unavailable"
    end
    local removed = {}
    for index = 1, #(resolved or {}) do
        local entry = resolved[index]
        if entry.consume then
            local item = entry.item
            local actual = fullType(item)
            if not actual then
                return false, "treatment item became invalid"
            end
            local ok, err = pcall(function()
                container:Remove(item)
            end)
            if not ok then
                -- Restore items already removed if the container API throws.
                for restoreIndex = #removed, 1, -1 do
                    pcall(function()
                        container:AddItem(removed[restoreIndex])
                    end)
                end
                return false, tostring(err)
            end
            removed[#removed + 1] = actual
        end
    end
    return true
end

function Inventory.Restore(container, resolved)
    if not container then
        return false
    end
    local ok = true
    for index = 1, #(resolved or {}) do
        local entry = resolved[index]
        if entry.consume then
            local actual = fullType(entry.item)
            if actual then
                local restored = pcall(function()
                    container:AddItem(actual)
                end)
                ok = ok and restored
            end
        end
    end
    return ok
end

function Inventory.HasAlias(container, alias)
    local items = getItems(container)
    if not items then
        return false
    end
    for index = 1, #items do
        if matches(items[index], alias) then
            return true
        end
    end
    return false
end

return Inventory

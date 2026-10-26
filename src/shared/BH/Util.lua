-- Beautiful Humans / shared utilities.
-- Target runtime: Project Zomboid Build 42 (Kahlua, Lua 5.1 subset).
-- This file must not touch game objects or the filesystem.

BH = BH or {}

if BH.Util then
    return
end

local Util = {}
BH.Util = Util

local math_huge = math.huge

function Util.IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math_huge
        and value ~= -math_huge
end

function Util.IsInteger(value)
    return Util.IsFiniteNumber(value) and value == math.floor(value)
end

function Util.Clamp(value, minimum, maximum)
    if not Util.IsFiniteNumber(value) then
        return minimum
    end
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

function Util.ClampInt(value, minimum, maximum)
    return math.floor(Util.Clamp(value, minimum, maximum) + 0.5)
end

function Util.ToNumber(value, fallback)
    if Util.IsFiniteNumber(value) then
        return value
    end
    return fallback
end

function Util.Round(value, digits)
    local factor = 10 ^ (digits or 0)
    return math.floor(value * factor + 0.5) / factor
end

function Util.DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[Util.DeepCopy(key, seen)] = Util.DeepCopy(item, seen)
    end
    return copy
end

function Util.ShallowCopy(value)
    local copy = {}
    if type(value) == "table" then
        for key, item in pairs(value) do
            copy[key] = item
        end
    end
    return copy
end

function Util.SortedKeys(value)
    local keys = {}
    if type(value) == "table" then
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

function Util.TableCount(value)
    local count = 0
    if type(value) == "table" then
        for _ in pairs(value) do
            count = count + 1
        end
    end
    return count
end

function Util.StartsWith(value, prefix)
    return type(value) == "string"
        and type(prefix) == "string"
        and string.sub(value, 1, #prefix) == prefix
end

function Util.Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

function Util.Join(separator, values)
    if type(values) ~= "table" then
        return ""
    end
    local parts = {}
    for index = 1, #values do
        parts[#parts + 1] = tostring(values[index])
    end
    return table.concat(parts, separator or ", ")
end

function Util.SafeCall(callback, ...)
    if type(callback) ~= "function" then
        return false, "not a function"
    end
    local results = { pcall(callback, ...) }
    if not results[1] then
        return false, results[2]
    end
    return true, results[2], results[3], results[4]
end

function Util.WeakKeys()
    local value = {}
    pcall(setmetatable, value, { __mode = "k" })
    return value
end

function Util.StringOr(value, fallback)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback
end

function Util.CopyArray(value)
    local copy = {}
    if type(value) == "table" then
        for index = 1, #value do
            copy[index] = value[index]
        end
    end
    return copy
end

return Util

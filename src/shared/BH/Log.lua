-- Beautiful Humans / diagnostics.
-- The logger is intentionally small: it never writes files, never throws, and
-- keeps a bounded in-memory ring for the diagnostic UI and test reports.

BH = BH or {}

if BH.Log then
    return
end

local Log = {
    LEVELS = {
        debug = 10,
        info = 20,
        warn = 30,
        error = 40,
        critical = 50,
    },
    entries = {},
    capacity = 250,
    minimumLevel = "info",
    sequence = 0,
}
BH.Log = Log

local function levelValue(level)
    return Log.LEVELS[level] or Log.LEVELS.info
end

function Log.SetLevel(level)
    if Log.LEVELS[level] then
        Log.minimumLevel = level
        return true
    end
    return false
end

function Log.IsEnabled(level)
    return levelValue(level) >= levelValue(Log.minimumLevel)
end

function Log.Write(level, subsystem, message, data)
    level = Log.LEVELS[level] and level or "info"
    subsystem = tostring(subsystem or "bh")
    message = tostring(message or "")

    Log.sequence = Log.sequence + 1
    local entry = {
        id = Log.sequence,
        level = level,
        subsystem = subsystem,
        message = message,
        data = data,
    }

    local entryCount = #Log.entries
    if entryCount >= Log.capacity then
        table.remove(Log.entries, 1)
    end
    Log.entries[#Log.entries + 1] = entry

    if Log.IsEnabled(level) then
        local suffix = ""
        if data ~= nil then
            local ok, rendered = pcall(tostring, data)
            if ok then
                suffix = " | " .. rendered
            else
                suffix = " | <unprintable>"
            end
        end
        local line = string.format("[BH][%s][%s] %s%s", string.upper(level), subsystem, message, suffix)
        pcall(print, line)
    end

    return entry
end

function Log.Debug(subsystem, message, data)
    return Log.Write("debug", subsystem, message, data)
end

function Log.Info(subsystem, message, data)
    return Log.Write("info", subsystem, message, data)
end

function Log.Warn(subsystem, message, data)
    return Log.Write("warn", subsystem, message, data)
end

function Log.Error(subsystem, message, data)
    return Log.Write("error", subsystem, message, data)
end

function Log.Critical(subsystem, message, data)
    return Log.Write("critical", subsystem, message, data)
end

function Log.GetRecent(limit)
    limit = limit or 50
    local result = {}
    local first = math.max(1, #Log.entries - limit + 1)
    for index = first, #Log.entries do
        result[#result + 1] = Log.entries[index]
    end
    return result
end

function Log.Clear()
    Log.entries = {}
    Log.sequence = 0
end

return Log

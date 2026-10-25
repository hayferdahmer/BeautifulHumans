-- Beautiful Humans / core bootstrap.
-- Core owns identity, versioning, configuration, the internal event bus, module
-- lifecycle and diagnostics. It must not contain medical, economic or combat
-- rules.

BH = BH or {}

if BH.Core and BH.Core._loaded then
    return
end

BH.VERSION = "0.1.0"
BH.API_VERSION = 1
BH.SCHEMA_VERSION = 1
BH.MOD_ID = "BeautifulHumansCore"

require "BH/Util"
require "BH/Log"
require "BH/Config"
require "BH/EventBus"
require "BH/ModuleRegistry"

local Core = {
    _loaded = true,
    booted = false,
    started = false,
    startResult = nil,
}
BH.Core = Core

function BH.RegisterModule(definition)
    return BH.Modules.Register(definition)
end

function BH.GetVersionString()
    return string.format("%s (API %d, schema %d)", BH.VERSION, BH.API_VERSION, BH.SCHEMA_VERSION)
end

function BH.GetGameVersionString()
    local ok, version = pcall(function()
        return getCore():getGameVersion()
    end)
    if not ok or not version then
        return "unavailable"
    end
    local renderedOk, rendered = pcall(tostring, version)
    if renderedOk and rendered then
        return tostring(rendered)
    end
    return "unavailable"
end

function BH.IsGameVersionAtLeast(requiredMajor, requiredMinor)
    if not BH.Util.IsFiniteNumber(requiredMajor) then
        return false
    end
    requiredMinor = requiredMinor or 0

    local ok, version = pcall(function()
        return getCore():getGameVersion()
    end)
    if not ok or not version then
        return false
    end

    local major, minor
    local methodsOk = pcall(function()
        major = version:getMajor()
        minor = version:getMinor()
    end)
    if methodsOk and BH.Util.IsFiniteNumber(major) and BH.Util.IsFiniteNumber(minor) then
        if major ~= requiredMajor then
            return major > requiredMajor
        end
        return minor >= requiredMinor
    end

    local text = tostring(version)
    local parsedMajor, parsedMinor = string.match(text, "^(%d+)%.(%d+)")
    if parsedMajor then
        major = tonumber(parsedMajor)
        minor = tonumber(parsedMinor)
        if major ~= requiredMajor then
            return major > requiredMajor
        end
        return minor >= requiredMinor
    end
    return false
end

function BH.Boot()
    if Core.booted then
        return false
    end
    Core.booted = true

    BH.Log.Info("core", "Booting Beautiful Humans", {
        version = BH.VERSION,
        game = BH.GetGameVersionString(),
    })

    if BH.Integration and type(BH.Integration.Boot) == "function" then
        local ok, errorMessage = pcall(BH.Integration.Boot)
        if not ok then
            BH.Log.Error("core", "Integration boot failed", tostring(errorMessage))
        end
    end

    BH.Events.Emit(BH.Events.Names.CORE_BOOTED, {
        version = BH.VERSION,
        apiVersion = BH.API_VERSION,
        gameVersion = BH.GetGameVersionString(),
    })
    return true
end

function BH.Start()
    if Core.started then
        return Core.startResult
    end
    Core.started = true

    if not BH.Config.Get("enabled") then
        BH.Log.Warn("core", "Beautiful Humans is disabled by configuration")
        Core.startResult = false
        return false
    end

    BH.Context = {
        version = BH.VERSION,
        apiVersion = BH.API_VERSION,
        schemaVersion = BH.SCHEMA_VERSION,
        config = BH.Config,
        events = BH.Events,
        modules = BH.Modules,
        log = BH.Log,
        util = BH.Util,
    }

    BH.Log.Info("core", "Resolving modules")
    local results, report = BH.Modules.InitAll(BH.Context)

    local ready = 0
    local failed = 0
    local skipped = 0
    for _, result in pairs(results) do
        if result.status == "ready" then
            ready = ready + 1
        elseif result.status == "failed" then
            failed = failed + 1
        elseif result.status == "skipped" then
            skipped = skipped + 1
        end
    end

    if report and #report.cycles > 0 then
        for index = 1, #report.cycles do
            BH.Log.Critical("core", "Circular module dependency", report.cycles[index])
        end
    end

    if report and BH.Util.TableCount(report.missing) > 0 then
        for dependency in pairs(report.missing) do
            BH.Log.Error("core", "Missing module dependency", dependency)
        end
    end

    BH.Log.Info("core", "Modules initialised", {
        ready = ready,
        failed = failed,
        skipped = skipped,
        total = ready + failed + skipped,
    })

    Core.startResult = failed == 0 and skipped == 0
    BH.Events.Emit(BH.Events.Names.CORE_STARTED, {
        ready = ready,
        failed = failed,
        skipped = skipped,
        ok = Core.startResult,
    })
    return Core.startResult
end

function BH.GetStatus()
    local modules = {}
    for id in pairs(BH.Modules.defs) do
        local status, errorMessage = BH.Modules.GetStatus(id)
        modules[#modules + 1] = {
            id = id,
            status = status,
            error = errorMessage,
        }
    end
    table.sort(modules, function(left, right)
        return left.id < right.id
    end)

    return {
        version = BH.VERSION,
        apiVersion = BH.API_VERSION,
        schemaVersion = BH.SCHEMA_VERSION,
        gameVersion = BH.GetGameVersionString(),
        booted = Core.booted,
        started = Core.started,
        modules = modules,
        log = BH.Log.GetRecent(20),
    }
end

function BH.ResetForTests()
    Core.booted = false
    Core.started = false
    Core.startResult = nil
    BH.Config.Reset()
    BH.Events.Clear()
    BH.Log.Clear()
end

BH.RegisterModule({
    id = "bh.core",
    version = BH.VERSION,
    description = "Core identity, configuration, event bus and module lifecycle",
    init = function(context)
        context.log.Info("core", "Core module ready", {
            version = context.version,
            api = context.apiVersion,
            schema = context.schemaVersion,
        })
    end,
})

return Core

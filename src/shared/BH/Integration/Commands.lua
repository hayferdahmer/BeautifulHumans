-- Beautiful Humans / console and test commands.
-- These are developer-facing entry points. They deliberately bypass inventory
-- requirements; gameplay treatment must go through a server-validated action.

BH = BH or {}

if BH.Commands then
    return
end

require "BH/Core"
require "BH/Persistence/Persistence"
require "BH/Anatomy/Model"
require "BH/Medical/Medical"
require "BH/Integration/PlayerObserver"

BH.Commands = {}
local Commands = BH.Commands

local function localPlayer()
    local ok, player = pcall(function()
        return getPlayer()
    end)
    if ok and player then
        return player
    end
    return nil
end

local function printLine(message)
    pcall(print, "[BH] " .. tostring(message))
end

function Commands.Help()
    printLine("BH commands:")
    printLine("  BH.Commands.Self()")
    printLine("  BH.Commands.Injury(zone, kind, severity)")
    printLine("  BH.Commands.List()")
    printLine("  BH.Commands.Treat(injuryId, action)")
    printLine("  BH.Commands.Tick(minutes)")
    printLine("  BH.Commands.Heal(injuryId)")
    printLine("  BH.Commands.Reset()")
    printLine("  BH.Commands.Snapshot()")
end

function Commands.Self()
    local player = localPlayer()
    if not player then
        printLine("no local player")
        return
    end
    local ext = BH.Persistence.GetCharacterData(player)
    if not ext then
        printLine("no character extension")
        return
    end
    ext.metadata.ownerKey = BH.Persistence.GetPlayerKey(player)
    local injuries = BH.Anatomy.Model.GetActiveInjuries(ext)
    printLine(string.format(
        "player=%s schema=%s injuries=%d pain=%.1f blood=%.1f mobility=%.2f manipulation=%.2f",
        tostring(ext.metadata.ownerKey),
        tostring(ext.schemaVersion),
        #injuries,
        ext.physiology and ext.physiology.pain or 0,
        ext.physiology and ext.physiology.bloodLoss or 0,
        BH.Anatomy.Model.GetMobility(ext),
        BH.Anatomy.Model.GetManipulation(ext)
    ))
    for index = 1, #injuries do
        local injury = injuries[index]
        printLine(string.format(
            "  %s zone=%s kind=%s severity=%.1f bleeding=%.1f bandaged=%s splinted=%s",
            injury.id,
            injury.zone,
            injury.kind,
            injury.severity or 0,
            injury.bleeding or 0,
            tostring(injury.bandaged == true),
            tostring(injury.splinted == true)
        ))
    end
end

function Commands.Injury(zone, kind, severity)
    local player = localPlayer()
    if not player then
        printLine("no local player")
        return nil
    end
    local ext = BH.Persistence.GetCharacterData(player)
    if not ext then
        printLine("no character extension")
        return nil
    end
    ext.metadata.ownerKey = BH.Persistence.GetPlayerKey(player)

    local injury, reason = BH.Anatomy.Model.AddInjury(
        ext,
        zone or "left_thigh",
        kind or "cut",
        severity or 40,
        "debug",
        { characterKey = ext.metadata.ownerKey }
    )
    if not injury then
        printLine("injury not created: " .. tostring(reason))
        return nil
    end
    printLine("created " .. injury.id)
    return injury
end

function Commands.List()
    return Commands.Self()
end

function Commands.Treat(injuryId, action)
    local player = localPlayer()
    if not player then
        printLine("no local player")
        return nil
    end
    local ext = BH.Persistence.GetCharacterData(player)
    if not ext then
        printLine("no character extension")
        return nil
    end
    ext.metadata.ownerKey = BH.Persistence.GetPlayerKey(player)

    if not injuryId then
        local injuries = BH.Anatomy.Model.GetActiveInjuries(ext)
        if #injuries == 0 then
            printLine("no active injuries")
            return nil
        end
        injuryId = injuries[1].id
    end

    local result = BH.Medical.Apply(ext, injuryId, action or "bandage", {
        bypassItems = true,
        requestId = "debug-" .. tostring(os.time and os.time() or 0) .. "-" .. tostring(injuryId),
        itemIsDirty = false,
    })
    if result.ok then
        printLine("treatment applied: " .. tostring(action or "bandage") .. " -> " .. injuryId)
    else
        printLine("treatment rejected: " .. tostring(result.error))
    end
    return result
end

function Commands.Tick(minutes)
    local player = localPlayer()
    if not player then
        printLine("no local player")
        return
    end
    local ext = BH.Persistence.GetCharacterData(player)
    if not ext then
        printLine("no character extension")
        return
    end
    local healed = BH.Anatomy.Model.Tick(ext, minutes or 10)
    BH.Physiology.Tick(ext, minutes or 10)
    printLine(string.format("tick %.1f minutes, healed=%d", minutes or 10, healed or 0))
end

function Commands.Heal(injuryId)
    local player = localPlayer()
    if not player then
        printLine("no local player")
        return
    end
    local ext = BH.Persistence.GetCharacterData(player)
    if not ext then
        printLine("no character extension")
        return
    end
    local ok, reason = BH.Anatomy.Model.HealInjury(ext, injuryId, "debug")
    printLine(ok and "healed" or ("heal failed: " .. tostring(reason)))
end

function Commands.Reset()
    local player = localPlayer()
    if not player then
        printLine("no local player")
        return
    end
    BH.Persistence.ResetCharacterData(player)
    BH.Integration.Player.baselines[BH.Integration.Player.Key(player)] = nil
    printLine("character extension reset")
end

function Commands.Snapshot()
    local player = localPlayer()
    if not player then
        return nil
    end
    local ext = BH.Persistence.GetCharacterData(player)
    if not ext then
        return nil
    end
    return {
        schemaVersion = ext.schemaVersion,
        summary = BH.Persistence.GetSummary(ext),
        mobility = BH.Anatomy.Model.GetMobility(ext),
        manipulation = BH.Anatomy.Model.GetManipulation(ext),
        consciousness = BH.Anatomy.Model.GetConsciousness(ext),
        respiration = BH.Anatomy.Model.GetRespiration(ext),
        injuries = BH.Anatomy.Model.GetActiveInjuries(ext),
    }
end

return Commands

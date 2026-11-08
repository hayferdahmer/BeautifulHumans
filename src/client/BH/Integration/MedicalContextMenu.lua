-- Beautiful Humans / client context-menu entry point.

BH = BH or {}
BH.Integration = BH.Integration or {}

if BH.Integration.MedicalContextMenu then
    return
end

local ContextMenu = {}
BH.Integration.MedicalContextMenu = ContextMenu

function ContextMenu.Open(player)
    if not player or not BH.UI or not BH.UI.MedicalPanel then
        return
    end
    BH.UI.MedicalPanel.Open(player)
end

function ContextMenu.OnPreFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then
        return
    end
    if not context or not getSpecificPlayer then
        return
    end

    local player = getSpecificPlayer(playerNum)
    if not player then
        return
    end

    local option = context:addOption(
        "Beautiful Humans: Medical",
        player,
        ContextMenu.Open
    )
    if option then
        option.toolTip = "Inspect injuries and perform medical procedures."
    end
end

function ContextMenu.OnServerCommand(module, command, args)
    if module ~= "BH" or command ~= "treatmentResult" then
        return
    end
    local panel = BH.UI and BH.UI.MedicalPanel and BH.UI.MedicalPanel.instance
    if panel then
        panel:onTreatmentResult(args)
    end
end

function ContextMenu.Boot()
    if not Events then
        return false
    end
    if Events.OnPreFillWorldObjectContextMenu then
        Events.OnPreFillWorldObjectContextMenu.Add(ContextMenu.OnPreFillWorldObjectContextMenu)
    elseif Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(ContextMenu.OnPreFillWorldObjectContextMenu)
    else
        BH.Log.Warn("medical-ui", "World context-menu event is unavailable")
        return false
    end

    if Events.OnServerCommand then
        Events.OnServerCommand.Add(ContextMenu.OnServerCommand)
    end
    return true
end

ContextMenu.Boot()
return ContextMenu

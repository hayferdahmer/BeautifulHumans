-- Beautiful Humans / player-facing medical panel.
-- The panel is presentation only. All treatment effects are applied by the
-- shared timed action on the authoritative server.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "TimedActions/ISTimedActionQueue"

BH = BH or {}
BH.UI = BH.UI or {}

if BH.UI.MedicalPanel then
    return
end

local MedicalPanel = ISCollapsableWindow:derive("BHMedicalPanel")
BH.UI.MedicalPanel = MedicalPanel
MedicalPanel.instance = nil

local actionDefinitions = {
    { id = "examine", label = "Examine" },
    { id = "clean", label = "Clean wound" },
    { id = "bandage", label = "Bandage" },
    { id = "splint", label = "Apply splint" },
    { id = "stitch", label = "Stitch wound" },
    { id = "remove_bandage", label = "Remove bandage" },
}

local function safePlayerData(player)
    if not player or not BH.Persistence or not BH.Anatomy then
        return nil, {}
    end
    local ok, ext = pcall(BH.Persistence.GetCharacterData, player)
    if not ok or not ext then
        return nil, {}
    end
    return ext, BH.Anatomy.Model.GetActiveInjuries(ext)
end

function MedicalPanel:new(player)
    local width, height = 540, 420
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local x = math.max(20, (screenWidth - width) / 2)
    local y = math.max(20, (screenHeight - height) / 2)

    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.title = "Beautiful Humans - Medical"
    o.resizable = false
    o.pin = false
    o.selectedInjuryId = nil
    o.statusText = "Select an injury to view available procedures."
    o.requestSequence = 0
    o.injuryButtons = {}
    o.actionButtons = {}
    return o
end

function MedicalPanel:initialise()
    ISCollapsableWindow.initialise(self)
end

function MedicalPanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    self:drawText("ACTIVE INJURIES", 12, 34, 0.85, 0.88, 0.92, 1, UIFont.Small)
    self:drawText("SELECTED INJURY", 260, 34, 0.85, 0.88, 0.92, 1, UIFont.Small)

    for index = 1, 6 do
        local button = ISButton:new(12, 58 + (index - 1) * 42, 224, 34, "", self, MedicalPanel.onSelectInjury)
        button:initialise()
        button:instantiate()
        button.injuryId = nil
        self:addChild(button)
        self.injuryButtons[index] = button
    end

    for index = 1, #actionDefinitions do
        local definition = actionDefinitions[index]
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local button = ISButton:new(260 + column * 128, 172 + row * 48, 120, 38, definition.label, self, MedicalPanel.onStartTreatment)
        button:initialise()
        button:instantiate()
        button.actionId = definition.id
        self:addChild(button)
        self.actionButtons[definition.id] = button
    end

    self.statusText = "Select an injury."
    self:refresh()
end

function MedicalPanel:getSelectedInjury()
    if not self.selectedInjuryId then
        return nil
    end
    local ext = safePlayerData(self.player)
    if not ext then
        return nil
    end
    return BH.Anatomy.Model.FindInjury(ext, self.selectedInjuryId)
end

function MedicalPanel:refresh()
    local ext, injuries = safePlayerData(self.player)
    for index = 1, #self.injuryButtons do
        local button = self.injuryButtons[index]
        local injury = injuries[index]
        button:setVisible(injury ~= nil)
        if injury then
            button.injuryId = injury.id
            local zone = BH.Anatomy.Zones.Get(injury.zone)
            local diagnosis = BH.Medical.GetDiagnosis(ext, injury.id)
            local zoneLabel = zone and zone.label or injury.zone
            local severity = diagnosis and diagnosis.severityBand or "unknown"
            local title = string.format("%s | %s | %s", zoneLabel, injury.kind, severity)
            button:setTitle(title)
            button.enable = true
            if not self.selectedInjuryId then
                self.selectedInjuryId = injury.id
            end
        else
            button.injuryId = nil
        end
    end

    local selected = self:getSelectedInjury()
    if selected then
        local diagnosis = BH.Medical.GetDiagnosis(ext, selected.id)
        local zone = BH.Anatomy.Zones.Get(selected.zone)
        self.selectedTitle = string.format("%s - %s", zone and zone.label or selected.zone, selected.kind)
        self.selectedDetails = string.format(
            "Severity: %s | Bleeding: %.1f | Contamination: %.1f",
            diagnosis and diagnosis.severityBand or "unknown",
            selected.bleeding or 0,
            selected.contamination or 0
        )
    else
        self.selectedTitle = "No active injury selected"
        self.selectedDetails = ""
        self.selectedInjuryId = nil
    end

    local inventory = nil
    pcall(function()
        inventory = self.player:getInventory()
    end)
    for index = 1, #actionDefinitions do
        local definition = actionDefinitions[index]
        local button = self.actionButtons[definition.id]
        local available, reason = false, "Select an injury"
        if ext and selected then
            available, reason = BH.Medical.CanApply(ext, selected.id, definition.id, {
                hasItem = function(alias)
                    return inventory ~= nil and BH.Medical.Inventory.HasAlias(inventory, alias)
                end,
            })
        end
        button.enable = available == true
        button.tooltip = available and nil or tostring(reason or "Unavailable")
    end
end

function MedicalPanel:onSelectInjury(button)
    if not button or not button.injuryId then
        return
    end
    self.selectedInjuryId = button.injuryId
    self:refresh()
end

function MedicalPanel:onStartTreatment(button)
    if not button or not button.actionId or not self.selectedInjuryId then
        return
    end
    local ext = safePlayerData(self.player)
    local selected = BH.Anatomy.Model.FindInjury(ext, self.selectedInjuryId)
    if not selected then
        self.statusText = "The selected injury is no longer available."
        self:refresh()
        return
    end

    local inventory = self.player:getInventory()
    local canApply, reason = BH.Medical.CanApply(ext, selected.id, button.actionId, {
        hasItem = function(alias)
            return BH.Medical.Inventory.HasAlias(inventory, alias)
        end,
    })
    if not canApply then
        self.statusText = tostring(reason or "Treatment unavailable.")
        self:refresh()
        return
    end

    self.requestSequence = self.requestSequence + 1
    local onlineId = "local"
    pcall(function()
        onlineId = tostring(self.player:getOnlineID())
    end)
    local timestamp = os.time and os.time() or 0
    local requestId = string.format("bh-%s-%s-%d", onlineId, tostring(timestamp), self.requestSequence)

    local action = BH.Medical.TimedAction:new(
        self.player,
        selected.id,
        button.actionId,
        requestId
    )
    ISTimedActionQueue.add(action)
    self.statusText = "Treatment started: " .. button.actionId
    self:refresh()
end

function MedicalPanel:onTreatmentResult(args)
    if type(args) ~= "table" then
        return
    end
    if args.ok then
        self.statusText = "Treatment completed: " .. tostring(args.action or "procedure")
    else
        self.statusText = "Treatment failed: " .. tostring(args.error or "server rejected request")
    end
    self:refresh()
end

function MedicalPanel:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then
        return
    end

    self:drawText(self.selectedTitle or "No injury selected", 260, 62, 1, 1, 1, 1, UIFont.Medium)
    self:drawText(self.selectedDetails or "", 260, 92, 0.82, 0.84, 0.86, 1, UIFont.Small)

    local selected = self:getSelectedInjury()
    if selected then
        self:drawText("Bleeding: " .. tostring(selected.bleeding or 0), 260, 120, 1, 0.72, 0.62, 1, UIFont.Small)
        self:drawText("Bandaged: " .. (selected.bandaged and "Yes" or "No"), 260, 140, 0.85, 0.88, 0.92, 1, UIFont.Small)
    end

    self:drawRect(12, 330, self.width - 24, 1, 0.6, 0.55, 0.55, 0.55)
    self:drawText(self.statusText or "", 14, 344, 0.9, 0.9, 0.9, 1, UIFont.Small)
    self:drawText("Treatment effects are confirmed by the server.", 14, 374, 0.65, 0.72, 0.78, 1, UIFont.Small)
end

function MedicalPanel:close()
    ISCollapsableWindow.close(self)
    if MedicalPanel.instance == self then
        MedicalPanel.instance = nil
    end
end

function MedicalPanel.Open(player)
    if MedicalPanel.instance and MedicalPanel.instance:getIsVisible() then
        MedicalPanel.instance:bringToTop()
        MedicalPanel.instance:refresh()
        return MedicalPanel.instance
    end
    local panel = MedicalPanel:new(player)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(true)
    panel:refresh()
    MedicalPanel.instance = panel
    return panel
end

return MedicalPanel

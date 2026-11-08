-- Beautiful Humans / shared timed medical action.
-- The client owns presentation; the server owns completion and all mutations.

BH = BH or {}

if not ISBaseTimedAction then
    local ok = pcall(require, "TimedActions/ISBaseTimedAction")
    if not ok or not ISBaseTimedAction then
        return
    end
end

BH.Medical = BH.Medical or {}

if BH.Medical.TimedAction then
    return
end

local TimedAction = ISBaseTimedAction:derive("BHTimedMedicalAction")
BH.Medical.TimedAction = TimedAction

local function getTreatment(actionId)
    return BH.Medical and BH.Medical.Treatments
        and BH.Medical.Treatments.Get(actionId) or nil
end

function TimedAction:new(character, injuryId, actionId, requestId)
    local o = ISBaseTimedAction.new(self, character)
    setmetatable(o, self)
    self.__index = self

    local treatment = getTreatment(actionId)
    o.character = character
    o.injuryId = injuryId
    o.actionId = actionId
    o.requestId = requestId
    o.duration = treatment and treatment.duration or 100
    o.maxTime = o.duration
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.caloriesModifier = 1.0
    return o
end

function TimedAction:isValid()
    if not self.character or not self.injuryId or not self.actionId then
        return false
    end
    local aliveOk, dead = pcall(function()
        return self.character:isDead()
    end)
    if not aliveOk or dead == true then
        return false
    end
    local ext = BH.Persistence.GetCharacterData(self.character)
    if not ext then
        return false
    end
    return BH.Anatomy.Model.FindInjury(ext, self.injuryId) ~= nil
        and getTreatment(self.actionId) ~= nil
end

function TimedAction:start()
    self:setActionAnim("Bandage")
    self.character:setVariable("BandageType", "Bandage")
end

function TimedAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function TimedAction:stop()
    ISBaseTimedAction.stop(self)
end

function TimedAction:perform()
    ISBaseTimedAction.perform(self)
end

-- Build 42 executes complete() on the authoritative server for MP timed actions.
function TimedAction:complete()
    if isServer and isServer() then
        if BH.Integration and BH.Integration.Network then
            BH.Integration.Network.HandleTreatment(self.character, {
                injuryId = self.injuryId,
                action = self.actionId,
                requestId = self.requestId,
            })
        end
    end
end

function TimedAction:getDuration()
    return self.duration or self.maxTime or 100
end

return TimedAction

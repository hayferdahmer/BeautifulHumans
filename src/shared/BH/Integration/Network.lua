-- Beautiful Humans / authoritative treatment command handler.
-- Clients send intent only. The server resolves the player's own injury,
-- validates the treatment and inventory, consumes items, then applies effects.

BH = BH or {}

if BH.Integration and BH.Integration.Network then
    return
end

require "BH/Core"
require "BH/Persistence/Persistence"
require "BH/Anatomy/Model"
require "BH/Medical/Medical"
require "BH/Medical/Inventory"

BH.Integration = BH.Integration or {}

local Network = {
    requestCounters = {},
    lastRequestAt = {},
}
BH.Integration.Network = Network

local function sendResult(player, payload)
    if not sendServerCommand or not player then
        return
    end
    pcall(function()
        sendServerCommand(player, "BH", "treatmentResult", payload)
    end)
end

local function isAlive(player)
    local ok, dead = pcall(function()
        return player:isDead()
    end)
    return ok and dead ~= true
end

local function validString(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum
end

function Network.HandleTreatment(player, args)
    local requestId = type(args) == "table" and args.requestId or nil
    local function reject(reason, duplicate)
        sendResult(player, {
            requestId = requestId,
            ok = false,
            duplicate = duplicate == true,
            error = reason,
        })
        return false, reason
    end

    if not player or type(args) ~= "table" then
        return reject("invalid request")
    end
    if not validString(args.requestId, 96)
        or not validString(args.injuryId, 64)
        or not validString(args.action, 32) then
        return reject("invalid request fields")
    end
    if not isAlive(player) then
        return reject("player is not alive")
    end

    local key = BH.Persistence.GetPlayerKey(player)
    local now = os.time and os.time() or 0
    local window = Network.lastRequestAt[key]
    if not window or now - window.startedAt >= 10 then
        window = { startedAt = now, count = 0 }
        Network.lastRequestAt[key] = window
    end
    window.count = window.count + 1
    if window.count > 8 then
        return reject("too many requests")
    end

    local ext, dataError = BH.Persistence.GetCharacterData(player)
    if not ext then
        return reject(dataError or "character data unavailable")
    end
    ext.metadata = ext.metadata or {}
    ext.metadata.ownerKey = key

    ext.medical = ext.medical or {}
    if ext.medical.processedRequests and ext.medical.processedRequests[args.requestId] then
        return reject("request already processed", true)
    end

    local treatment = BH.Medical.Treatments.Get(args.action)
    if not treatment then
        return reject("unknown treatment")
    end

    local inventory = nil
    local inventoryOk = pcall(function()
        inventory = player:getInventory()
    end)
    if not inventoryOk or not inventory then
        return reject("inventory unavailable")
    end

    local resolved, inventoryError = BH.Medical.Inventory.Resolve(inventory, treatment.requirements)
    if not resolved then
        return reject(inventoryError or "required items unavailable")
    end

    local canApply, reason = BH.Medical.CanApply(ext, args.injuryId, args.action, {
        hasItem = function(alias)
            return BH.Medical.Inventory.HasAlias(inventory, alias)
        end,
    })
    if not canApply then
        return reject(reason or "treatment rejected")
    end

    -- Consume first. If domain validation unexpectedly fails, restore the
    -- exact resolved items rather than granting a free treatment.
    local consumed, consumeError = BH.Medical.Inventory.Consume(inventory, resolved)
    if not consumed then
        return reject(consumeError or "could not consume treatment items")
    end

    local result = BH.Medical.Apply(ext, args.injuryId, args.action, {
        requestId = args.requestId,
        bypassItems = true,
        itemIsDirty = false,
    })
    if not result.ok then
        BH.Medical.Inventory.Restore(inventory, resolved)
        return reject(result.error or "treatment failed", result.duplicate)
    end

    sendResult(player, {
        requestId = args.requestId,
        ok = true,
        injuryId = result.injuryId,
        action = result.action,
        injury = result.injury,
        changes = result.changes,
    })
    return true, result
end

function Network.OnClientCommand(module, command, player, args)
    if module ~= "BH" or command ~= "treat" then
        return
    end
    local ok, err = pcall(Network.HandleTreatment, player, args)
    if not ok then
        BH.Log.Error("network", "Treatment command failed", tostring(err))
        sendResult(player, {
            requestId = type(args) == "table" and args.requestId or nil,
            ok = false,
            error = "internal treatment error",
        })
    end
end

return Network

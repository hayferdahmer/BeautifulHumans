describe("Integration.Network", function()
    local function newPlayer(name, fullTypes)
        local inventory = { values = {} }
        for index = 1, #(fullTypes or {}) do
            local fullType = fullTypes[index]
            inventory.values[#inventory.values + 1] = {
                getFullType = function()
                    return fullType
                end,
            }
        end
        local itemList = {
            size = function()
                return #inventory.values
            end,
            get = function(_, index)
                return inventory.values[index + 1]
            end,
        }
        function inventory:getItems()
            return itemList
        end
        function inventory:Remove(item)
            for index = #self.values, 1, -1 do
                if self.values[index] == item then
                    table.remove(self.values, index)
                    return
                end
            end
            error("item not found")
        end
        function inventory:AddItem(value)
            local fullType = value
            self.values[#self.values + 1] = {
                getFullType = function()
                    return fullType
                end,
            }
        end

        local player = {
            data = {},
            inventory = inventory,
        }
        function player:getUsername()
            return name
        end
        function player:getModData()
            return self.data
        end
        function player:isDead()
            return false
        end
        function player:getInventory()
            return self.inventory
        end
        return player
    end

    it("validates, consumes and applies a treatment on the server", function()
        local player = newPlayer("network-bandage-player", { "Base.Bandage" })
        local ext = BH.Persistence.GetCharacterData(player)
        local injury = BH.Anatomy.Model.AddInjury(ext, "left_thigh", "cut", 60, "test")
        local ok, result = BH.Integration.Network.HandleTreatment(player, {
            injuryId = injury.id,
            action = "bandage",
            requestId = "network-bandage-1",
        })
        truthy(ok)
        truthy(result.ok)
        truthy(injury.bandaged)
        eq(#player.inventory.values, 0)
    end)

    it("rejects a repeated request without consuming another item", function()
        local player = newPlayer("network-duplicate-player", { "Base.Bandage" })
        local ext = BH.Persistence.GetCharacterData(player)
        local injury = BH.Anatomy.Model.AddInjury(ext, "left_thigh", "cut", 60, "test")
        local args = {
            injuryId = injury.id,
            action = "bandage",
            requestId = "network-duplicate-1",
        }
        truthy(BH.Integration.Network.HandleTreatment(player, args))
        local ok, reason = BH.Integration.Network.HandleTreatment(player, args)
        falsy(ok)
        contains(reason, "already processed")
        eq(#player.inventory.values, 0)
        eq(injury.treatmentCount, 1)
    end)

    it("rejects treatment without required items and leaves injury unchanged", function()
        local player = newPlayer("network-no-item-player", {})
        local ext = BH.Persistence.GetCharacterData(player)
        local injury = BH.Anatomy.Model.AddInjury(ext, "left_thigh", "cut", 60, "test")
        local before = injury.bleeding
        local ok, reason = BH.Integration.Network.HandleTreatment(player, {
            injuryId = injury.id,
            action = "bandage",
            requestId = "network-no-item-1",
        })
        falsy(ok)
        contains(reason, "bandage")
        falsy(injury.bandaged)
        eq(injury.bleeding, before)
    end)
end)

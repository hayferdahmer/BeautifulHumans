describe("Medical.Inventory", function()
    local function makeItem(fullType)
        return {
            getFullType = function()
                return fullType
            end,
        }
    end

    local function makeContainer(items)
        local container = { items = items }
        local list = {
            size = function()
                return #container.items
            end,
            get = function(_, index)
                return container.items[index + 1]
            end,
        }
        function container:getItems()
            return list
        end
        function container:Remove(item)
            for index = #self.items, 1, -1 do
                if self.items[index] == item then
                    table.remove(self.items, index)
                    return
                end
            end
            error("item not found")
        end
        function container:AddItem(value)
            if type(value) == "string" then
                self.items[#self.items + 1] = makeItem(value)
            else
                self.items[#self.items + 1] = value
            end
        end
        return container
    end

    it("resolves and consumes the exact required bandage", function()
        local bandage = makeItem("Base.Bandage")
        local container = makeContainer({ bandage, makeItem("Base.Water") })
        local resolved = BH.Medical.Inventory.Resolve(container, {
            { any = { "Bandage" }, consume = true, label = "bandage" },
        })
        truthy(resolved)
        eq(resolved[1].item, bandage)
        truthy(BH.Medical.Inventory.Consume(container, resolved))
        eq(#container.items, 1)
        eq(container.items[1]:getFullType(), "Base.Water")
    end)

    it("does not match an unrelated item as a bandage", function()
        local container = makeContainer({ makeItem("Base.Water") })
        local resolved, reason = BH.Medical.Inventory.Resolve(container, {
            { any = { "Bandage", "RagBandage" }, consume = true, label = "bandage" },
        })
        falsy(resolved)
        contains(reason, "bandage")
    end)

    it("requires distinct items for separate consumed requirements", function()
        local container = makeContainer({ makeItem("Base.Bandage") })
        local resolved = BH.Medical.Inventory.Resolve(container, {
            { any = { "Bandage" }, consume = true, label = "bandage" },
            { any = { "Bandage" }, consume = true, label = "binding" },
        })
        falsy(resolved)
    end)

    it("restores a consumed item after a rejected domain action", function()
        local bandage = makeItem("Base.Bandage")
        local container = makeContainer({ bandage })
        local resolved = BH.Medical.Inventory.Resolve(container, {
            { any = { "Bandage" }, consume = true, label = "bandage" },
        })
        truthy(BH.Medical.Inventory.Consume(container, resolved))
        truthy(BH.Medical.Inventory.Restore(container, resolved))
        eq(#container.items, 1)
        eq(container.items[1]:getFullType(), "Base.Bandage")
    end)
end)

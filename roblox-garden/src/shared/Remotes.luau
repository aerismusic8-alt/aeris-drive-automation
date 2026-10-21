--!strict
-- Remote and instance names, in one place. Pure Luau.
--
-- The client and the server must agree on every name, and a typo in either is a
-- silently dead feature: the client fires into nothing and the button does
-- nothing. Both sides read the names from here, so the only way to get one wrong
-- is to get it wrong in one place, where a test can see it.

local Remotes = {}

-- Client -> server requests.
Remotes.Requests = {
        Plant = "GardenPlant",
        Harvest = "GardenHarvest",
        HarvestAll = "GardenHarvestAll",
        Sell = "GardenSell",
        BuySeed = "GardenBuySeed",
        Restock = "GardenRestock",
        BuyPlot = "GardenBuyPlot",
        BuyUpgrade = "GardenBuyUpgrade",
        BuyEgg = "GardenBuyEgg",
        EquipPet = "GardenEquipPet",
        UnequipPet = "GardenUnequipPet",
        GetState = "GardenGetState",
}

-- Server -> client pushes.
Remotes.Pushes = {
        State = "GardenState",
        Toast = "GardenToast",
        Harvested = "GardenHarvested",
}

-- The folders the server builds and the client looks up.
Remotes.Folders = {
        Remotes = "Remotes",
        Shared = "Shared",
}

-- The part name on a plot model, used by the client to find what to draw on.
Remotes.PlotPartName = "Plot"

-- Every request and push name, sorted. A test walks this to prove no two
-- remotes share a name and none is empty, which would make two features fight
-- over one remote.
function Remotes.all(): { string }
        local out: { string } = {}
        for _, name in pairs(Remotes.Requests) do
                table.insert(out, name)
        end
        for _, name in pairs(Remotes.Pushes) do
                table.insert(out, name)
        end
        table.sort(out)
        return out
end

return Remotes

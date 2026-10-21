--!nocheck
-- Runtime tests for AX Garden Legends: boot the real server, build the real
-- garden, load the real client, join a real player, and play the loop.
--
-- Why this file exists. The 114 unit tests in run.luau prove the *rules* are
-- right. They cannot prove the game runs, because none of them touch
-- init.server.luau, World.luau, Hud.luau or init.client.luau -- the code that
-- actually executes in Roblox. The previous game in this repository passed its
-- whole unit suite while being unplayable, for exactly that reason.
--
-- So this suite plays the game: it plants a seed through the remotes the client
-- calls, ripens it, harvests it, sells it, and reads the coins back. If any link
-- in that chain is broken the test fails, which is the only way to know that
-- "K can tap this" is true before telling K to try it.
--
-- A returning player is simulated by writing a save into the DataStore with
-- Shim.putSave and then joining. That is how the offline-growth path and the
-- later-game states (a ripe crop, enough coins to buy a plot) are reached
-- without cheating the game's own rules.
--
--   luau roblox-garden/tests/runtime.luau

local t = require("../../roblox/tests/TestRunner")
local Shim = require("../../roblox/tests/RobloxShim")
local Sources = require("./.generated/Sources")

local function boot()
        return Shim.bootServer(Sources)
end

-- Join a player and capture the state the server pushes them. The handler is
-- disconnected after the first push: a handler that stays connected would keep
-- overwriting the captured value, so a test reading it later would see a newer
-- state than the one it meant to snapshot.
local function joinAndCapture(env, userId, name)
        local captured = nil
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        local connection = State.OnClientEvent:Connect(function(payload)
                captured = payload
        end)
        Shim.joinPlayer(env, userId, name)
        connection:Disconnect()
        return captured
end

-- Call a server remote the way the client's InvokeServer does.
local function call(env, name, player, ...)
        local remote = env.__replicatedRemotes:FindFirstChild(name)
        if not remote or type(remote.OnServerInvoke) ~= "function" then
                return false, nil, "NO_REMOTE:" .. tostring(name)
        end
        return remote.OnServerInvoke(player, ...)
end

-- The state the server most recently pushed to a player. The handler is
-- disconnected before returning, so the value is a snapshot of that moment and
-- cannot be changed by a later push.
local function latestState(env, player)
        local latest = nil
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        local connection = State.OnClientEvent:Connect(function(payload)
                latest = payload
        end)
        call(env, "GardenGetState", player)
        connection:Disconnect()
        return latest
end

-- A save for a returning player: coins to spend, and one plot holding a crop
-- that ripened long ago. The plot is written exactly as the server writes it,
-- so joining exercises the real load-and-migrate path.
local function returningSave(env, coins, plotIndex, seedId)
        local SaveSchema = env.__load("shared/SaveSchema")
        local save = SaveSchema.new(os.time() - 3600)
        save.coins = coins
        save.garden.plots[plotIndex].seedId = seedId
        save.garden.plots[plotIndex].plantedAt = os.time() - 7200
        save.garden.plots[plotIndex].readyAt = os.time() - 3600
        return save
end

--------------------------------------------------------------------------
t.suite("Garden runtime: the world builds")
--------------------------------------------------------------------------

t.test("the server builds a world with one plot per config plot", function()
        local env = boot()
        local Config = env.__load("shared/Config")

        local root = env.__workspace:FindFirstChild("GardenWorld")
        t.assertTrue(root ~= nil, "the server built no world")

        local plots = 0
        for _, child in ipairs(root:GetChildren()) do
                if child.Name:match("^Plot%d+$") then
                        plots += 1
                end
        end
        t.assertEqual(plots, Config.Garden.TotalPlots,
                "world plot count must match the logic's plot count")
end)

t.test("the world has ground to stand on", function()
        local env = boot()
        local root = env.__workspace:FindFirstChild("GardenWorld")
        t.assertTrue(root:FindFirstChild("Ground") ~= nil, "no ground")
end)

t.test("every plot is in the world at a distinct position", function()
        local env = boot()
        local root = env.__workspace:FindFirstChild("GardenWorld")
        local seen = {}
        for _, child in ipairs(root:GetChildren()) do
                if child.Name:match("^Plot%d+$") then
                        local soil = child:FindFirstChild("Soil")
                        t.assertTrue(soil ~= nil, child.Name .. " has no soil")
                        local key = tostring(soil.Position)
                        t.assertFalse(seen[key] == true, "two plots share a position: " .. key)
                        seen[key] = true
                end
        end
end)

--------------------------------------------------------------------------
t.suite("Garden runtime: the server serves a player")
--------------------------------------------------------------------------

t.test("the server creates every remote the client needs", function()
        local env = boot()
        local Remotes = env.__load("shared/Remotes")
        local folder = env.__replicatedRemotes

        for _, name in ipairs({
                Remotes.Requests.Plant, Remotes.Requests.Harvest, Remotes.Requests.HarvestAll,
                Remotes.Requests.Sell, Remotes.Requests.BuySeed, Remotes.Requests.Restock,
                Remotes.Requests.BuyPlot, Remotes.Requests.BuyUpgrade, Remotes.Requests.BuyEgg,
                Remotes.Requests.EquipPet, Remotes.Requests.UnequipPet,
                Remotes.Pushes.State, Remotes.Pushes.Toast,
        }) do
                t.assertTrue(folder:FindFirstChild(name) ~= nil, "missing remote " .. name)
        end
end)

t.test("there is only ever one Remotes folder", function()
        local env = boot()
        local count = 0
        for _, child in ipairs(env.__game:GetService("ReplicatedStorage"):GetChildren()) do
                if child.Name == "Remotes" then
                        count += 1
                end
        end
        t.assertEqual(count, 1, "the server made a second Remotes folder")
end)

t.test("joining pushes a state payload with every field the HUD reads", function()
        local env = boot()
        local payload = joinAndCapture(env, 101, "Farmer")
        t.assertTrue(payload ~= nil, "the server pushed no state on join")
        if not payload then
                return
        end

        for _, field in ipairs({ "coins", "garden", "upgrades", "pets", "basket", "collection", "shop", "seeds", "eggs", "serverTime" }) do
                t.assertTrue(payload[field] ~= nil, "state is missing " .. field)
        end
        t.assertEqual(#payload.garden.plots, 12, "plot count in the payload")
        t.assertGreater(#payload.shop.stock, 0, "the shop stocked nothing")
end)

t.test("a new player starts with coins and unlocked plots", function()
        local env = boot()
        local Config = env.__load("shared/Config")
        local payload = joinAndCapture(env, 102, "Newbie")
        t.assertEqual(payload.coins, Config.Economy.StartingCoins, "starting coins")
        t.assertEqual(payload.garden.unlocked, Config.Garden.StartingPlots, "starting plots")
end)

t.test("a returning player's save is loaded, not replaced", function()
        local env = boot()
        local save = returningSave(env, 7777, 1, "Carrot")
        Shim.putSave(env, 103, save)
        local payload = joinAndCapture(env, 103, "Returning")
        t.assertEqual(payload.coins, 7777, "the stored coins were not loaded")
        t.assertEqual(payload.garden.plots[1].seedId, "Carrot", "the stored crop was not loaded")
end)

t.test("a crop that ripened while away is ready on join", function()
        local env = boot()
        local save = returningSave(env, 500, 1, "Carrot")
        Shim.putSave(env, 104, save)
        local payload = joinAndCapture(env, 104, "Offline")
        t.assertTrue(payload.garden.plots[1].ready, "an offline-ripened crop was not ready on join")
end)

--------------------------------------------------------------------------
t.suite("Garden runtime: the loop actually plays")
--------------------------------------------------------------------------

-- The headline test. Plant -> ripen -> harvest -> sell -> coins, driven only
-- through the remotes the client calls.
t.test("a crop can be planted, harvested and sold for coins", function()
        local env = boot()
        local save = returningSave(env, 1000, 1, "Carrot")
        Shim.putSave(env, 201, save)
        local player = Shim.joinPlayer(env, 201, "Player")
        local payload = latestState(env, player)
        t.assertTrue(payload ~= nil, "no state")
        if not payload then
                return
        end

        local coinsBefore = payload.coins

        -- Harvest the ripe crop through the remote the client taps.
        local ok, harvested = call(env, "GardenHarvest", player, 1)
        t.assertTrue(ok, "harvesting a ripe crop failed")
        t.assertNotNil(harvested, "harvest returned nothing")
        t.assertNotNil(harvested.reward, "harvest returned no crop")

        local afterHarvest = latestState(env, player)
        t.assertEqual(afterHarvest.basket.count, 1, "the crop did not reach the basket")

        -- Sell it.
        local soldOk, sold = call(env, "GardenSell", player)
        t.assertTrue(soldOk, "selling failed")
        t.assertGreater(sold.total, 0, "the crop sold for nothing")

        local afterSell = latestState(env, player)
        t.assertGreater(afterSell.coins, coinsBefore, "selling did not earn coins")
        t.assertEqual(afterSell.basket.count, 0, "the basket was not emptied")
        t.assertEqual(afterSell.collection.sold, 1, "the sale was not recorded in the collection")
end)

t.test("planting a seed costs coins and fills the plot", function()
        local env = boot()
        local save = returningSave(env, 1000, 1, "Carrot")
        Shim.putSave(env, 202, save)
        local player = Shim.joinPlayer(env, 202, "Planter")
        local before = latestState(env, player)

        local ok = call(env, "GardenPlant", player, 2, "Carrot")
        t.assertTrue(ok, "planting failed")

        local after = latestState(env, player)
        t.assertLess(after.coins, before.coins, "planting was free")
        t.assertEqual(after.garden.plots[2].seedId, "Carrot", "the plot did not take the seed")
        t.assertFalse(after.garden.plots[2].ready, "a just-planted crop is already ripe")
end)

t.test("harvesting an unripe crop is refused", function()
        local env = boot()
        local save = returningSave(env, 1000, 1, "Carrot")
        Shim.putSave(env, 203, save)
        local player = Shim.joinPlayer(env, 203, "Impatient")

        call(env, "GardenPlant", player, 2, "Carrot")
        local ok, _, message = call(env, "GardenHarvest", player, 2)
        t.assertFalse(ok, "an unripe crop was harvested")
        t.assertNotNil(message, "no reason given")
end)

t.test("harvest all takes every ripe crop at once", function()
        local env = boot()
        local save = returningSave(env, 1000, 1, "Carrot")
        save.garden.plots[2].seedId = "Carrot"
        save.garden.plots[2].plantedAt = os.time() - 7200
        save.garden.plots[2].readyAt = os.time() - 3600
        save.garden.plots[3].seedId = "Strawberry"
        save.garden.plots[3].plantedAt = os.time() - 7200
        save.garden.plots[3].readyAt = os.time() - 3600
        Shim.putSave(env, 204, save)
        local player = Shim.joinPlayer(env, 204, "Harvester")

        local ok, result = call(env, "GardenHarvestAll", player)
        t.assertTrue(ok, "harvest all failed")
        t.assertEqual(result.harvested, 3, "harvest all missed a ripe crop")

        local after = latestState(env, player)
        t.assertEqual(after.basket.count, 3, "the crops did not reach the basket")
end)

t.test("a locked plot cannot be planted", function()
        local env = boot()
        local Config = env.__load("shared/Config")
        local save = returningSave(env, 1000, 1, "Carrot")
        Shim.putSave(env, 205, save)
        local player = Shim.joinPlayer(env, 205, "Locked")
        local ok, _, message = call(env, "GardenPlant", player, Config.Garden.TotalPlots, "Carrot")
        t.assertFalse(ok, "planting on a locked plot should fail")
        t.assertNotNil(message, "no reason given for a refused plant")
end)

t.test("planting with no coins is refused", function()
        local env = boot()
        local save = returningSave(env, 1, 1, "Carrot")
        Shim.putSave(env, 206, save)
        local player = Shim.joinPlayer(env, 206, "Broke")
        local ok, _, message = call(env, "GardenPlant", player, 2, "Carrot")
        t.assertFalse(ok, "an unaffordable plant should fail")
        t.assertNotNil(message, "no reason given")
end)

t.test("selling an empty basket is refused", function()
        local env = boot()
        local player = Shim.joinPlayer(env, 207, "Empty")
        local ok, _, message = call(env, "GardenSell", player)
        t.assertFalse(ok, "selling nothing should fail")
        t.assertNotNil(message, "no reason given")
end)

-- A full basket must not eat a crop. If the space check ran after the harvest
-- instead of before it, the crop would be lifted off the plot and then dropped,
-- and the player would have lost it for nothing.
t.test("a full basket refuses a harvest and leaves the crop in the ground", function()
        local env = boot()
        local Config = env.__load("shared/Config")
        local save = returningSave(env, 1000, 1, "Carrot")
        for _ = 1, Config.Basket.Capacity do
                table.insert(save.basket.entries, {
                        seedId = "Carrot", rarity = "Common", mutation = "None", value = 12,
                })
        end
        Shim.putSave(env, 215, save)
        local player = Shim.joinPlayer(env, 215, "FullBasket")

        local ok, _, message = call(env, "GardenHarvest", player, 1)
        t.assertFalse(ok, "harvesting into a full basket should fail")
        t.assertNotNil(message, "no reason given")

        local after = latestState(env, player)
        t.assertEqual(after.basket.count, Config.Basket.Capacity, "the basket overflowed")
        t.assertEqual(after.garden.plots[1].seedId, "Carrot",
                "the crop was destroyed instead of being left in the ground")
end)

t.test("harvest all keeps the crops that do not fit", function()
        local env = boot()
        local Config = env.__load("shared/Config")
        local save = returningSave(env, 1000, 1, "Carrot")
        -- One free slot, but three crops are ripe.
        for _ = 1, Config.Basket.Capacity - 1 do
                table.insert(save.basket.entries, {
                        seedId = "Carrot", rarity = "Common", mutation = "None", value = 12,
                })
        end
        for index = 2, 3 do
                save.garden.plots[index].seedId = "Carrot"
                save.garden.plots[index].plantedAt = os.time() - 7200
                save.garden.plots[index].readyAt = os.time() - 3600
        end
        Shim.putSave(env, 216, save)
        local player = Shim.joinPlayer(env, 216, "TightFit")

        call(env, "GardenHarvestAll", player)
        local after = latestState(env, player)
        t.assertEqual(after.basket.count, Config.Basket.Capacity, "the basket did not fill exactly")

        local stillGrowing = 0
        for index = 1, 4 do
                if after.garden.plots[index].seedId ~= nil then
                        stillGrowing += 1
                end
        end
        t.assertEqual(stillGrowing, 2, "crops that did not fit were destroyed instead of left ripe")
end)

t.test("a plot can be bought once it is affordable", function()
        local env = boot()
        local save = returningSave(env, 10000, 1, "Carrot")
        Shim.putSave(env, 208, save)
        local player = Shim.joinPlayer(env, 208, "Buyer")
        local before = latestState(env, player)

        local ok = call(env, "GardenBuyPlot", player)
        t.assertTrue(ok, "buying a plot failed with enough coins")

        local after = latestState(env, player)
        t.assertEqual(after.garden.unlocked, before.garden.unlocked + 1, "the plot was not unlocked")
        t.assertLess(after.coins, before.coins, "the plot was free")
end)

t.test("a plot is refused when it is not affordable", function()
        local env = boot()
        local player = Shim.joinPlayer(env, 209, "Poor")
        local ok, _, message = call(env, "GardenBuyPlot", player)
        t.assertFalse(ok, "a new player should not afford a plot")
        t.assertNotNil(message, "no reason given")
end)

t.test("an upgrade raises the level and charges for it", function()
        local env = boot()
        local save = returningSave(env, 5000, 1, "Carrot")
        Shim.putSave(env, 210, save)
        local player = Shim.joinPlayer(env, 210, "Upgrader")
        local before = latestState(env, player)

        local ok = call(env, "GardenBuyUpgrade", player, "speed")
        t.assertTrue(ok, "buying a speed upgrade failed")

        local after = latestState(env, player)
        t.assertEqual(after.upgrades.speedLevel, before.upgrades.speedLevel + 1, "speed level did not rise")
        t.assertLess(after.coins, before.coins, "the upgrade was free")
end)

t.test("an unknown upgrade kind is refused", function()
        local env = boot()
        local save = returningSave(env, 5000, 1, "Carrot")
        Shim.putSave(env, 211, save)
        local player = Shim.joinPlayer(env, 211, "Nonsense")
        local ok = call(env, "GardenBuyUpgrade", player, "makeMeRich")
        t.assertFalse(ok, "an unknown upgrade should be refused")
end)

t.test("an egg can be hatched and the pet shows in the state", function()
        local env = boot()
        local save = returningSave(env, 100000, 1, "Carrot")
        Shim.putSave(env, 212, save)
        local player = Shim.joinPlayer(env, 212, "Hatcher")
        local before = latestState(env, player)

        local eggId = before.eggs[1].id
        local ok, result = call(env, "GardenBuyEgg", player, eggId)
        t.assertTrue(ok, "hatching failed")
        t.assertNotNil(result.petId, "hatching produced no pet")

        local after = latestState(env, player)
        t.assertEqual(#after.pets.owned, 1, "the pet is not in the inventory")
        t.assertLess(after.coins, before.coins, "the egg was free")
end)

t.test("a hatched pet can be equipped", function()
        local env = boot()
        local save = returningSave(env, 100000, 1, "Carrot")
        Shim.putSave(env, 213, save)
        local player = Shim.joinPlayer(env, 213, "PetOwner")
        local before = latestState(env, player)
        call(env, "GardenBuyEgg", player, before.eggs[1].id)
        local withPet = latestState(env, player)

        local uid = withPet.pets.owned[1].uid
        local ok = call(env, "GardenEquipPet", player, uid)
        t.assertTrue(ok, "equipping failed")

        local after = latestState(env, player)
        t.assertEqual(#after.pets.equipped, 1, "the pet was not equipped")
        t.assertEqual(after.pets.equipped[1], uid, "the wrong pet was equipped")
end)

t.test("the shop can be restocked", function()
        local env = boot()
        local player = Shim.joinPlayer(env, 214, "Restocker")
        local ok, payload = call(env, "GardenRestock", player)
        t.assertTrue(ok, "restock failed")
        t.assertNotNil(payload, "restock returned no stock")
        t.assertEqual(#payload.stock, 6, "restock size")
end)

--------------------------------------------------------------------------
t.suite("Garden runtime: the client boots and draws")
--------------------------------------------------------------------------

t.test("the client loads and builds its HUD", function()
        local env = boot()
        local ok, err = pcall(function()
                env.__load("client/init.client")
        end)
        t.assertTrue(ok, "the client failed to load: " .. tostring(err))
        local gui = env.__player.PlayerGui:FindFirstChild("AXGardenHud")
        t.assertTrue(gui ~= nil, "the client built no HUD")
end)

t.test("a real state payload renders without error", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player

        local payload = joinAndCapture(env, 301, "Viewer")
        t.assertTrue(payload ~= nil, "no payload to render")
        if not payload then
                return
        end

        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        local ok, err = pcall(function()
                State:FireClient(clientPlayer, payload)
        end)
        t.assertTrue(ok, "rendering the payload threw: " .. tostring(err))

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        local top = gui:FindFirstChild("TopBar")
        t.assertTrue(top ~= nil, "no top bar")
        local coins = top and top:FindFirstChild("Coins")
        t.assertTrue(coins ~= nil, "no coin label")
        t.assertContains(coins.Text, tostring(payload.coins), "the coin label shows the wrong number")
end)

t.test("every plot on the client is a tap target of a usable size", function()
        local env = boot()
        local Config = env.__load("shared/Config")
        local HudLayout = env.__load("client/HudLayout")
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 302, "Sizer")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        for index = 1, Config.Garden.TotalPlots do
                local plot = gui:FindFirstChild("Plot" .. tostring(index))
                t.assertTrue(plot ~= nil, "plot " .. index .. " is not on screen")
                if plot then
                        local size = plot.AbsoluteSize
                        t.assertTrue(size.X >= HudLayout.MIN_TOUCH and size.Y >= HudLayout.MIN_TOUCH,
                                "plot " .. index .. " is smaller than a finger: " .. tostring(size.X) .. "x" .. tostring(size.Y))
                end
        end
end)

t.test("tapping an empty plot asks the server to plant", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 303, "Tapper")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        local plot = gui:FindFirstChild("Plot1")
        t.assertTrue(plot ~= nil, "no plot button on screen")
        if not plot then
                return
        end

        local Plant = env.__replicatedRemotes:FindFirstChild("GardenPlant")
        plot.Activated:Fire()
        t.assertTrue(Plant.invokedWith ~= nil, "tapping a plot asked the server for nothing")
        t.assertEqual(Plant.invokedWith[1], 1, "the tap asked to plant the wrong plot")
end)

t.test("tapping a ripe plot asks the server to harvest", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local save = returningSave(env, 1000, 1, "Carrot")
        Shim.putSave(env, 304, save)
        local captured = nil
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State.OnClientEvent:Connect(function(payload) captured = payload end)
        Shim.joinPlayer(env, 304, "HarvestTapper")
        State:FireClient(clientPlayer, captured)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        local Harvest = env.__replicatedRemotes:FindFirstChild("GardenHarvest")
        gui:FindFirstChild("Plot1").Activated:Fire()
        t.assertTrue(Harvest.invokedWith ~= nil, "tapping a ripe plot did not ask to harvest")
end)

t.test("the bottom bar has all five buttons at a usable size", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 305, "BarTester")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        local bar = gui:FindFirstChild("BottomBar")
        t.assertTrue(bar ~= nil, "no bottom bar")
        for _, name in ipairs({ "Shop", "Pets", "Collection", "Upgrades", "Sell" }) do
                local button = bar:FindFirstChild(name)
                t.assertTrue(button ~= nil, "bottom bar is missing " .. name)
                if button then
                        local size = button.AbsoluteSize
                        t.assertTrue(size.X >= 44 and size.Y >= 44,
                                name .. " is smaller than a finger: " .. tostring(size.X) .. "x" .. tostring(size.Y))
                end
        end
end)

t.test("the sell button cashes the basket", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 306, "Seller")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        local Sell = env.__replicatedRemotes:FindFirstChild("GardenSell")
        gui:FindFirstChild("BottomBar"):FindFirstChild("Sell").Activated:Fire()
        t.assertTrue(Sell.invokedWith ~= nil, "the sell button asked the server for nothing")
end)

t.test("tapping the shop button opens a panel with the stock in it", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 307, "Shopper")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        gui:FindFirstChild("BottomBar"):FindFirstChild("Shop").Activated:Fire()

        local panel = gui:FindFirstChild("Panel")
        t.assertTrue(panel.Visible, "the shop panel did not open")
        local list = panel:FindFirstChild("List")
        t.assertGreater(#list:GetChildren(), 0, "the shop panel is empty")
end)

t.test("closing the panel hides it", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 308, "Closer")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        gui:FindFirstChild("BottomBar"):FindFirstChild("Shop").Activated:Fire()
        local panel = gui:FindFirstChild("Panel")
        t.assertTrue(panel.Visible, "panel did not open")
        panel:FindFirstChild("Close").Activated:Fire()
        t.assertFalse(panel.Visible, "the close button left the panel open")
end)

t.test("every screen in the bottom bar opens a panel that is not empty", function()
        local env = boot()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 309, "Tabber")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        local panel = gui:FindFirstChild("Panel")
        for _, name in ipairs({ "Shop", "Pets", "Collection", "Upgrades" }) do
                gui:FindFirstChild("BottomBar"):FindFirstChild(name).Activated:Fire()
                t.assertTrue(panel.Visible, name .. " opened nothing")
                local list = panel:FindFirstChild("List")
                t.assertGreater(#list:GetChildren(), 0, name .. " drew an empty panel")
        end
end)

-- The layout must fit a phone, which is the only device K has. The previous
-- game's HUD ran off the top of a 360x640 screen.
t.test("the HUD fits the smallest phone without leaving the screen", function()
        local env = Shim.harness(Sources)
        -- The phone size is set before the server and client load, because the
        -- client builds its HUD once from the viewport it sees at load.
        Shim.setViewport(env, 360, 640)
        env.__load("server/init.server")
        env.__drain()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 310, "Phone")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        for _, name in ipairs({ "TopBar", "BottomBar" }) do
                local node = gui:FindFirstChild(name)
                t.assertTrue(node ~= nil, name .. " is missing on a small screen")
                if node then
                        local pos = node.Position
                        local size = node.AbsoluteSize
                        t.assertTrue(pos.X.Offset >= 0 and pos.Y.Offset >= 0,
                                name .. " starts off screen at " .. pos.X.Offset .. "," .. pos.Y.Offset)
                        t.assertTrue(pos.X.Offset + size.X <= 360,
                                name .. " runs off the right edge")
                        t.assertTrue(pos.Y.Offset + size.Y <= 640,
                                name .. " runs off the bottom edge")
                end
        end
end)

-- The plot grid must also fit. Twelve plots in four columns is three rows, and
-- on a 360px screen the third row must not collide with the bottom bar.
t.test("the plot grid fits a phone above the bottom bar", function()
        local env = Shim.harness(Sources)
        Shim.setViewport(env, 360, 640)
        env.__load("server/init.server")
        env.__drain()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 311, "Phone")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        local bar = gui:FindFirstChild("BottomBar")
        local barTop = bar.Position.Y.Offset
        for index = 1, 12 do
                local plot = gui:FindFirstChild("Plot" .. tostring(index))
                t.assertTrue(plot ~= nil, "plot " .. index .. " is missing on a phone")
                if plot then
                        local bottom = plot.Position.Y.Offset + plot.AbsoluteSize.Y
                        t.assertTrue(bottom <= barTop,
                                "plot " .. index .. " overlaps the bottom bar")
                        t.assertTrue(plot.Position.X.Offset + plot.AbsoluteSize.X <= 360,
                                "plot " .. index .. " runs off the right edge")
                end
        end
end)

-- The panel is the one piece of the HUD drawn at a fixed offset rather than
-- derived from the bars, so it is the piece that can silently overlap them. On a
-- phone the panel must start below the top bar and end above the bottom bar, or
-- the player cannot read their coins or reach the way out.
t.test("an open panel clears both bars on a phone", function()
        local env = Shim.harness(Sources)
        Shim.setViewport(env, 360, 640)
        env.__load("server/init.server")
        env.__drain()
        env.__load("client/init.client")
        local clientPlayer = env.__player
        local payload = joinAndCapture(env, 312, "Phone")
        local State = env.__replicatedRemotes:FindFirstChild("GardenState")
        State:FireClient(clientPlayer, payload)

        local gui = clientPlayer.PlayerGui:FindFirstChild("AXGardenHud")
        gui:FindFirstChild("BottomBar"):FindFirstChild("Shop").Activated:Fire()

        local panel = gui:FindFirstChild("Panel")
        t.assertTrue(panel.Visible, "the panel did not open on a phone")

        local top = gui:FindFirstChild("TopBar")
        local bottom = gui:FindFirstChild("BottomBar")
        local topBottom = top.Position.Y.Offset + top.AbsoluteSize.Y
        local panelTop = panel.Position.Y.Offset
        local panelBottom = panelTop + panel.AbsoluteSize.Y

        t.assertTrue(panelTop >= topBottom,
                "the panel overlaps the top bar: panel starts at " .. panelTop .. ", bar ends at " .. topBottom)
        t.assertTrue(panelBottom <= bottom.Position.Y.Offset,
                "the panel overlaps the bottom bar: panel ends at " .. panelBottom .. ", bar starts at " .. bottom.Position.Y.Offset)
end)

t.finish()

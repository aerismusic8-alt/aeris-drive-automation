--!strict
-- AX Garden Legends shared-logic test suite.
--   luau roblox-garden/tests/run.luau
--
-- Everything here runs the real modules under the standalone Luau CLI. There is
-- no Roblox shim in this suite on purpose: the garden loop is pure arithmetic on
-- a timestamp, and if any of it needed an engine to be tested, the loop would be
-- in the wrong module.

local t = require("./TestRunner")

local Config = require("../src/shared/Config")
local Random = require("../src/shared/Random")
local Rarity = require("../src/shared/Rarity")
local Seeds = require("../src/shared/Seeds")
local Mutations = require("../src/shared/Mutations")
local Pets = require("../src/shared/Pets")
local Garden = require("../src/shared/Garden")
local Sell = require("../src/shared/Sell")
local Collection = require("../src/shared/Collection")
local Basket = require("../src/shared/Basket")
local SaveSchema = require("../src/shared/SaveSchema")
local Remotes = require("../src/shared/Remotes")
local Text = require("../src/shared/Text")
local HudLayout = require("../src/client/HudLayout")

--------------------------------------------------------------------------
t.suite("Rarity")
--------------------------------------------------------------------------

t.test("has seven tiers in a fixed order", function()
        t.assertEqual(#Rarity.list(), 7, "tier count")
        t.assertEqual(Rarity.ids()[1], "Common", "weakest tier")
        t.assertEqual(Rarity.ids()[7], "Divine", "strongest tier")
end)

t.test("rank rises with tier strength", function()
        local previous = 0
        for _, id in ipairs(Rarity.ids()) do
                local rank = Rarity.rank(id)
                t.assertGreater(rank, previous, "rank of " .. id)
                previous = rank
        end
end)

t.test("value multiplier rises with tier strength", function()
        local previous = 0
        for _, def in ipairs(Rarity.list()) do
                t.assertGreater(def.valueMultiplier, previous, def.id .. " multiplier")
                previous = def.valueMultiplier
        end
end)

-- Every tier must be reachable from the seed pool, or a player can never
-- complete the collection and the top tiers are decoration.
t.test("every tier has at least one seed", function()
        for _, id in ipairs(Rarity.ids()) do
                t.assertGreater(#Seeds.byRarity(id), 0, "seeds of tier " .. id)
        end
end)

t.test("an unknown tier sells for face value rather than erroring", function()
        t.assertEqual(Rarity.valueMultiplier("NotATier"), 1, "unknown multiplier")
end)

--------------------------------------------------------------------------
t.suite("Seeds")
--------------------------------------------------------------------------

t.test("every seed id is unique", function()
        local seen: { [string]: boolean } = {}
        for _, seed in ipairs(Seeds.list()) do
                t.assertFalse(seen[seed.id] == true, "duplicate seed id " .. seed.id)
                seen[seed.id] = true
        end
end)

t.test("every seed names a tier that exists", function()
        for _, seed in ipairs(Seeds.list()) do
                t.assertNotNil(Rarity.get(seed.rarity), seed.id .. " names tier " .. seed.rarity)
        end
end)

-- The catalogue is the progression. A later seed that pays less than an earlier
-- one, or ripens sooner, would make the shop's ordering a lie.
t.test("payout rises with rarity across the catalogue", function()
        local best: { [string]: number } = {}
        for _, seed in ipairs(Seeds.list()) do
                local rank = Rarity.rank(seed.rarity)
                for tierRank = 1, rank - 1 do
                        local weaker = Rarity.ids()[tierRank]
                        if best[weaker] then
                                t.assertGreater(seed.baseValue, best[weaker],
                                        seed.id .. " pays more than every " .. weaker)
                        end
                end
                if not best[seed.rarity] or seed.baseValue > best[seed.rarity] then
                        best[seed.rarity] = seed.baseValue
                end
        end
end)

t.test("a better seed costs more patience", function()
        local previous = 0
        for _, seed in ipairs(Seeds.list()) do
                t.assertGreater(seed.growSeconds, previous, seed.id .. " grow time")
                previous = seed.growSeconds
        end
end)

t.test("cost is positive and rises with payout", function()
        local previous = 0
        for _, seed in ipairs(Seeds.list()) do
                local cost = Seeds.cost(seed.id)
                t.assertGreater(cost, 0, seed.id .. " cost")
                t.assertGreater(cost, previous, seed.id .. " cost vs previous")
                previous = cost
        end
end)

t.test("an unknown seed is unbuyable rather than free", function()
        t.assertEqual(Seeds.cost("NotASeed"), math.huge, "unknown seed cost")
end)

-- The shop must never stock the same seed twice, or a player pays for a slot
-- showing a duplicate.
t.test("shop stock has no duplicates", function()
        local rng = Random.new(2024)
        for _ = 1, 200 do
                local stock = Seeds.rollStock(rng, 6)
                local seen: { [string]: boolean } = {}
                for _, id in ipairs(stock) do
                        t.assertFalse(seen[id] == true, "duplicate in stock: " .. id)
                        seen[id] = true
                end
        end
end)

t.test("shop stock is the size asked for", function()
        local rng = Random.new(7)
        for _ = 1, 50 do
                t.assertEqual(#Seeds.rollStock(rng, 6), 6, "stock size")
        end
end)

-- Asking for more than exists must terminate and return what there is, not spin.
t.test("asking for more stock than exists returns the whole pool", function()
        local rng = Random.new(11)
        local stock = Seeds.rollStock(rng, 999)
        t.assertEqual(#stock, #Seeds.list(), "whole pool")
end)

-- The cheap end of the shop must dominate, or a new player can never afford
-- their second seed and the loop stalls at the first plant.
t.test("common seeds appear far more often than divine ones", function()
        local common = Seeds.appearanceOdds("Carrot")
        local divine = Seeds.appearanceOdds("OmegaLily")
        t.assertGreater(common, divine * 100, "common vs divine odds")
end)

t.test("appearance odds over the pool sum to one", function()
        local total = 0
        for _, seed in ipairs(Seeds.list()) do
                total += Seeds.appearanceOdds(seed.id)
        end
        t.assertNear(total, 1, 0.0001, "odds sum")
end)

-- Upgrades must speed growth up without ever reaching zero, or the waiting --
-- the thing the game is made of -- disappears.
t.test("growth multiplier never makes a crop instant", function()
        t.assertGreater(Seeds.growSeconds("Carrot", 1), 0, "base grow time")
        t.assertGreater(Seeds.growSeconds("Carrot", 1000), 0, "grow time at absurd speed")
        t.assertGreater(Seeds.growSeconds("Carrot", 1000), 0.99, "grow time floor")
end)

t.test("a bigger multiplier ripens a crop sooner", function()
        local slow = Seeds.growSeconds("Carrot", 1)
        local fast = Seeds.growSeconds("Carrot", 2)
        t.assertLess(fast, slow, "speed upgrade shortens grow time")
end)

--------------------------------------------------------------------------
t.suite("Mutations")
--------------------------------------------------------------------------

t.test("the ordinary result exists and is worth face value", function()
        t.assertEqual(Mutations.multiplier("None"), 1, "no-mutation multiplier")
end)

t.test("better mutations are rarer", function()
        local previous = math.huge
        -- Skip None: it is the baseline, not a reward.
        for _, def in ipairs(Mutations.list()) do
                if def.id ~= "None" then
                        t.assertLess(def.weight, previous, def.id .. " weight")
                        previous = def.weight
                end
        end
end)

t.test("multiplier rises as the mutation gets rarer", function()
        local previous = 1
        for _, def in ipairs(Mutations.list()) do
                if def.id ~= "None" then
                        t.assertGreater(def.multiplier, previous, def.id .. " multiplier")
                        previous = def.multiplier
                end
        end
end)

t.test("chances sum to one", function()
        local total = 0
        for _, def in ipairs(Mutations.list()) do
                total += Mutations.chance(def.id)
        end
        t.assertNear(total, 1, 0.0001, "mutation chances")
end)

-- The headline number of the game. A Cosmic must be a story, not a Tuesday.
t.test("the rarest mutation is far rarer than an ordinary harvest", function()
        local ordinary = Mutations.chance("None")
        local cosmic = Mutations.chance("Cosmic")
        t.assertGreater(ordinary, cosmic * 500, "ordinary vs cosmic")
end)

t.test("rolling always returns a known mutation", function()
        local rng = Random.new(4242)
        for _ = 1, 2000 do
                local id = Mutations.roll(rng, 1)
                t.assertNotNil(Mutations.get(id), "rolled " .. tostring(id))
        end
end)

-- Over enough rolls the ordinary result must dominate, or the game is a slot
-- machine that pays out every pull and the rare ones stop meaning anything.
t.test("ordinary harvests dominate a large sample", function()
        local rng = Random.new(99)
        local ordinary = 0
        local rolls = 5000
        for _ = 1, rolls do
                if Mutations.roll(rng, 1) == "None" then
                        ordinary += 1
                end
        end
        t.assertGreater(ordinary / rolls, 0.55, "share of ordinary harvests")
end)

t.test("every mutation is reachable in a large sample", function()
        local rng = Random.new(31337)
        local seen: { [string]: boolean } = {}
        for _ = 1, 20000 do
                seen[Mutations.roll(rng, 1)] = true
        end
        for _, def in ipairs(Mutations.list()) do
                t.assertTrue(seen[def.id] == true, "never rolled: " .. def.id)
        end
end)

t.test("luck raises the share of mutated harvests", function()
        local plain = Random.new(5)
        local lucky = Random.new(5)
        local plainMutated = 0
        local luckyMutated = 0
        local rolls = 4000
        for _ = 1, rolls do
                if Mutations.roll(plain, 1) ~= "None" then
                        plainMutated += 1
                end
                if Mutations.roll(lucky, 8) ~= "None" then
                        luckyMutated += 1
                end
        end
        t.assertGreater(luckyMutated, plainMutated, "luck raises mutation rate")
end)

t.test("zero luck is treated as no bonus, not as a penalty", function()
        local rng = Random.new(6)
        for _ = 1, 200 do
                t.assertNotNil(Mutations.get(Mutations.roll(rng, 0)), "roll at zero luck")
        end
end)

--------------------------------------------------------------------------
t.suite("Garden")
--------------------------------------------------------------------------

local function plantAt(state: any, index: number, seedId: string, now: number, speed: number?)
        return Garden.plant(state, index, seedId, now, speed)
end

t.test("a new garden starts partly unlocked and empty", function()
        local state = Garden.new()
        t.assertEqual(state.unlocked, Config.Garden.StartingPlots, "starting plots")
        t.assertEqual(Garden.plantedCount(state), 0, "nothing planted")
        t.assertEqual(Garden.readyCount(state, 0), 0, "nothing ready")
end)

t.test("planting fills a plot and schedules its ripening", function()
        local state = Garden.new()
        local ok, reason = plantAt(state, 1, "Carrot", 1000)
        t.assertTrue(ok, "plant failed: " .. tostring(reason))
        local plot = Garden.getPlot(state, 1) :: any
        t.assertEqual(plot.seedId, "Carrot", "planted seed")
        t.assertEqual(plot.plantedAt, 1000, "planted time")
        t.assertEqual(plot.readyAt, 1000 + Seeds.growSeconds("Carrot", 1), "ready time")
end)

t.test("a plot cannot be double-planted", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 0)
        local ok, reason = plantAt(state, 1, "Carrot", 0)
        t.assertFalse(ok, "second plant should fail")
        t.assertEqual(reason, "PLOT_OCCUPIED", "reason")
end)

t.test("a locked plot cannot be planted", function()
        local state = Garden.new()
        local ok, reason = plantAt(state, Config.Garden.StartingPlots + 1, "Carrot", 0)
        t.assertFalse(ok, "plant on locked plot should fail")
        t.assertEqual(reason, "PLOT_LOCKED", "reason")
end)

t.test("a plot out of range is rejected", function()
        local state = Garden.new()
        t.assertEqual(select(2, Garden.plant(state, 0, "Carrot", 0)), "NO_SUCH_PLOT", "index 0")
        t.assertEqual(select(2, Garden.plant(state, 999, "Carrot", 0)), "NO_SUCH_PLOT", "index 999")
end)

t.test("an unknown seed is rejected", function()
        local state = Garden.new()
        t.assertEqual(select(2, Garden.plant(state, 1, "NotASeed", 0)), "NO_SUCH_SEED", "unknown seed")
end)

t.test("an empty seed id is rejected", function()
        local state = Garden.new()
        t.assertEqual(select(2, Garden.plant(state, 1, "", 0)), "NO_SEED", "empty seed")
        t.assertEqual(select(2, Garden.plant(state, 1, nil, 0)), "NO_SEED", "nil seed")
end)

t.test("a crop is not ready before its time", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 0)
        local plot = Garden.getPlot(state, 1) :: any
        t.assertFalse(Garden.isReady(plot, 5), "ready too early")
        t.assertTrue(Garden.isReady(plot, Seeds.growSeconds("Carrot", 1)), "ready on time")
end)

t.test("harvesting an unripe crop is refused", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 0)
        local rng = Random.new(1)
        local reward, reason = Garden.harvest(state, 1, 1, rng)
        t.assertNil(reward, "early harvest should fail")
        t.assertEqual(reason, "NOT_READY", "reason")
end)

t.test("harvesting an empty plot is refused", function()
        local state = Garden.new()
        local reward, reason = Garden.harvest(state, 1, 1000, Random.new(1))
        t.assertNil(reward, "empty harvest should fail")
        t.assertEqual(reason, "PLOT_EMPTY", "reason")
end)

t.test("a harvest returns the seed and clears the plot", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 0)
        local readyAt = (Garden.getPlot(state, 1) :: any).readyAt
        local reward = Garden.harvest(state, 1, readyAt, Random.new(1))
        t.assertNotNil(reward, "harvest returned nothing")
        t.assertEqual((reward :: any).seedId, "Carrot", "harvested seed")
        t.assertTrue(Garden.isEmpty(Garden.getPlot(state, 1) :: any), "plot should be clear")
        t.assertEqual(Garden.plantedCount(state), 0, "planted count after harvest")
end)

t.test("a harvest always carries a mutation id", function()
        local rng = Random.new(77)
        for i = 1, 100 do
                local state = Garden.new()
                plantAt(state, 1, "Carrot", 0)
                local readyAt = (Garden.getPlot(state, 1) :: any).readyAt
                local reward = Garden.harvest(state, 1, readyAt, rng) :: any
                t.assertNotNil(reward.mutation, "harvest " .. i .. " had no mutation id")
                t.assertNotNil(Mutations.get(reward.mutation), "harvest " .. i .. " mutation is unknown")
        end
end)

t.test("harvestAll pays every ripe plot and leaves the rest", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 0)
        plantAt(state, 2, "Carrot", 0)
        plantAt(state, 3, "OmegaLily", 0)
        local rewards, count = Garden.harvestAll(state, 10, Random.new(3))
        t.assertEqual(count, 2, "ripe plots harvested")
        t.assertEqual(#rewards, 2, "rewards returned")
        t.assertEqual(Garden.plantedCount(state), 1, "the slow crop is untouched")
end)

t.test("progress runs from zero to one", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 0)
        local plot = Garden.getPlot(state, 1) :: any
        t.assertNear(Garden.progress(plot, 0), 0, 0.001, "progress at plant time")
        t.assertNear(Garden.progress(plot, plot.readyAt / 2), 0.5, 0.001, "progress halfway")
        t.assertNear(Garden.progress(plot, plot.readyAt), 1, 0.001, "progress when ripe")
        t.assertNear(Garden.progress(plot, plot.readyAt * 10), 1, 0.001, "progress never exceeds one")
end)

t.test("an empty plot reads as zero progress", function()
        local state = Garden.new()
        t.assertNear(Garden.progress(Garden.getPlot(state, 1) :: any, 999), 0, 0.001, "empty progress")
end)

-- The headline feature: a crop must ripen across a gap when the player was not
-- connected. Time is a parameter, so this is the whole offline system.
t.test("a crop ripens while the player is away", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 1000)
        -- The player left at 1000 and returned eight hours later.
        local returned = 1000 + 8 * 60 * 60
        t.assertTrue(Garden.isReady(Garden.getPlot(state, 1) :: any, returned), "crop should have ripened offline")
end)

t.test("a crop planted for a long grow time is still growing offline", function()
        local state = Garden.new()
        plantAt(state, 1, "OmegaLily", 0)
        local oneHour = 3600
        t.assertFalse(Garden.isReady(Garden.getPlot(state, 1) :: any, oneHour), "divine seed should still be growing")
        t.assertTrue(Garden.isReady(Garden.getPlot(state, 1) :: any, 20000), "divine seed should ripen eventually")
end)

t.test("the snapshot covers every plot", function()
        local state = Garden.new()
        local snapshot = Garden.snapshot(state, 0)
        t.assertEqual(#snapshot.plots, Config.Garden.TotalPlots, "plot count in snapshot")
        t.assertEqual(snapshot.unlocked, Config.Garden.StartingPlots, "unlocked in snapshot")
end)

t.test("the snapshot reports what is ready", function()
        local state = Garden.new()
        plantAt(state, 1, "Carrot", 0)
        local readyAt = (Garden.getPlot(state, 1) :: any).readyAt
        t.assertEqual(Garden.snapshot(state, readyAt).ready, 1, "ready count in snapshot")
        t.assertEqual(Garden.snapshot(state, 0).ready, 0, "nothing ready at plant time")
end)

--------------------------------------------------------------------------
t.suite("Sell")
--------------------------------------------------------------------------

t.test("a common crop with no mutation sells for its base value", function()
        local upgrades = Sell.newUpgrades()
        local reward = { seedId = "Carrot", rarity = "Common", mutation = "None" }
        t.assertEqual(Sell.value(reward, upgrades, { growth = 1, value = 1 }), 12, "base sale")
end)

t.test("a higher tier is worth more", function()
        local upgrades = Sell.newUpgrades()
        local pets = { growth = 1, value = 1 }
        local common = Sell.value({ seedId = "Carrot", rarity = "Common", mutation = "None" }, upgrades, pets)
        local rare = Sell.value({ seedId = "Dragonfruit", rarity = "Rare", mutation = "None" }, upgrades, pets)
        t.assertGreater(rare, common * 10, "rare vs common")
end)

t.test("the mutation multiplies the sale", function()
        local upgrades = Sell.newUpgrades()
        local pets = { growth = 1, value = 1 }
        local plain = Sell.value({ seedId = "Carrot", rarity = "Common", mutation = "None" }, upgrades, pets)
        local cosmic = Sell.value({ seedId = "Carrot", rarity = "Common", mutation = "Cosmic" }, upgrades, pets)
        t.assertEqual(cosmic, plain * 240, "cosmic multiplier")
end)

t.test("the breakdown multiplies out to the total", function()
        local upgrades = { speedLevel = 3, valueLevel = 4 }
        local pets = { growth = 1.5, value = 2 }
        local breakdown = Sell.breakdown({ seedId = "Starfruit", rarity = "Rare", mutation = "Gold" }, upgrades, pets)
        local product = breakdown.base * breakdown.rarity * breakdown.mutation * breakdown.upgrade * breakdown.pet
        t.assertNear(breakdown.total, math.floor(product), 1, "breakdown product")
end)

t.test("an unknown seed sells for nothing rather than erroring", function()
        local upgrades = Sell.newUpgrades()
        t.assertEqual(Sell.value({ seedId = "Nope", rarity = "Common", mutation = "None" }, upgrades, nil), 0, "unknown seed")
end)

t.test("a sale never rounds down to zero", function()
        local upgrades = Sell.newUpgrades()
        t.assertGreater(Sell.value({ seedId = "Carrot", rarity = "Common", mutation = "None" }, upgrades, { growth = 0.001, value = 0.001 }), 0, "floor")
end)

-- Upgrades must be worth buying, or the coin sink is a trap.
t.test("the value upgrade raises the sale", function()
        local pets = { growth = 1, value = 1 }
        local reward = { seedId = "Carrot", rarity = "Common", mutation = "None" }
        local plain = Sell.value(reward, { speedLevel = 0, valueLevel = 0 }, pets)
        local upgraded = Sell.value(reward, { speedLevel = 0, valueLevel = 5 }, pets)
        t.assertGreater(upgraded, plain, "value upgrade should pay more")
end)

t.test("the speed upgrade shortens growth", function()
        local slow = Sell.growthMultiplier({ speedLevel = 0, valueLevel = 0 }, { growth = 1 })
        local fast = Sell.growthMultiplier({ speedLevel = 5, valueLevel = 0 }, { growth = 1 })
        t.assertGreater(fast, slow, "speed upgrade multiplier")
end)

t.test("upgrade levels are capped", function()
        local over = { speedLevel = 9999, valueLevel = 9999 }
        t.assertNear(Sell.speedMultiplier(over), 1 + Config.Upgrades.SpeedMaxLevel * Config.Upgrades.SpeedPerLevel, 0.0001, "speed cap")
        t.assertNear(Sell.valueMultiplier(over), 1 + Config.Upgrades.ValueMaxLevel * Config.Upgrades.ValuePerLevel, 0.0001, "value cap")
end)

t.test("upgrade costs rise with level", function()
        for _, kind in ipairs({ "speed", "value" }) do
                local previous = 0
                for level = 0, 10 do
                        local cost = Sell.upgradeCost(kind, level)
                        t.assertGreater(cost, previous, kind .. " cost at level " .. level)
                        previous = cost
                end
        end
end)

t.test("a maxed upgrade cannot be bought again", function()
        local upgrades = { speedLevel = Config.Upgrades.SpeedMaxLevel, valueLevel = 0 }
        local coins, reason = Sell.buyUpgrade(1e12, upgrades, "speed")
        t.assertNil(coins, "maxed upgrade should refuse")
        t.assertEqual(reason, "MAX_LEVEL", "reason")
end)

t.test("an upgrade cannot be bought without the coins", function()
        local upgrades = Sell.newUpgrades()
        local coins, reason = Sell.buyUpgrade(0, upgrades, "speed")
        t.assertNil(coins, "purchase without coins should fail")
        t.assertEqual(reason, "NOT_ENOUGH_COINS", "reason")
        t.assertEqual(upgrades.speedLevel, 0, "level unchanged")
end)

t.test("buying an upgrade charges the cost and raises the level", function()
        local upgrades = Sell.newUpgrades()
        local cost = Sell.upgradeCost("value", 0)
        local coins, reason = Sell.buyUpgrade(cost + 100, upgrades, "value")
        t.assertNil(reason, "purchase failed: " .. tostring(reason))
        t.assertEqual(coins, 100, "coins left")
        t.assertEqual(upgrades.valueLevel, 1, "level after purchase")
end)

t.test("an unknown upgrade is rejected", function()
        t.assertEqual(select(2, Sell.buyUpgrade(1e9, Sell.newUpgrades(), "nonsense")), "NO_SUCH_UPGRADE", "reason")
end)

t.test("plot costs rise as plots are bought", function()
        local previous = 0
        for unlocked = Config.Garden.StartingPlots, Config.Garden.TotalPlots - 1 do
                local cost = Sell.plotCost(unlocked)
                t.assertGreater(cost, previous, "plot cost at " .. unlocked)
                previous = cost
        end
end)

t.test("a plot cannot be bought with too few coins", function()
        local state = Garden.new()
        local coins, reason = Sell.buyPlot(0, state)
        t.assertNil(coins, "plot purchase should fail")
        t.assertEqual(reason, "NOT_ENOUGH_COINS", "reason")
        t.assertEqual(state.unlocked, Config.Garden.StartingPlots, "unlocked unchanged")
end)

t.test("a plot cannot be bought past the last one", function()
        local state = Garden.new()
        state.unlocked = Config.Garden.TotalPlots
        local coins, reason = Sell.buyPlot(1e12, state)
        t.assertNil(coins, "over-buying should fail")
        t.assertEqual(reason, "ALL_UNLOCKED", "reason")
        t.assertEqual(state.unlocked, Config.Garden.TotalPlots, "unlocked unchanged")
end)

-- Offline time is the retention mechanic, so its clamp is load-bearing: an
-- uncapped window would make one long absence worth more than weeks of play.
t.test("offline time is capped", function()
        local lastSeen = 0
        local week = 7 * 24 * 60 * 60
        t.assertEqual(Sell.offlineSeconds(lastSeen, week), Config.Offline.MaxOfflineSeconds, "capped offline window")
end)

t.test("a short absence is not treated as offline growth", function()
        t.assertEqual(Sell.offlineSeconds(100, 101), 0, "one second")
        t.assertEqual(Sell.offlineSeconds(100, 100 + Config.Offline.MinimumSeconds - 1), 0, "just under the floor")
end)

t.test("a backwards clock does not un-ripen the garden", function()
        t.assertEqual(Sell.offlineSeconds(1000, 500), 0, "negative elapsed")
end)

t.test("a normal absence passes through unchanged", function()
        t.assertEqual(Sell.offlineSeconds(0, 600), 600, "ten minutes")
end)

--------------------------------------------------------------------------
t.suite("Pets")
--------------------------------------------------------------------------

t.test("every pet names a tier that exists", function()
        for _, pet in ipairs(Pets.list()) do
                t.assertNotNil(Rarity.get(pet.rarity), pet.id .. " names " .. pet.rarity)
        end
end)

t.test("every egg tier it lists has at least one pet", function()
        for _, egg in ipairs(Pets.eggs()) do
                for rarityId, weight in pairs(egg.odds) do
                        if weight > 0 then
                                t.assertGreater(#Pets.byRarity(rarityId), 0, egg.id .. " lists empty tier " .. rarityId)
                        end
                end
        end
end)

t.test("a new inventory is empty", function()
        local inv = Pets.new()
        t.assertEqual(#inv.owned, 0, "owned")
        t.assertEqual(#inv.equipped, 0, "equipped")
        t.assertEqual(inv.hatches, 0, "hatches")
end)

t.test("an unknown egg cannot be hatched", function()
        local petId, reason = Pets.hatch(Pets.new(), "NotAnEgg", Random.new(1))
        t.assertNil(petId, "unknown egg")
        t.assertEqual(reason, "NO_SUCH_EGG", "reason")
end)

t.test("hatching adds exactly one pet with a fresh uid", function()
        local inv = Pets.new()
        local rng = Random.new(5)
        for i = 1, 50 do
                local petId, reason = Pets.hatch(inv, "Basic", rng)
                t.assertNil(reason, "hatch failed: " .. tostring(reason))
                t.assertNotNil(Pets.get(petId :: string), "unknown pet hatched")
                t.assertEqual(inv.owned[i].uid, i, "uid sequence")
        end
        t.assertEqual(#inv.owned, 50, "owned count")
        t.assertEqual(inv.hatches, 50, "hatch count")
end)

t.test("a cheap egg never drops a tier it does not list", function()
        local inv = Pets.new()
        local rng = Random.new(31337)
        for _ = 1, 3000 do
                Pets.hatch(inv, "Basic", rng)
        end
        for _, entry in ipairs(inv.owned) do
                local def = Pets.get(entry.petId) :: any
                t.assertTrue(def.rarity == "Common" or def.rarity == "Uncommon",
                        "Basic egg dropped " .. def.rarity)
        end
end)

t.test("every tier an egg lists is reachable", function()
        local inv = Pets.new()
        local rng = Random.new(20240)
        for _ = 1, 4000 do
                Pets.hatch(inv, "Divine", rng)
        end
        local seen: { [string]: boolean } = {}
        for _, entry in ipairs(inv.owned) do
                seen[(Pets.get(entry.petId) :: any).rarity] = true
        end
        for _, rarityId in ipairs({ "Epic", "Legendary", "Mythic" }) do
                t.assertTrue(seen[rarityId] == true, "Divine egg never gave " .. rarityId)
        end
end)

t.test("egg odds sum to one", function()
        for _, egg in ipairs(Pets.eggs()) do
                local total = 0
                for _, entry in ipairs(Pets.eggOdds(egg.id)) do
                        total += entry.chance
                end
                t.assertNear(total, 1, 0.0001, egg.id .. " odds")
        end
end)

-- A better egg must actually be better, or the coin sink is a lie. This checks
-- the whole ladder rather than one pair: every dearer egg must give a better
-- average pet than the one below it.
t.test("each egg in the ladder is better than the one below it", function()
        local function averageValue(eggId: string): number
                local inv = Pets.new()
                local rng = Random.new(808)
                for _ = 1, 4000 do
                        Pets.hatch(inv, eggId, rng)
                end
                local total = 0
                for _, entry in ipairs(inv.owned) do
                        total += (Pets.get(entry.petId) :: any).valueMultiplier
                end
                return total / math.max(1, #inv.owned)
        end

        local eggs = Pets.eggs()
        local previousCost = 0
        local previousValue = 0
        for _, egg in ipairs(eggs) do
                t.assertGreater(egg.cost, previousCost, egg.id .. " cost")
                local average = averageValue(egg.id)
                t.assertGreater(average, previousValue, egg.id .. " average pet value")
                previousCost = egg.cost
                previousValue = average
        end
end)

t.test("a dearer egg gives a better average pet", function()
        local function averageValue(eggId: string): number
                local inv = Pets.new()
                local rng = Random.new(808)
                for _ = 1, 2000 do
                        Pets.hatch(inv, eggId, rng)
                end
                local total = 0
                for _, entry in ipairs(inv.owned) do
                        total += (Pets.get(entry.petId) :: any).valueMultiplier
                end
                return total / math.max(1, #inv.owned)
        end
        local basic = averageValue("Basic")
        local divine = averageValue("Divine")
        t.assertGreater(divine, basic * 2, "divine vs basic average")
end)

t.test("equipping a pet you do not own is refused", function()
        local inv = Pets.new()
        local ok, reason = Pets.equip(inv, 1)
        t.assertFalse(ok, "equip should fail")
        t.assertEqual(reason, "NOT_OWNED", "reason")
end)

t.test("a pet cannot be equipped twice", function()
        local inv = Pets.new()
        Pets.hatch(inv, "Basic", Random.new(1))
        Pets.equip(inv, 1)
        local ok, reason = Pets.equip(inv, 1)
        t.assertFalse(ok, "double equip should fail")
        t.assertEqual(reason, "ALREADY_EQUIPPED", "reason")
end)

t.test("equip slots are capped", function()
        local inv = Pets.new()
        local rng = Random.new(2)
        for _ = 1, 20 do
                Pets.hatch(inv, "Basic", rng)
        end
        for i = 1, Config.Pets.MaxEquipped do
                t.assertTrue(Pets.equip(inv, i), "equip " .. i)
        end
        local ok, reason = Pets.equip(inv, Config.Pets.MaxEquipped + 1)
        t.assertFalse(ok, "over-equipping should fail")
        t.assertEqual(reason, "SLOTS_FULL", "reason")
        t.assertEqual(#inv.equipped, Config.Pets.MaxEquipped, "equipped count")
end)

t.test("unequipping frees a slot", function()
        local inv = Pets.new()
        Pets.hatch(inv, "Basic", Random.new(3))
        Pets.equip(inv, 1)
        t.assertTrue(Pets.unequip(inv, 1), "unequip")
        t.assertEqual(#inv.equipped, 0, "equipped count")
        t.assertEqual(select(2, Pets.unequip(inv, 1)), "NOT_EQUIPPED", "double unequip")
end)

t.test("bonuses multiply across equipped pets", function()
        local inv = Pets.new()
        Pets.hatch(inv, "Basic", Random.new(4))
        Pets.hatch(inv, "Basic", Random.new(5))
        Pets.equip(inv, 1)
        Pets.equip(inv, 2)
        local bonuses = Pets.bonuses(inv)
        local first = Pets.get(inv.owned[1].petId) :: any
        local second = Pets.get(inv.owned[2].petId) :: any
        t.assertNear(bonuses.growth, first.growthMultiplier * second.growthMultiplier, 0.0001, "growth bonus")
        t.assertNear(bonuses.value, first.valueMultiplier * second.valueMultiplier, 0.0001, "value bonus")
end)

t.test("an empty inventory has no bonuses", function()
        local bonuses = Pets.bonuses(Pets.new())
        t.assertEqual(bonuses.growth, 1, "growth")
        t.assertEqual(bonuses.value, 1, "value")
end)

-- A corrupt save must not brick a garden: an equipped uid with no pet behind it
-- is dropped rather than multiplying by a nil lookup.
t.test("an equipped pet that is not owned is ignored", function()
        local inv = Pets.new()
        table.insert(inv.equipped, 999)
        local bonuses = Pets.bonuses(inv)
        t.assertEqual(bonuses.growth, 1, "growth with a ghost pet")
        t.assertEqual(bonuses.value, 1, "value with a ghost pet")
end)

t.test("prune drops ghost pets and keeps the real ones", function()
        local inv = Pets.new()
        Pets.hatch(inv, "Basic", Random.new(6))
        inv.equipped = { 1, 999, 1000 }
        local removed = Pets.prune(inv)
        t.assertEqual(removed, 2, "removed count")
        t.assertEqual(#inv.equipped, 1, "kept count")
        t.assertEqual(inv.equipped[1], 1, "kept the owned pet")
end)

--------------------------------------------------------------------------
t.suite("Collection")
--------------------------------------------------------------------------

t.test("a new collection is empty and not complete", function()
        local state = Collection.new()
        t.assertEqual(Collection.seedCount(state), 0, "seeds")
        t.assertEqual(Collection.mutationCount(state), 0, "mutations")
        t.assertFalse(Collection.isComplete(state), "complete")
end)

t.test("discovering the same seed twice only reports new once", function()
        local state = Collection.new()
        t.assertTrue(Collection.discover(state, "Carrot"), "first discovery")
        t.assertFalse(Collection.discover(state, "Carrot"), "second discovery")
        t.assertEqual(Collection.seedCount(state), 1, "seed count")
end)

t.test("the best sale only rises", function()
        local state = Collection.new()
        t.assertTrue(Collection.recordSale(state, 100), "first sale is a record")
        t.assertFalse(Collection.recordSale(state, 50), "smaller sale is not a record")
        t.assertEqual(state.bestSale, 100, "best sale")
        t.assertEqual(state.sold, 2, "sold count")
end)

t.test("the by-rarity page covers every tier", function()
        local rows = Collection.byRarity(Collection.new())
        t.assertEqual(#rows, 7, "row count")
        for _, row in ipairs(rows) do
                t.assertGreater(row.total, 0, row.rarity .. " total")
                t.assertEqual(row.owned, 0, row.rarity .. " owned at start")
        end
end)

-- Completion is the end of the collection, so it must require every seed, not a
-- count that a duplicate could satisfy.
t.test("the collection is only complete when every seed is found", function()
        local state = Collection.new()
        local seeds = Seeds.list()
        for i = 1, #seeds - 1 do
                Collection.discover(state, seeds[i].id)
        end
        t.assertFalse(Collection.isComplete(state), "one short")
        Collection.discover(state, seeds[#seeds].id)
        t.assertTrue(Collection.isComplete(state), "all found")
end)

t.test("the snapshot reports the totals", function()
        local state = Collection.new()
        Collection.discover(state, "Carrot")
        local snapshot = Collection.snapshot(state)
        t.assertEqual(snapshot.seedCount, 1, "seed count")
        t.assertEqual(snapshot.seedTotal, #Seeds.list(), "seed total")
        t.assertEqual(snapshot.mutationTotal, #Mutations.list(), "mutation total")
end)

--------------------------------------------------------------------------
t.suite("SaveSchema")
--------------------------------------------------------------------------

t.test("a new save is at the current version", function()
        t.assertEqual(SaveSchema.new(0).version, Config.Save.SchemaVersion, "version")
end)

t.test("a new save starts with the starting coins", function()
        t.assertEqual(SaveSchema.new(0).coins, Config.Economy.StartingCoins, "coins")
end)

t.test("serialisation is deterministic", function()
        local a = SaveSchema.new(1234)
        local b = SaveSchema.new(1234)
        t.assertEqual(SaveSchema.serialize(a), SaveSchema.serialize(b), "two identical saves")
end)

t.test("a save round-trips through migrate", function()
        local save = SaveSchema.new(1000)
        save.coins = 4321
        Garden.plant(save.garden, 1, "Carrot", 1000)
        save.upgrades.speedLevel = 3
        save.collection.seeds["Carrot"] = true
        local restored = SaveSchema.migrate(save, 2000)
        t.assertEqual(restored.coins, 4321, "coins")
        t.assertEqual(restored.upgrades.speedLevel, 3, "speed level")
        t.assertEqual(restored.garden.plots[1].seedId, "Carrot", "planted seed")
        t.assertTrue(restored.collection.seeds["Carrot"] == true, "discovery")
end)

t.test("migrating garbage yields a playable save", function()
        for _, junk in ipairs({ nil, 0, "text", true }) do
                local save = SaveSchema.migrate(junk, 500)
                t.assertEqual(save.version, Config.Save.SchemaVersion, "version from junk")
                t.assertEqual(save.coins, Config.Economy.StartingCoins, "coins from junk")
                t.assertEqual(#save.garden.plots, Config.Garden.TotalPlots, "plots from junk")
        end
end)

t.test("a negative coin balance is repaired", function()
        t.assertEqual(SaveSchema.migrate({ coins = -999 }, 0).coins, 0, "negative coins")
end)

t.test("a NaN coin balance is repaired", function()
        t.assertEqual(SaveSchema.migrate({ coins = 0 / 0 }, 0).coins, Config.Economy.StartingCoins, "nan coins")
end)

t.test("an unlocked count outside the range is clamped", function()
        t.assertEqual(SaveSchema.migrate({ garden = { unlocked = 999 } }, 0).garden.unlocked, Config.Garden.TotalPlots, "too many")
        t.assertEqual(SaveSchema.migrate({ garden = { unlocked = 0 } }, 0).garden.unlocked, Config.Garden.StartingPlots, "too few")
end)

t.test("a plot naming a seed that no longer exists is cleared", function()
        local raw = { garden = { unlocked = 4, plots = { { seedId = "RemovedSeed", plantedAt = 0, readyAt = 100 } } } }
        local save = SaveSchema.migrate(raw, 0)
        t.assertNil(save.garden.plots[1].seedId, "stale seed should be cleared")
end)

t.test("upgrade levels above the cap are clamped", function()
        local save = SaveSchema.migrate({ upgrades = { speedLevel = 9999, valueLevel = 9999 } }, 0)
        t.assertEqual(save.upgrades.speedLevel, Config.Upgrades.SpeedMaxLevel, "speed clamp")
        t.assertEqual(save.upgrades.valueLevel, Config.Upgrades.ValueMaxLevel, "value clamp")
end)

t.test("a pet naming a pet that no longer exists is dropped", function()
        local raw = { pets = { owned = { { uid = 1, petId = "Pup" }, { uid = 2, petId = "RemovedPet" } } } }
        local save = SaveSchema.migrate(raw, 0)
        t.assertEqual(#save.pets.owned, 1, "owned after migrate")
        t.assertEqual(save.pets.owned[1].petId, "Pup", "kept pet")
end)

t.test("duplicate pet uids are reassigned", function()
        local raw = { pets = { owned = { { uid = 7, petId = "Pup" }, { uid = 7, petId = "Pup" } } } }
        local save = SaveSchema.migrate(raw, 0)
        t.assertEqual(#save.pets.owned, 2, "both kept")
        t.assertNotEqual(save.pets.owned[1].uid, save.pets.owned[2].uid, "uids differ")
end)

t.test("an equipped pet with no pet behind it is dropped on load", function()
        local raw = { pets = { owned = { { uid = 1, petId = "Pup" } }, equipped = { 1, 42 } } }
        local save = SaveSchema.migrate(raw, 0)
        t.assertEqual(#save.pets.equipped, 1, "equipped after migrate")
        t.assertEqual(save.pets.equipped[1], 1, "kept the real pet")
end)

t.test("a discovery of a seed that no longer exists is dropped", function()
        local raw = { collection = { seeds = { Carrot = true, RemovedSeed = true } } }
        local save = SaveSchema.migrate(raw, 0)
        t.assertTrue(save.collection.seeds["Carrot"] == true, "kept real seed")
        t.assertNil(save.collection.seeds["RemovedSeed"], "dropped stale seed")
end)

t.test("a save missing lastSeen is treated as a rejoin now", function()
        t.assertEqual(SaveSchema.migrate({}, 777).lastSeen, 777, "lastSeen")
end)

--------------------------------------------------------------------------
t.suite("Text")
--------------------------------------------------------------------------

-- Thai only reaches players if the key exists. A missing key falls back to the
-- id, which is visible in a screenshot but easy to miss in a diff.
t.test("every key the garden uses is defined", function()
        local needed = {
                "title", "coins", "garden", "shop", "seeds", "pets", "collection",
                "upgrades", "close", "plant", "harvest", "harvestAll", "empty",
                "growing", "ready", "buy", "cost", "notEnoughCoins", "sold",
                "newSeed", "newMutation", "hatch", "equip", "unequip", "hatched",
                "growthSpeed", "saleValue", "level", "upgrade", "welcomeBack",
                "offlineGrew", "loading", "error", "locked", "buyPlot",
        }
        for _, key in ipairs(needed) do
                t.assertTrue(Text.has(key), "missing text key: " .. key)
        end
end)

t.test("an unknown key returns itself rather than empty", function()
        t.assertEqual(Text.get("thisKeyDoesNotExist"), "thisKeyDoesNotExist", "unknown key")
end)

t.test("formatting substitutes its arguments", function()
        t.assertEqual(Text.get("cost", 250), "ราคา 250", "formatted cost")
end)

t.test("a formatting mistake falls back to the raw line", function()
        t.assertEqual(Text.get("cost", "not a number"), "ราคา %d", "bad format")
end)

t.test("every rarity has Thai text", function()
        local keys = {
                Common = "rarityCommon", Uncommon = "rarityUncommon", Rare = "rarityRare",
                Epic = "rarityEpic", Legendary = "rarityLegendary", Mythic = "rarityMythic",
                Divine = "rarityDivine",
        }
        for _, id in ipairs(Rarity.ids()) do
                t.assertTrue(Text.has(keys[id]), "missing rarity text: " .. id)
        end
end)

t.test("durations read in the right unit", function()
        t.assertEqual(Text.duration(30), Text.get("secondsLeft", 30), "seconds")
        t.assertEqual(Text.duration(600), Text.get("minutesLeft", 10), "minutes")
        t.assertEqual(Text.duration(7200), Text.get("hoursLeft", 2), "hours")
end)

t.test("a negative duration reads as zero", function()
        t.assertEqual(Text.duration(-5), Text.get("secondsLeft", 0), "negative duration")
end)

--------------------------------------------------------------------------
t.suite("Basket")
--------------------------------------------------------------------------

t.test("a new basket is empty and worth nothing", function()
        local basket = Basket.new()
        t.assertEqual(Basket.count(basket), 0, "count")
        t.assertEqual(Basket.total(basket, Sell.newUpgrades(), { growth = 1, value = 1 }), 0, "total")
end)

t.test("adding a crop increases the count", function()
        local basket = Basket.new()
        local added = Basket.add(basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12)
        t.assertTrue(added, "add returned false")
        t.assertEqual(Basket.count(basket), 1, "count")
end)

t.test("the basket refuses to overflow past its capacity", function()
        local basket = Basket.new()
        for _ = 1, Config.Basket.Capacity do
                t.assertTrue(Basket.add(basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12),
                        "a crop within capacity was refused")
        end
        t.assertEqual(Basket.count(basket), Config.Basket.Capacity, "count at capacity")
        t.assertFalse(Basket.add(basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12),
                "a crop past capacity was accepted")
end)

t.test("selling empties the basket and returns the total", function()
        local basket = Basket.new()
        Basket.add(basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12)
        Basket.add(basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12)
        local total, sold = Basket.sellAll(basket, Sell.newUpgrades(), { growth = 1, value = 1 })
        t.assertEqual(#sold, 2, "entries sold")
        t.assertGreater(total, 0, "total earned")
        t.assertEqual(Basket.count(basket), 0, "the basket was not emptied")
end)

t.test("the basket total follows a value upgrade bought after harvesting", function()
        local basket = Basket.new()
        Basket.add(basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12)
        local base = Basket.total(basket, Sell.newUpgrades(), { growth = 1, value = 1 })

        local upgraded = Sell.newUpgrades()
        upgraded.valueLevel = 5
        local better = Basket.total(basket, upgraded, { growth = 1, value = 1 })
        t.assertGreater(better, base, "a value upgrade did not raise a held crop's worth")
end)

--------------------------------------------------------------------------
t.suite("Remotes")
--------------------------------------------------------------------------

t.test("every remote name is unique", function()
        local seen = {}
        for _, name in ipairs(Remotes.all()) do
                t.assertFalse(seen[name] == true, "duplicate remote name: " .. name)
                seen[name] = true
        end
end)

t.test("no remote name is empty", function()
        for _, name in ipairs(Remotes.all()) do
                t.assertGreater(#name, 0, "an empty remote name would be unusable")
        end
end)

t.test("the client and server agree on the folder name", function()
        t.assertEqual(Remotes.Folders.Remotes, "Remotes", "folder name")
end)

--------------------------------------------------------------------------
t.suite("HudLayout")
--------------------------------------------------------------------------

-- This suite is the reason HudLayout is pure Luau. The previous game laid its
-- HUD out inline and a panel ran off the top of a 360x640 phone. Here the same
-- arithmetic a phone would do is checked directly.
t.test("a panel fits the reference screen", function()
        local height = HudLayout.panelHeight(HudLayout.DESIGN_WIDTH, HudLayout.DESIGN_HEIGHT)
        t.assertGreater(height, 0, "the panel has no height on the design screen")
end)

t.test("every rect is on screen at the smallest phone size", function()
        for _, entry in ipairs(HudLayout.rects(HudLayout.MIN_WIDTH, HudLayout.MIN_HEIGHT)) do
                t.assertTrue(HudLayout.onScreen(entry.rect, HudLayout.MIN_WIDTH, HudLayout.MIN_HEIGHT),
                        entry.name .. " is off screen on a phone")
        end
end)

t.test("the top bar and bottom bar never overlap", function()
        local rects = HudLayout.rects(HudLayout.MIN_WIDTH, HudLayout.MIN_HEIGHT)
        local byName = {}
        for _, entry in ipairs(rects) do
                byName[entry.name] = entry.rect
        end
        t.assertFalse(HudLayout.overlaps(byName.topBar, byName.bottomBar), "top and bottom bars overlap")
end)

t.test("the panel sits between the two bars without overlapping either", function()
        local rects = HudLayout.rects(HudLayout.MIN_WIDTH, HudLayout.MIN_HEIGHT)
        local byName = {}
        for _, entry in ipairs(rects) do
                byName[entry.name] = entry.rect
        end
        t.assertFalse(HudLayout.overlaps(byName.panel, byName.topBar), "panel overlaps the top bar")
        t.assertFalse(HudLayout.overlaps(byName.panel, byName.bottomBar), "panel overlaps the bottom bar")
end)

t.test("a plot cell is never smaller than a finger", function()
        for _, width in ipairs({ 320, 360, 390, 414, 768, 1280 }) do
                local cell = HudLayout.plotCellSize(width, 4)
                t.assertTrue(cell >= HudLayout.MIN_TOUCH,
                        "a plot cell on a " .. width .. "px screen is too small: " .. cell)
        end
end)

t.test("bottom bar buttons are never smaller than a finger", function()
        for _, width in ipairs({ 320, 360, 390, 414, 768, 1280 }) do
                local buttonWidth, buttonHeight = HudLayout.bottomButtonSize(width, 5)
                t.assertTrue(buttonWidth >= HudLayout.MIN_TOUCH,
                        "a bottom button on a " .. width .. "px screen is too narrow: " .. buttonWidth)
                t.assertTrue(buttonHeight >= HudLayout.MIN_TOUCH,
                        "a bottom button on a " .. width .. "px screen is too short: " .. buttonHeight)
        end
end)

t.test("the plot grid never runs off the right edge", function()
        for _, width in ipairs({ 320, 360, 390, 414, 768, 1280 }) do
                local columns = HudLayout.PLOT_GRID.columns
                local cell = HudLayout.plotCellSize(width, columns)
                local right = HudLayout.PAD + columns * (cell + HudLayout.PLOT_GRID.gap) - HudLayout.PLOT_GRID.gap
                t.assertTrue(right <= width, "the plot grid runs off a " .. width .. "px screen by " .. (right - width))
        end
end)

-- The width-only test above passed while the grid covered a landscape phone
-- completely, because "not off the right edge" says nothing about the bottom.
-- These are the screens a real phone reports, both orientations.
local PHONES = {
        { name = "small portrait", w = 360, h = 640 },
        { name = "typical portrait", w = 390, h = 844 },
        { name = "large portrait", w = 414, h = 896 },
        { name = "small landscape", w = 640, h = 360 },
        { name = "typical landscape", w = 844, h = 390 },
        { name = "tablet", w = 768, h = 1024 },
        { name = "desktop", w = 1280, h = 720 },
}

t.test("every plot cell is on screen in both orientations", function()
        for _, phone in ipairs(PHONES) do
                for _, entry in ipairs(HudLayout.plotRects(phone.w, phone.h, HudLayout.PLOT_COUNT)) do
                        t.assertTrue(HudLayout.onScreen(entry.rect, phone.w, phone.h),
                                entry.name .. " is off screen on a " .. phone.name
                                        .. " (" .. phone.w .. "x" .. phone.h .. ")")
                end
        end
end)

t.test("the plot grid never runs under the bottom bar", function()
        for _, phone in ipairs(PHONES) do
                local bottom = HudLayout.bottomBarRect(phone.w, phone.h)
                for _, entry in ipairs(HudLayout.plotRects(phone.w, phone.h, HudLayout.PLOT_COUNT)) do
                        t.assertFalse(HudLayout.overlaps(entry.rect, bottom),
                                entry.name .. " is under the bottom bar on a " .. phone.name)
                end
        end
end)

t.test("the whole screen is on screen, grid included", function()
        for _, phone in ipairs(PHONES) do
                for _, entry in ipairs(HudLayout.rects(phone.w, phone.h)) do
                        t.assertTrue(HudLayout.onScreen(entry.rect, phone.w, phone.h),
                                entry.name .. " is off screen on a " .. phone.name
                                        .. " (" .. phone.w .. "x" .. phone.h .. ")")
                end
        end
end)

t.test("the grid draws exactly the plots the game has", function()
        t.assertEqual(HudLayout.PLOT_COUNT, Config.Garden.TotalPlots,
                "the HUD grid count and the garden plot count have drifted apart")
        t.assertEqual(HudLayout.plotRows(HudLayout.PLOT_COUNT), 3, "rows for 12 plots in 4 columns")
end)

t.test("the scale never magnifies past the design size", function()
        t.assertEqual(HudLayout.scale(HudLayout.DESIGN_WIDTH, HudLayout.DESIGN_HEIGHT), 1, "design scale")
        t.assertEqual(HudLayout.scale(4000, 4000), 1, "a large screen is not stretched")
end)

t.test("a panel reports when its content does not fit", function()
        local tall = HudLayout.panelHeight(HudLayout.MIN_WIDTH, HudLayout.MIN_HEIGHT) + 100
        t.assertFalse(HudLayout.panelFits(HudLayout.MIN_WIDTH, HudLayout.MIN_HEIGHT, tall),
                "a panel taller than the screen reported that it fits")
end)

--------------------------------------------------------------------------
t.suite("SaveSchema: the basket and owned seeds survive a round trip")
--------------------------------------------------------------------------

t.test("a new save has an empty basket and no owned seeds", function()
        local save = SaveSchema.new(0)
        t.assertEqual(Basket.count(save.basket), 0, "basket count")
        t.assertEqual(next(save.seedsOwned), nil, "seedsOwned should be empty")
end)

t.test("a basket and owned seeds survive migrate", function()
        local save = SaveSchema.new(1000)
        Basket.add(save.basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12)
        save.seedsOwned["Carrot"] = 3

        local restored = SaveSchema.migrate(save, 2000)
        t.assertEqual(Basket.count(restored.basket), 1, "basket count after migrate")
        t.assertEqual(restored.basket.entries[1].seedId, "Carrot", "basket entry seed")
        t.assertEqual(restored.seedsOwned["Carrot"], 3, "owned seed count after migrate")
end)

t.test("migrate drops a basket entry naming a seed the game no longer has", function()
        local save = SaveSchema.new(1000)
        table.insert(save.basket.entries, { seedId = "Unobtainium", rarity = "Common", mutation = "None", value = 99 })
        local restored = SaveSchema.migrate(save, 2000)
        t.assertEqual(Basket.count(restored.basket), 0, "an unknown seed survived the migrate")
end)

t.test("migrate caps a hand-edited basket at the capacity", function()
        local save = SaveSchema.new(1000)
        for index = 1, Config.Basket.Capacity + 20 do
                table.insert(save.basket.entries, { seedId = "Carrot", rarity = "Common", mutation = "None", value = 12 })
        end
        local restored = SaveSchema.migrate(save, 2000)
        t.assertEqual(Basket.count(restored.basket), Config.Basket.Capacity, "basket was not capped")
end)

t.test("a snapshot is a deep copy, not a second reference", function()
        local save = SaveSchema.new(1000)
        Garden.plant(save.garden, 1, "Carrot", 1000)
        local copy = SaveSchema.snapshot(save)

        -- Mutating the live save must not change the snapshot, or a DataStore
        -- write could be changed after it was handed over.
        save.garden.plots[1].seedId = nil
        save.coins = 999
        t.assertEqual(copy.garden.plots[1].seedId, "Carrot", "the snapshot changed with the live save")
        t.assertEqual(copy.coins, Config.Economy.StartingCoins, "the snapshot's coins changed")
end)

t.test("a save with a planted garden serialises without error", function()
        -- The encoder must handle the plot array, which is keyed by integer.
        -- A string-only key sorter would refuse to encode this at all.
        local save = SaveSchema.new(1000)
        Garden.plant(save.garden, 1, "Carrot", 1000)
        Basket.add(save.basket, { seedId = "Carrot", rarity = "Common", mutation = "None" }, 12)
        local ok, text = pcall(SaveSchema.serialize, save)
        t.assertTrue(ok, "serialising a planted garden threw: " .. tostring(text))
        t.assertGreater(#text, 0, "the serialised save is empty")
end)

--------------------------------------------------------------------------
t.finish()

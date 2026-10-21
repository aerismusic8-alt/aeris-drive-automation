--!strict
-- What a harvest is worth, and the player's upgrades that change it. Pure Luau.
--
-- Every multiplier in the game meets here exactly once: the seed's base value,
-- the tier's value multiplier, the mutation's multiplier, the sale-value upgrade
-- and the equipped pets. Combining them in one function is what stops the shop
-- and the HUD from disagreeing about what a crop is worth.

local Config = require("./Config")
local Seeds = require("./Seeds")
local Rarity = require("./Rarity")
local Mutations = require("./Mutations")
local Pets = require("./Pets")

local Sell = {}

export type Upgrades = {
        -- Bought levels, not raw multipliers.
        speedLevel: number,
        valueLevel: number,
}

export type Breakdown = {
        base: number,
        rarity: number,
        mutation: number,
        upgrade: number,
        pet: number,
        total: number,
        mutationId: string,
}

function Sell.newUpgrades(): Upgrades
        return { speedLevel = 0, valueLevel = 0 }
end

-- Value multiplier from the sale-value upgrade.
function Sell.valueMultiplier(upgrades: Upgrades): number
        local level = math.clamp(math.floor(upgrades.valueLevel or 0), 0, Config.Upgrades.ValueMaxLevel)
        return 1 + level * Config.Upgrades.ValuePerLevel
end

-- Growth multiplier from the speed upgrade. Pets multiply on top of this in
-- `Sell.growthMultiplier`.
function Sell.speedMultiplier(upgrades: Upgrades): number
        local level = math.clamp(math.floor(upgrades.speedLevel or 0), 0, Config.Upgrades.SpeedMaxLevel)
        return 1 + level * Config.Upgrades.SpeedPerLevel
end

-- Growth multiplier applied to a seed's grow time: the upgrade and the pets.
function Sell.growthMultiplier(upgrades: Upgrades, petBonuses: any): number
        return Sell.speedMultiplier(upgrades) * (petBonuses and petBonuses.growth or 1)
end

-- Full breakdown of one sale, so the HUD can show the player why a crop is
-- worth what it is rather than a number appearing from nowhere.
function Sell.breakdown(reward: any, upgrades: Upgrades, petBonuses: any): Breakdown
        local seed = Seeds.get(reward.seedId)
        local base = seed and seed.baseValue or 0
        local rarity = Rarity.valueMultiplier(reward.rarity)
        local mutation = Mutations.multiplier(reward.mutation)
        local upgrade = Sell.valueMultiplier(upgrades)
        local pet = petBonuses and petBonuses.value or 1
        local total = base * rarity * mutation * upgrade * pet
        -- The floor exists so a tiny pet multiplier cannot round a real sale
        -- down to nothing. A crop whose seed no longer exists is worth nothing,
        -- and must not be paid the floor.
        local floored = 0
        if base > 0 then
                floored = math.max(Config.Economy.SellFloor, math.floor(total))
        end
        return {
                base = base,
                rarity = rarity,
                mutation = mutation,
                upgrade = upgrade,
                pet = pet,
                total = floored,
                mutationId = reward.mutation,
        }
end

function Sell.value(reward: any, upgrades: Upgrades, petBonuses: any): number
        return Sell.breakdown(reward, upgrades, petBonuses).total
end

-- Cost of the next level of an upgrade. Level is the level already owned, so
-- the first purchase is level 0 -> 1.
function Sell.upgradeCost(kind: string, currentLevel: number): number
        local level = math.max(0, math.floor(currentLevel))
        if kind == "speed" then
                if level >= Config.Upgrades.SpeedMaxLevel then
                        return math.huge
                end
                return math.floor(Config.Upgrades.SpeedBaseCost * Config.Upgrades.SpeedCostGrowth ^ level)
        elseif kind == "value" then
                if level >= Config.Upgrades.ValueMaxLevel then
                        return math.huge
                end
                return math.floor(Config.Upgrades.ValueBaseCost * Config.Upgrades.ValueCostGrowth ^ level)
        end
        return math.huge
end

-- Buy one level. Returns the coins left, or nil and a reason.
function Sell.buyUpgrade(coins: number, upgrades: Upgrades, kind: string): (number?, string?)
        local current = 0
        if kind == "speed" then
                current = upgrades.speedLevel
        elseif kind == "value" then
                current = upgrades.valueLevel
        else
                return nil, "NO_SUCH_UPGRADE"
        end

        local cost = Sell.upgradeCost(kind, current)
        if cost == math.huge then
                return nil, "MAX_LEVEL"
        end
        if coins < cost then
                return nil, "NOT_ENOUGH_COINS"
        end

        if kind == "speed" then
                upgrades.speedLevel = current + 1
        else
                upgrades.valueLevel = current + 1
        end
        return coins - cost, nil
end

-- Cost of the next locked plot, given how many are already unlocked.
function Sell.plotCost(unlocked: number): number
        local bought = math.max(0, math.floor(unlocked) - Config.Garden.StartingPlots)
        return math.floor(Config.Upgrades.PlotBaseCost * Config.Upgrades.PlotCostGrowth ^ bought)
end

-- Buy one more plot. Returns the coins left, or nil and a reason.
function Sell.buyPlot(coins: number, state: any): (number?, string?)
        if state.unlocked >= Config.Garden.TotalPlots then
                return nil, "ALL_UNLOCKED"
        end
        local cost = Sell.plotCost(state.unlocked)
        if coins < cost then
                return nil, "NOT_ENOUGH_COINS"
        end
        state.unlocked += 1
        return coins - cost, nil
end

-- Offline growth window in seconds, clamped to the cap. A negative delta (a
-- clock that moved backwards) is treated as no time at all rather than as a
-- huge negative that would un-ripen crops.
function Sell.offlineSeconds(lastSeen: number, now: number): number
        local elapsed = now - lastSeen
        if elapsed < Config.Offline.MinimumSeconds then
                return 0
        end
        return math.min(elapsed, Config.Offline.MaxOfflineSeconds)
end

return Sell

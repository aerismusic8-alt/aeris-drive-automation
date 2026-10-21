--!strict
-- Seeds: the catalogue, and the shop that stocks a rotating few of them. Pure Luau.
--
-- The catalogue is every seed in the game. The shop is the subset on sale right
-- now, picked by rarity weight, so a player cannot simply buy the best seed with
-- their first coins. Rerolling the stock is what brings a player back to the
-- shop; the same shop forever is a menu, not a reason to log in.

local Config = require("./Config")
local Rarity = require("./Rarity")

local Seeds = {}

export type SeedDef = {
        id: string,
        rarity: string,
        growSeconds: number,
        baseValue: number,
        color: { number },
}

local BY_ID: { [string]: SeedDef } = {}
local ORDER: { string } = {}

for _, raw in ipairs(Config.Seeds) do
        BY_ID[raw.id] = raw
        table.insert(ORDER, raw.id)
end

function Seeds.get(id: string): SeedDef?
        return BY_ID[id]
end

function Seeds.list(): { SeedDef }
        local out: { SeedDef } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, BY_ID[id])
        end
        return out
end

-- Every seed of a tier, in catalogue order. The shop and the collection page
-- both walk rarity, so this is the shared step.
function Seeds.byRarity(rarity: string): { SeedDef }
        local out: { SeedDef } = {}
        for _, id in ipairs(ORDER) do
                local def = BY_ID[id]
                if def.rarity == rarity then
                        table.insert(out, def)
                end
        end
        return out
end

-- What a seed costs to buy. Priced off its payout: a seed that pays 10x costs
-- roughly 5x, so the shop is a patience-versus-payout decision rather than a
-- strictly-best option.
--
-- Rounded to a readable number, because a shop showing 1234.567 coins reads as
-- unfinished. The step grows with the magnitude, so the rounding stays fine at
-- the cheap end: a coarse step there collapses two different seeds onto one
-- price, and a player cannot tell which of them is worth buying.
function Seeds.cost(id: string): number
        local def = BY_ID[id]
        if not def then
                return math.huge
        end
        local raw = def.baseValue * 0.5
        local step = 1
        if raw >= 100000 then
                step = 1000
        elseif raw >= 10000 then
                step = 100
        elseif raw >= 1000 then
                step = 10
        elseif raw >= 100 then
                step = 5
        end
        return math.max(1, math.floor(raw / step + 0.5) * step)
end

-- The rotating shop stock. `count` seeds are drawn by rarity weight, and a seed
-- is never drawn twice in one stock. Returns a list of seed ids.
--
-- The RNG is passed in so a test can pin a stock exactly, the same contract the
-- rest of the game uses.
function Seeds.rollStock(rng: any, count: number): { string }
        local pool: { any } = {}
        for _, id in ipairs(ORDER) do
                local def = BY_ID[id]
                local tier = Rarity.get(def.rarity)
                table.insert(pool, { weight = tier and tier.weight or 1, id = id })
        end

        local stock: { string } = {}
        local taken: { [string]: boolean } = {}
        local wanted = math.max(0, math.floor(count))
        -- Bounded so a pool smaller than `count` cannot loop forever.
        local attempts = 0
        local maxAttempts = wanted * 20 + 20
        while #stock < wanted and attempts < maxAttempts do
                attempts += 1
                local pick = rng:pickWeighted(pool)
                if pick and not taken[pick.id] then
                        taken[pick.id] = true
                        table.insert(stock, pick.id)
                end
        end
        return stock
end

-- Odds of a given seed appearing in one roll of the shop, as a fraction of the
-- whole pool. The shop UI shows these, so they must be derived rather than
-- written down a second time.
function Seeds.appearanceOdds(id: string): number
        local def = BY_ID[id]
        if not def then
                return 0
        end
        local total = 0
        for _, other in ipairs(ORDER) do
                local tier = Rarity.get(BY_ID[other].rarity)
                total += tier and tier.weight or 1
        end
        if total <= 0 then
                return 0
        end
        local tier = Rarity.get(def.rarity)
        return (tier and tier.weight or 1) / total
end

-- Grow time for a seed after the player's speed upgrade and pets are applied.
-- Clamped to a floor so upgrades cannot make a crop instant, which would remove
-- the loop entirely.
function Seeds.growSeconds(id: string, growthMultiplier: number): number
        local def = BY_ID[id]
        if not def then
                return math.huge
        end
        local speed = math.max(0.01, growthMultiplier)
        return math.max(1, def.growSeconds / speed)
end

return Seeds

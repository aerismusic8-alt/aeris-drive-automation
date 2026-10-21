--!strict
-- The basket: crops that have been harvested but not yet sold. Pure Luau.
--
-- Harvesting and selling are separate on purpose. If a harvest paid out on the
-- spot, the mutation roll would be a number that appears and vanishes in the
-- same frame. Holding the crop until the player cashes it in is what turns a
-- Cosmic roll into something they can see sitting in a basket.

local Config = require("./Config")
local Sell = require("./Sell")

local Basket = {}

export type Entry = {
        seedId: string,
        rarity: string,
        mutation: string,
        -- Coins this entry is worth right now, computed when it was harvested.
        -- Recomputed on sale, so an upgrade bought while holding a crop still
        -- applies to it.
        value: number,
}

export type State = {
        entries: { Entry },
}

function Basket.new(): State
        return { entries = {} }
end

function Basket.count(state: State): number
        return #state.entries
end

-- Put a harvest in the basket. Returns false when the basket is full, so the
-- player is told rather than silently losing a crop.
function Basket.add(state: State, reward: any, value: number): boolean
        if #state.entries >= Config.Basket.Capacity then
                return false
        end
        table.insert(state.entries, {
                seedId = reward.seedId,
                rarity = reward.rarity,
                mutation = reward.mutation,
                value = value,
        })
        return true
end

-- Total the basket is worth right now, recomputed from current upgrades and
-- pets rather than from the values stored when each crop was picked.
function Basket.total(state: State, upgrades: any, petBonuses: any): number
        local total = 0
        for _, entry in ipairs(state.entries) do
                total += Sell.value(entry, upgrades, petBonuses)
        end
        return total
end

-- The most valuable entry, for a "best in basket" readout. Nil when empty.
function Basket.best(state: State): Entry?
        local best: Entry? = nil
        for _, entry in ipairs(state.entries) do
                if best == nil or entry.value > (best :: Entry).value then
                        best = entry
                end
        end
        return best
end

-- Sell everything. Returns the coins earned and the entries that were sold, so
-- the caller can record the discoveries and the best-sale record.
function Basket.sellAll(state: State, upgrades: any, petBonuses: any): (number, { Entry })
        local sold = state.entries
        local total = 0
        for _, entry in ipairs(sold) do
                total += Sell.value(entry, upgrades, petBonuses)
        end
        state.entries = {}
        return total, sold
end

-- The snapshot the HUD draws.
function Basket.snapshot(state: State, upgrades: any, petBonuses: any): { any }
        local best = Basket.best(state)
        return {
                count = Basket.count(state),
                total = Basket.total(state, upgrades, petBonuses),
                entries = state.entries,
                best = best,
        }
end

return Basket

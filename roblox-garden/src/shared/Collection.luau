--!strict
-- The collection: which seeds and mutations a player has ever seen. Pure Luau.
--
-- This is the second half of the genre's hook. Farming pays coins, but the
-- reason to keep opening the game is the seed that is still missing from the
-- list. A player who has every seed has "finished" the garden, which is what
-- the rarest tiers exist to postpone.

local Seeds = require("./Seeds")
local Mutations = require("./Mutations")
local Rarity = require("./Rarity")

local Collection = {}

export type State = {
        -- Seed ids ever harvested.
        seeds: { [string]: boolean },
        -- Mutation ids ever rolled.
        mutations: { [string]: boolean },
        -- Total crops sold, for a "garden veteran" number.
        sold: number,
        -- Best single sale, the player's personal record.
        bestSale: number,
}

function Collection.new(): State
        return { seeds = {}, mutations = {}, sold = 0, bestSale = 0 }
end

-- Record a harvest. Returns true when the seed was new, so the caller can fire
-- a "new discovery" celebration exactly once.
function Collection.discover(state: State, seedId: string): boolean
        if state.seeds[seedId] then
                return false
        end
        state.seeds[seedId] = true
        return true
end

function Collection.discoverMutation(state: State, mutationId: string): boolean
        if state.mutations[mutationId] then
                return false
        end
        state.mutations[mutationId] = true
        return true
end

function Collection.recordSale(state: State, value: number): boolean
        state.sold += 1
        if value > state.bestSale then
                state.bestSale = value
                return true
        end
        return false
end

function Collection.hasSeed(state: State, seedId: string): boolean
        return state.seeds[seedId] == true
end

function Collection.hasMutation(state: State, mutationId: string): boolean
        return state.mutations[mutationId] == true
end

function Collection.seedCount(state: State): number
        local count = 0
        for _ in pairs(state.seeds) do
                count += 1
        end
        return count
end

function Collection.mutationCount(state: State): number
        local count = 0
        for _ in pairs(state.mutations) do
                count += 1
        end
        return count
end

-- Progress per tier, for a collection page that shows what is left to find.
function Collection.byRarity(state: State): { { rarity: string, owned: number, total: number } }
        local out: { { rarity: string, owned: number, total: number } } = {}
        for _, rarityId in ipairs(Rarity.ids()) do
                local seeds = Seeds.byRarity(rarityId)
                local owned = 0
                for _, seed in ipairs(seeds) do
                        if state.seeds[seed.id] then
                                owned += 1
                        end
                end
                table.insert(out, { rarity = rarityId, owned = owned, total = #seeds })
        end
        return out
end

-- True when every seed in the game has been found.
function Collection.isComplete(state: State): boolean
        for _, seed in ipairs(Seeds.list()) do
                if not state.seeds[seed.id] then
                        return false
                end
        end
        return true
end

-- The snapshot the collection page draws.
function Collection.snapshot(state: State): { any }
        return {
                seeds = state.seeds,
                mutations = state.mutations,
                sold = state.sold,
                bestSale = state.bestSale,
                seedCount = Collection.seedCount(state),
                seedTotal = #Seeds.list(),
                mutationCount = Collection.mutationCount(state),
                mutationTotal = #Mutations.list(),
                byRarity = Collection.byRarity(state),
                complete = Collection.isComplete(state),
        }
end

return Collection

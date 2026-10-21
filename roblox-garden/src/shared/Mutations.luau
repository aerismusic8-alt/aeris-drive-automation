--!strict
-- Mutations: the one roll that decides whether a harvest is ordinary or the
-- reason the player screenshots the game. Pure Luau.
--
-- Every harvest draws exactly one mutation. The multiplier is applied to the
-- sale value, so the same seed pays 1x most of the time and 240x once in a
-- while. That variance is the point: without it, harvesting is arithmetic.

local Config = require("./Config")

local Mutations = {}

export type MutationDef = {
        id: string,
        name: string,
        multiplier: number,
        weight: number,
        color: { number },
}

local BY_ID: { [string]: MutationDef } = {}
local ORDER: { string } = {}
local TOTAL_WEIGHT = 0

for _, raw in ipairs(Config.Mutations) do
        BY_ID[raw.id] = raw
        table.insert(ORDER, raw.id)
        TOTAL_WEIGHT += raw.weight
end

-- The no-mutation result. A harvest always has an id, never nil, so the caller
-- never has to branch on "was there a mutation".
Mutations.None = "None"

function Mutations.get(id: string): MutationDef?
        return BY_ID[id]
end

function Mutations.list(): { MutationDef }
        local out: { MutationDef } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, BY_ID[id])
        end
        return out
end

function Mutations.multiplier(id: string): number
        local def = BY_ID[id]
        if not def then
                return 1
        end
        return def.multiplier
end

function Mutations.color(id: string): { number }
        local def = BY_ID[id]
        if not def then
                return { 200, 200, 200 }
        end
        return def.color
end

-- The chance of drawing a mutation, as a fraction. Derived from the weights so
-- the shop or an event can show it without restating the table.
function Mutations.chance(id: string): number
        local def = BY_ID[id]
        if not def or TOTAL_WEIGHT <= 0 then
                return 0
        end
        return def.weight / TOTAL_WEIGHT
end

-- Chance of drawing anything better than the given id. Used to decide whether a
-- harvest is worth a celebration effect.
function Mutations.betterChanceThan(id: string): number
        local def = BY_ID[id]
        local cutoff = def and def.weight or 0
        local total = 0
        for _, other in ipairs(ORDER) do
                if other.weight < cutoff then
                        total += other.weight
                end
        end
        if TOTAL_WEIGHT <= 0 then
                return 0
        end
        return total / TOTAL_WEIGHT
end

-- One roll, weighted. `luck` scales the chance of everything except None: at
-- luck 1 nothing changes, and above 1 the ordinary result becomes less likely.
-- Clamped at 0 so a penalty cannot make an ordinary harvest certain by accident.
function Mutations.roll(rng: any, luck: number?): string
        local bonus = math.max(0, luck or 1)
        if bonus == 1 then
                local pick = rng:pickWeighted(Mutations.list())
                return pick and pick.id or Mutations.None
        end

        local entries: { any } = {}
        for _, id in ipairs(ORDER) do
                local def = BY_ID[id]
                local weight = def.weight
                if id ~= Mutations.None then
                        weight = weight * bonus
                end
                table.insert(entries, { id = id, weight = weight })
        end
        local pick = rng:pickWeighted(entries)
        return pick and pick.id or Mutations.None
end

return Mutations

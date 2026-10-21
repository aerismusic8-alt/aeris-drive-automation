--!strict
-- The seven collection tiers. Pure Luau.
--
-- Rarity is one lookup table rather than a colour and a number repeated at every
-- call site, so the shop, the save file and the HUD all agree on what "Rare"
-- means. `valueMultiplier` is applied once, in Sell.luau.

local Config = require("./Config")

local Rarity = {}

export type RarityDef = {
        id: string,
        name: string,
        weight: number,
        valueMultiplier: number,
        color: { number },
}

local BY_ID: { [string]: RarityDef } = {}
local ORDER: { string } = {}

for _, raw in ipairs(Config.Rarities) do
        BY_ID[raw.id] = raw
        table.insert(ORDER, raw.id)
end

function Rarity.get(id: string): RarityDef?
        return BY_ID[id]
end

-- Every tier, weakest first. The order is the config order and the tests pin it.
function Rarity.list(): { RarityDef }
        local out: { RarityDef } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, BY_ID[id])
        end
        return out
end

function Rarity.ids(): { string }
        local out: { string } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, id)
        end
        return out
end

-- Position in the ladder, 1 for the weakest. Used to compare two tiers and to
-- roll a tier at or below another.
function Rarity.rank(id: string): number
        for i, candidate in ipairs(ORDER) do
                if candidate == id then
                        return i
                end
        end
        return 0
end

-- Value multiplier for a tier, or 1 for an unknown id. An unknown id is not an
-- error here: a save from a future version must still sell for something.
function Rarity.valueMultiplier(id: string): number
        local def = BY_ID[id]
        if not def then
                return 1
        end
        return def.valueMultiplier
end

function Rarity.color(id: string): { number }
        local def = BY_ID[id]
        if not def then
                return { 200, 200, 200 }
        end
        return def.color
end

return Rarity

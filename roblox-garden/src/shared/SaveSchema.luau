--!strict
-- Save validation, migration and deterministic serialisation. Pure Luau.
--
-- Two paths read a save: `serialize` writes one, `migrate` repairs one. They are
-- deliberately separate functions because a save written by an older version is
-- the normal case, not an error case. Every field added here must be added to
-- both, or it survives one path and not the other.

local Config = require("./Config")
local Garden = require("./Garden")
local Pets = require("./Pets")
local Collection = require("./Collection")
local Sell = require("./Sell")

local SaveSchema = {}

export type Save = {
        version: number,
        coins: number,
        garden: any,
        upgrades: any,
        pets: any,
        collection: any,
        lastSeen: number,
        createdAt: number,
}

local function numberOr(value: any, fallback: number): number
        local n = tonumber(value)
        if not n or n ~= n or n == math.huge or n == -math.huge then
                return fallback
        end
        return n
end

local function boolMap(value: any): { [string]: boolean }
        local out: { [string]: boolean } = {}
        if type(value) ~= "table" then
                return out
        end
        for key, flag in pairs(value) do
                if type(key) == "string" and flag then
                        out[key] = true
                end
        end
        return out
end

function SaveSchema.new(now: number): Save
        return {
                version = Config.Save.SchemaVersion,
                coins = Config.Economy.StartingCoins,
                garden = Garden.new(),
                upgrades = Sell.newUpgrades(),
                pets = Pets.new(),
                collection = Collection.new(),
                lastSeen = now,
                createdAt = now,
        }
end

-- Deterministic JSON. Keys are sorted, numbers are rounded, and nothing is
-- written that a future version cannot read. Determinism matters because a test
-- compares two serialisations byte for byte.
local function sortedKeys(t: { [string]: any }): { string }
        local keys: { string } = {}
        for key in pairs(t) do
                table.insert(keys, key)
        end
        table.sort(keys)
        return keys
end

local function encode(value: any): string
        local valueType = type(value)
        if valueType == "number" then
                if value ~= value or value == math.huge or value == -math.huge then
                        return "0"
                end
                return string.format("%.3f", value)
        elseif valueType == "string" then
                return string.format("%q", value)
        elseif valueType == "boolean" then
                return value and "true" or "false"
        elseif valueType == "table" then
                local parts: { string } = {}
                for _, key in ipairs(sortedKeys(value)) do
                        table.insert(parts, string.format("%q", key) .. ":" .. encode(value[key]))
                end
                return "{" .. table.concat(parts, ",") .. "}"
        end
        return "null"
end

function SaveSchema.serialize(save: Save): string
        return encode(save)
end

-- Repair a loaded save into the current schema. Every field is rebuilt rather
-- than trusted, so a truncated or hand-edited save cannot crash the server.
function SaveSchema.migrate(raw: any, now: number): Save
        local save = SaveSchema.new(now)
        if type(raw) ~= "table" then
                return save
        end

        save.createdAt = numberOr(raw.createdAt, now)
        save.lastSeen = numberOr(raw.lastSeen, now)
        save.coins = math.max(0, numberOr(raw.coins, Config.Economy.StartingCoins))

        -- Garden: keep the plot array the right length, and drop a plot that
        -- names a seed the game no longer has.
        if type(raw.garden) == "table" then
                local unlocked = math.floor(numberOr(raw.garden.unlocked, Config.Garden.StartingPlots))
                save.garden.unlocked = math.clamp(unlocked, Config.Garden.StartingPlots, Config.Garden.TotalPlots)
                if type(raw.garden.plots) == "table" then
                        local Seeds = require("./Seeds")
                        for index = 1, Config.Garden.TotalPlots do
                                local rawPlot = raw.garden.plots[index]
                                local plot = save.garden.plots[index]
                                if type(rawPlot) == "table" and type(rawPlot.seedId) == "string" then
                                        if Seeds.get(rawPlot.seedId) then
                                                plot.seedId = rawPlot.seedId
                                                plot.plantedAt = numberOr(rawPlot.plantedAt, now)
                                                plot.readyAt = numberOr(rawPlot.readyAt, now)
                                        end
                                end
                        end
                end
        end

        -- Upgrades: clamp to the caps so a save cannot exceed them.
        if type(raw.upgrades) == "table" then
                save.upgrades.speedLevel = math.clamp(math.floor(numberOr(raw.upgrades.speedLevel, 0)), 0, Config.Upgrades.SpeedMaxLevel)
                save.upgrades.valueLevel = math.clamp(math.floor(numberOr(raw.upgrades.valueLevel, 0)), 0, Config.Upgrades.ValueMaxLevel)
        end

        -- Pets: rebuild the owned list, reassign uids so they are unique, and
        -- drop equipped uids that are not owned.
        if type(raw.pets) == "table" then
                if type(raw.pets.owned) == "table" then
                        local seen: { [number]: boolean } = {}
                        for _, entry in ipairs(raw.pets.owned) do
                                if type(entry) == "table" and type(entry.petId) == "string" and Pets.get(entry.petId) then
                                        local uid = math.floor(numberOr(entry.uid, save.pets.nextUid))
                                        if uid < 1 or seen[uid] then
                                                uid = save.pets.nextUid
                                        end
                                        seen[uid] = true
                                        table.insert(save.pets.owned, { uid = uid, petId = entry.petId })
                                        if uid >= save.pets.nextUid then
                                                save.pets.nextUid = uid + 1
                                        end
                                end
                        end
                end
                if type(raw.pets.equipped) == "table" then
                        for _, uid in ipairs(raw.pets.equipped) do
                                table.insert(save.pets.equipped, math.floor(numberOr(uid, 0)))
                        end
                end
                save.pets.hatches = math.max(0, math.floor(numberOr(raw.pets.hatches, 0)))
                Pets.prune(save.pets)
        end

        -- Collection: only keep ids the game still knows.
        if type(raw.collection) == "table" then
                local Seeds = require("./Seeds")
                local Mutations = require("./Mutations")
                for seedId in pairs(boolMap(raw.collection.seeds)) do
                        if Seeds.get(seedId) then
                                save.collection.seeds[seedId] = true
                        end
                end
                for mutationId in pairs(boolMap(raw.collection.mutations)) do
                        if Mutations.get(mutationId) then
                                save.collection.mutations[mutationId] = true
                        end
                end
                save.collection.sold = math.max(0, math.floor(numberOr(raw.collection.sold, 0)))
                save.collection.bestSale = math.max(0, numberOr(raw.collection.bestSale, 0))
        end

        save.version = Config.Save.SchemaVersion
        return save
end

return SaveSchema

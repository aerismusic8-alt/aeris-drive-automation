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
local Basket = require("./Basket")
local Sell = require("./Sell")

local SaveSchema = {}

export type Save = {
        version: number,
        coins: number,
        garden: any,
        upgrades: any,
        pets: any,
        collection: any,
        -- Harvested crops waiting to be sold.
        basket: any,
        -- Seed id -> how many of that seed are bought and unplanted. A count
        -- rather than a boolean, because a player can buy two of the same seed.
        seedsOwned: { [string]: number },
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
                basket = Basket.new(),
                seedsOwned = {},
                lastSeen = now,
                createdAt = now,
        }
end

-- Keys sorted for determinism. Numbers are allowed: a garden's plots are keyed
-- by plot index, so a string-only sorter would refuse to encode a planted
-- garden at all.
local function sortedKeys(t: { [any]: any }): { any }
        local keys: { any } = {}
        for key in pairs(t) do
                table.insert(keys, key)
        end
        table.sort(keys, function(a, b)
                local ta, tb = type(a), type(b)
                if ta == tb then
                        return a < b
                end
                return ta == "number"
        end)
        return keys
end

-- True when a table is a pure array: keys are 1..n with no gaps. Such a table
-- is written as a JSON array, which is what a list of basket entries is.
local function isArray(t: { [any]: any }): boolean
        local n = 0
        for key in pairs(t) do
                if type(key) ~= "number" then
                        return false
                end
                n += 1
        end
        if n == 0 then
                return false
        end
        for index = 1, n do
                if t[index] == nil then
                        return false
                end
        end
        return true
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
                if isArray(value) then
                        for index = 1, #value do
                                table.insert(parts, encode(value[index]))
                        end
                        return "[" .. table.concat(parts, ",") .. "]"
                end
                for _, key in ipairs(sortedKeys(value)) do
                        table.insert(parts, string.format("%q", tostring(key)) .. ":" .. encode(value[key]))
                end
                return "{" .. table.concat(parts, ",") .. "}"
        end
        return "null"
end

function SaveSchema.serialize(save: Save): string
        return encode(save)
end

-- A deep copy of a save, as plain data: numbers, strings, booleans and nested
-- tables only. The DataStore is given this rather than the live save, so a
-- write can never alias the running game's state and a later mutation cannot
-- change what was stored. Every table is rebuilt, so a copy is a snapshot and
-- not a second reference to the same tables.
function SaveSchema.snapshot(save: Save): any
        local function copy(value: any): any
                if type(value) ~= "table" then
                        return value
                end
                local out = {}
                for key, inner in pairs(value) do
                        out[key] = copy(inner)
                end
                return out
        end
        return copy(save)
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

        -- Basket: keep only entries naming a seed the game still has, and cap
        -- the count, so a hand-edited save cannot overflow it.
        if type(raw.basket) == "table" and type(raw.basket.entries) == "table" then
                local Seeds = require("./Seeds")
                local Mutations = require("./Mutations")
                for _, entry in ipairs(raw.basket.entries) do
                        if #save.basket.entries >= Config.Basket.Capacity then
                                break
                        end
                        if type(entry) == "table" and type(entry.seedId) == "string" and Seeds.get(entry.seedId) then
                                local mutation = type(entry.mutation) == "string" and entry.mutation or Mutations.None
                                if not Mutations.get(mutation) then
                                        mutation = Mutations.None
                                end
                                local rarity = type(entry.rarity) == "string" and entry.rarity or "Common"
                                if not require("./Rarity").get(rarity) then
                                        rarity = "Common"
                                end
                                table.insert(save.basket.entries, {
                                        seedId = entry.seedId,
                                        rarity = rarity,
                                        mutation = mutation,
                                        value = math.max(0, numberOr(entry.value, 0)),
                                })
                        end
                end
        end

        -- Seeds bought but not planted: keep counts for seeds that still exist.
        if type(raw.seedsOwned) == "table" then
                local Seeds = require("./Seeds")
                for seedId, count in pairs(raw.seedsOwned) do
                        if type(seedId) == "string" and Seeds.get(seedId) then
                                local n = math.floor(numberOr(count, 0))
                                if n > 0 then
                                        save.seedsOwned[seedId] = n
                                end
                        end
                end
        end

        save.version = Config.Save.SchemaVersion
        return save
end

return SaveSchema

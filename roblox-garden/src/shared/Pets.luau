--!strict
-- Pets, eggs and equipping. Pure Luau.
--
-- A pet is a permanent multiplier the player earns from an egg. Eggs are bought
-- with coins, so the pet loop is a coin sink with a collection on the other side
-- of it -- which is what keeps a farming game from being only about the farm.

local Config = require("./Config")
local Rarity = require("./Rarity")

local Pets = {}

export type PetDef = {
        id: string,
        rarity: string,
        growthMultiplier: number,
        valueMultiplier: number,
}

export type EggDef = {
        id: string,
        name: string,
        cost: number,
        odds: { [string]: number },
}

export type Inventory = {
        -- One entry per pet owned. A pet can be owned more than once.
        owned: { { uid: number, petId: string } },
        -- uids currently in a slot, at most Config.Pets.MaxEquipped.
        equipped: { number },
        nextUid: number,
        hatches: number,
}

local BY_ID: { [string]: PetDef } = {}
local ORDER: { string } = {}

for _, raw in ipairs(Config.Pets.Pets) do
        BY_ID[raw.id] = raw
        table.insert(ORDER, raw.id)
end

local EGGS_BY_ID: { [string]: EggDef } = {}
local EGG_ORDER: { string } = {}

for _, raw in ipairs(Config.Pets.Eggs) do
        EGGS_BY_ID[raw.id] = raw
        table.insert(EGG_ORDER, raw.id)
end

function Pets.get(id: string): PetDef?
        return BY_ID[id]
end

function Pets.list(): { PetDef }
        local out: { PetDef } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, BY_ID[id])
        end
        return out
end

function Pets.byRarity(rarity: string): { PetDef }
        local out: { PetDef } = {}
        for _, id in ipairs(ORDER) do
                if BY_ID[id].rarity == rarity then
                        table.insert(out, BY_ID[id])
                end
        end
        return out
end

function Pets.egg(id: string): EggDef?
        return EGGS_BY_ID[id]
end

function Pets.eggs(): { EggDef }
        local out: { EggDef } = {}
        for _, id in ipairs(EGG_ORDER) do
                table.insert(out, EGGS_BY_ID[id])
        end
        return out
end

function Pets.new(): Inventory
        return { owned = {}, equipped = {}, nextUid = 1, hatches = 0 }
end

-- Total odds in an egg. The egg's odds table is normalised against this, so a
-- designer can write 80/20 or 0.8/0.2 and get the same egg.
local function eggTotal(egg: EggDef): number
        local total = 0
        for _, weight in pairs(egg.odds) do
                total += weight
        end
        return total
end

-- One hatch. Returns the pet id, or nil and a reason when the egg cannot be
-- opened. The coin charge is the caller's business; this only rolls.
function Pets.hatch(inv: Inventory, eggId: string, rng: any): (string?, string?)
        local egg = EGGS_BY_ID[eggId]
        if not egg then
                return nil, "NO_SUCH_EGG"
        end

        local total = eggTotal(egg)
        if total <= 0 then
                return nil, "EMPTY_EGG"
        end

        -- Pick a rarity tier first, then a pet of that tier, so an egg that
        -- lists a tier with no pets cannot bias the odds toward the tiers it
        -- does list.
        local entries: { any } = {}
        for rarityId, weight in pairs(egg.odds) do
                if weight > 0 and #Pets.byRarity(rarityId) > 0 then
                        table.insert(entries, { weight = weight, rarity = rarityId })
                end
        end
        if #entries == 0 then
                return nil, "EMPTY_EGG"
        end

        local tierPick = rng:pickWeighted(entries)
        if not tierPick then
                return nil, "EMPTY_EGG"
        end

        local candidates = Pets.byRarity(tierPick.rarity)
        local pet = candidates[rng:nextInteger(1, #candidates)]

        table.insert(inv.owned, { uid = inv.nextUid, petId = pet.id })
        inv.nextUid += 1
        inv.hatches += 1
        return pet.id, nil
end

-- The rarity odds of an egg, normalised, for the shop to display. Derived, so
-- the UI cannot drift from the roll.
function Pets.eggOdds(eggId: string): { { rarity: string, chance: number } }
        local egg = EGGS_BY_ID[eggId]
        if not egg then
                return {}
        end
        local total = eggTotal(egg)
        if total <= 0 then
                return {}
        end
        local out: { { rarity: string, chance: number } } = {}
        for _, rarityId in ipairs(Rarity.ids()) do
                local weight = egg.odds[rarityId]
                if weight and weight > 0 then
                        table.insert(out, { rarity = rarityId, chance = weight / total })
                end
        end
        return out
end

local function findOwned(inv: Inventory, uid: number): { uid: number, petId: string }?
        for _, entry in ipairs(inv.owned) do
                if entry.uid == uid then
                        return entry
                end
        end
        return nil
end

function Pets.isEquipped(inv: Inventory, uid: number): boolean
        for _, slotUid in ipairs(inv.equipped) do
                if slotUid == uid then
                        return true
                end
        end
        return false
end

-- Put a pet in a slot. Fails when the pet is not owned, is already equipped, or
-- every slot is full -- each with its own reason so the client can say why.
function Pets.equip(inv: Inventory, uid: number): (boolean, string?)
        if not findOwned(inv, uid) then
                return false, "NOT_OWNED"
        end
        if Pets.isEquipped(inv, uid) then
                return false, "ALREADY_EQUIPPED"
        end
        if #inv.equipped >= Config.Pets.MaxEquipped then
                return false, "SLOTS_FULL"
        end
        table.insert(inv.equipped, uid)
        return true, nil
end

function Pets.unequip(inv: Inventory, uid: number): (boolean, string?)
        for i, slotUid in ipairs(inv.equipped) do
                if slotUid == uid then
                        table.remove(inv.equipped, i)
                        return true, nil
                end
        end
        return false, "NOT_EQUIPPED"
end

-- Combined multipliers from every equipped pet, and only from pets the player
-- still owns. An equipped uid whose pet was lost is ignored rather than
-- erroring, so a corrupt save cannot brick a player's garden.
function Pets.bonuses(inv: Inventory): { growth: number, value: number }
        local growth = 1
        local value = 1
        for _, uid in ipairs(inv.equipped) do
                local entry = findOwned(inv, uid)
                if entry then
                        local def = BY_ID[entry.petId]
                        if def then
                                growth *= def.growthMultiplier
                                value *= def.valueMultiplier
                        end
                end
        end
        return { growth = growth, value = value }
end

-- Drop any equipped uid that is not owned. Called after loading a save.
function Pets.prune(inv: Inventory): number
        local kept: { number } = {}
        for _, uid in ipairs(inv.equipped) do
                if findOwned(inv, uid) and #kept < Config.Pets.MaxEquipped then
                        table.insert(kept, uid)
                end
        end
        local removed = #inv.equipped - #kept
        inv.equipped = kept
        return removed
end

return Pets

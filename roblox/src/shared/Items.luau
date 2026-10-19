--!strict
-- Items, equipment and drop tables. Pure Luau.
--
-- Three kinds of thing live here:
--
--   * Equipment, which occupies a slot and adds attributes while worn.
--   * Consumables, which are used up and do something once.
--   * Materials, which do nothing yet and are the reason to keep killing.
--
-- Drop tables are per monster, not per field, so a rare monster is worth
-- hunting on purpose rather than being a recoloured common one.

local Config = require("./Config")

local Items = {}

export type Kind = "equipment" | "consumable" | "material"

export type ItemDef = {
        id: string,
        name: string,
        kind: Kind,
        -- How many fit in one backpack slot.
        maxStack: number,
        rarity: string,
        -- Equipment only: which slot it fills.
        slot: string?,
        -- Equipment only: two-handed weapons also block the shield slot.
        twoHanded: boolean?,
        -- Equipment only: attribute additions while worn.
        bonus: { [string]: number },
        -- Equipment only: minimum base level to wear it.
        levelRequirement: number,
        -- Equipment only: extra attack/defense on top of the attributes.
        attack: number,
        defense: number,
        -- Consumable only: what using it does.
        effect: string?,
        amount: number,
        -- Where it comes from, shown in the tooltip.
        source: string,
}

local DEFS: { [string]: ItemDef } = {}
local ORDER: { string } = {}

local function add(def: ItemDef)
        DEFS[def.id] = def
        table.insert(ORDER, def.id)
end

local function equip(
        id: string,
        name: string,
        slot: string,
        levelRequirement: number,
        bonus: { [string]: number },
        attack: number,
        defense: number,
        rarity: string,
        source: string,
        twoHanded: boolean?
)
        add({
                id = id,
                name = name,
                kind = "equipment",
                maxStack = 1,
                rarity = rarity,
                slot = slot,
                twoHanded = twoHanded == true,
                bonus = bonus,
                levelRequirement = levelRequirement,
                attack = attack,
                defense = defense,
                effect = nil,
                amount = 0,
                source = source,
        })
end

local function consumable(
        id: string,
        name: string,
        effect: string,
        amount: number,
        maxStack: number,
        rarity: string,
        source: string
)
        add({
                id = id,
                name = name,
                kind = "consumable",
                maxStack = maxStack,
                rarity = rarity,
                slot = nil,
                twoHanded = false,
                bonus = {},
                levelRequirement = 1,
                attack = 0,
                defense = 0,
                effect = effect,
                amount = amount,
                source = source,
        })
end

local function material(id: string, name: string, maxStack: number, rarity: string, source: string)
        add({
                id = id,
                name = name,
                kind = "material",
                maxStack = maxStack,
                rarity = rarity,
                slot = nil,
                twoHanded = false,
                bonus = {},
                levelRequirement = 1,
                attack = 0,
                defense = 0,
                effect = nil,
                amount = 0,
                source = source,
        })
end

--------------------------------------------------------------------------
-- Weapons. A weapon is the single biggest lever on damage, and the class
-- determines which one is worth carrying.
--------------------------------------------------------------------------

equip("NoviceKnife", "Novice Knife", "Weapon", 1, { STR = 1 }, 4, 0, "common", "Starting gear")
equip("ShortSword", "Short Sword", "Weapon", 3, { STR = 2 }, 9, 0, "common", "Meadow")
equip("LongSword", "Long Sword", "Weapon", 8, { STR = 3 }, 16, 0, "uncommon", "Meadow, Cavern")
equip("BroadSword", "Broad Sword", "Weapon", 15, { STR = 4, VIT = 2 }, 26, 0, "rare", "Cavern")
equip("Claymore", "Claymore", "Weapon", 25, { STR = 6, VIT = 3 }, 44, 0, "rare", "Cavern, Volcano", true)
equip("DragonSlayer", "Dragon Slayer", "Weapon", 40, { STR = 10, VIT = 5 }, 78, 0, "epic", "Volcano, Void", true)

equip("ShortBow", "Short Bow", "Weapon", 3, { DEX = 2 }, 8, 0, "common", "Meadow")
equip("HunterBow", "Hunter Bow", "Weapon", 12, { DEX = 4, AGI = 2 }, 22, 0, "uncommon", "Meadow, Cavern", true)
equip("GreatBow", "Great Bow", "Weapon", 25, { DEX = 7, AGI = 3 }, 46, 0, "rare", "Cavern, Volcano", true)
equip("ArtemisBow", "Artemis Bow", "Weapon", 40, { DEX = 11, AGI = 5 }, 82, 0, "epic", "Void, Heaven", true)

equip("NoviceRod", "Novice Rod", "Weapon", 3, { INT = 2 }, 4, 0, "common", "Meadow")
equip("BoneWand", "Bone Wand", "Weapon", 12, { INT = 5 }, 12, 0, "uncommon", "Cavern")
equip("StaffOfFire", "Staff of Fire", "Weapon", 25, { INT = 8, DEX = 2 }, 26, 0, "rare", "Volcano", true)
equip("ArcWand", "Arc Wand", "Weapon", 40, { INT = 12, DEX = 4 }, 52, 0, "epic", "Void, Heaven", true)

equip("Dagger", "Dagger", "Weapon", 3, { AGI = 2 }, 7, 0, "common", "Meadow")
equip("MainGauche", "Main Gauche", "Weapon", 12, { AGI = 4, LUK = 2 }, 18, 0, "uncommon", "Cavern")
equip("Katar", "Katar", "Weapon", 25, { AGI = 6, LUK = 4, STR = 2 }, 40, 0, "rare", "Volcano", true)
equip("Jur", "Jur", "Weapon", 40, { AGI = 10, LUK = 7, STR = 4 }, 72, 0, "epic", "Void, Heaven", true)

equip("NoviceMace", "Novice Mace", "Weapon", 3, { INT = 1, VIT = 1 }, 6, 0, "common", "Meadow")
equip("Mace", "Mace", "Weapon", 12, { INT = 3, VIT = 3 }, 16, 0, "uncommon", "Cavern")
equip("WarMace", "War Mace", "Weapon", 25, { INT = 6, VIT = 5 }, 34, 0, "rare", "Volcano")
equip("DivineMace", "Divine Mace", "Weapon", 40, { INT = 9, VIT = 8 }, 62, 0, "epic", "Void, Heaven")

--------------------------------------------------------------------------
-- Armour. Defense matters more as the fields get harsher, and the VIT on
-- these is what makes a tanky build possible without spending every point.
--------------------------------------------------------------------------

equip("CottonShirt", "Cotton Shirt", "Body", 1, { VIT = 1 }, 0, 6, "common", "Starting gear")
equip("LeatherArmor", "Leather Armor", "Body", 8, { VIT = 3 }, 0, 16, "uncommon", "Meadow, Cavern")
equip("ChainMail", "Chain Mail", "Body", 20, { VIT = 6 }, 0, 34, "rare", "Cavern, Volcano")
equip("PlateArmor", "Plate Armor", "Body", 35, { VIT = 10, STR = 3 }, 0, 62, "epic", "Volcano, Void")

equip("LeatherCap", "Leather Cap", "Head", 5, { VIT = 2 }, 0, 8, "common", "Meadow")
equip("IronHelm", "Iron Helm", "Head", 18, { VIT = 4, STR = 1 }, 0, 20, "uncommon", "Cavern")
equip("Crown", "Crown", "Head", 35, { VIT = 6, INT = 4 }, 0, 32, "rare", "Volcano, Void")

equip("Hood", "Hood", "Garment", 5, { AGI = 2 }, 0, 5, "common", "Meadow")
equip("Muffler", "Muffler", "Garment", 18, { AGI = 5 }, 0, 14, "uncommon", "Cavern")
equip("WindCloak", "Wind Cloak", "Garment", 32, { AGI = 9, DEX = 3 }, 0, 26, "rare", "Volcano, Void")

equip("Sandals", "Sandals", "Shoes", 5, { AGI = 1 }, 0, 4, "common", "Meadow")
equip("Boots", "Boots", "Shoes", 18, { AGI = 4, VIT = 2 }, 0, 12, "uncommon", "Cavern")
equip("Greaves", "Greaves", "Shoes", 32, { AGI = 7, VIT = 4 }, 0, 24, "rare", "Volcano, Void")

equip("WoodenShield", "Wooden Shield", "Shield", 8, { VIT = 2 }, 0, 12, "common", "Meadow")
equip("Buckler", "Buckler", "Shield", 20, { VIT = 4, AGI = 1 }, 0, 26, "uncommon", "Cavern")
equip("GuardianShield", "Guardian Shield", "Shield", 35, { VIT = 8 }, 0, 48, "rare", "Volcano, Void")

equip("RingOfStrength", "Ring of Strength", "Accessory1", 12, { STR = 3 }, 0, 0, "uncommon", "Cavern")
equip("RingOfWisdom", "Ring of Wisdom", "Accessory1", 12, { INT = 3 }, 0, 0, "uncommon", "Cavern")
equip("RingOfSpeed", "Ring of Speed", "Accessory1", 12, { AGI = 3 }, 0, 0, "uncommon", "Cavern")
equip("AmuletOfLuck", "Amulet of Luck", "Accessory1", 25, { LUK = 5 }, 0, 0, "rare", "Volcano")
equip("VoidPendant", "Void Pendant", "Accessory1", 40, { STR = 5, INT = 5, AGI = 5 }, 0, 0, "epic", "Void, Heaven")

--------------------------------------------------------------------------
-- Consumables.
--------------------------------------------------------------------------

consumable("RedPotion", "Red Potion", "heal", 0.35, 30, "common", "Drops and shop")
consumable("RedPotionBig", "Large Red Potion", "heal", 0.7, 20, "uncommon", "Drops and shop")
consumable("BluePotion", "Blue Potion", "sp", 0.5, 30, "common", "Drops and shop")
consumable("BluePotionBig", "Large Blue Potion", "sp", 1.0, 20, "uncommon", "Drops and shop")
consumable("SpeedPotion", "Speed Potion", "speed", 10, 10, "rare", "Drops")
consumable("LuckPotion", "Luck Potion", "luck", 5, 10, "rare", "Drops")

--------------------------------------------------------------------------
-- Materials. Worth collecting, and the reason a specific monster is worth
-- farming rather than whichever one is closest.
--------------------------------------------------------------------------

material("Jellopy", "Jellopy", 99, "common", "Slimes")
material("Fluff", "Fluff", 99, "common", "Hornets and bats")
material("Chitin", "Chitin", 99, "common", "Scorpions")
material("Stone", "Stone Shard", 99, "common", "Golems")
material("IronOre", "Iron Ore", 50, "uncommon", "Cavern monsters")
material("Crystal", "Crystal Shard", 25, "rare", "Crystal monsters")
material("Ember", "Ember Core", 25, "rare", "Volcano monsters")
material("RiftShard", "Rift Shard", 25, "rare", "Void monsters")
material("CelestialFeather", "Celestial Feather", 10, "epic", "Heaven monsters")
material("BossToken", "Boss Token", 20, "legendary", "Field bosses")

--------------------------------------------------------------------------
-- Drop tables. `chance` is a 0..1 probability rolled once per kill; the
-- server rolls it, never the client.
--------------------------------------------------------------------------

export type DropEntry = { itemId: string, chance: number, min: number, max: number }

local DROPS: { [string]: { DropEntry } } = {}

local function drops(monster: string, entries: { DropEntry })
        DROPS[monster] = entries
end

-- A generic table every monster rolls as well, so no kill is ever empty.
local COMMON: { DropEntry } = {
        { itemId = "RedPotion", chance = 0.18, min = 1, max = 2 },
        { itemId = "BluePotion", chance = 0.10, min = 1, max = 2 },
}

drops("Slime", {
        { itemId = "Jellopy", chance = 0.55, min = 1, max = 3 },
        { itemId = "NoviceKnife", chance = 0.03, min = 1, max = 1 },
        { itemId = "CottonShirt", chance = 0.03, min = 1, max = 1 },
})
drops("Hornet", {
        { itemId = "Fluff", chance = 0.5, min = 1, max = 2 },
        { itemId = "ShortBow", chance = 0.03, min = 1, max = 1 },
})
drops("SlimeKing", {
        { itemId = "BossToken", chance = 1.0, min = 1, max = 1 },
        { itemId = "LongSword", chance = 0.5, min = 1, max = 1 },
        { itemId = "Jellopy", chance = 1.0, min = 5, max = 12 },
        { itemId = "RedPotionBig", chance = 0.6, min = 1, max = 3 },
})

drops("CaveBat", {
        { itemId = "Fluff", chance = 0.45, min = 1, max = 2 },
        { itemId = "BluePotion", chance = 0.15, min = 1, max = 2 },
})
drops("RockGolem", {
        { itemId = "Stone", chance = 0.6, min = 1, max = 3 },
        { itemId = "IronOre", chance = 0.3, min = 1, max = 2 },
        { itemId = "Buckler", chance = 0.05, min = 1, max = 1 },
})
drops("CrystalGolem", {
        { itemId = "BossToken", chance = 1.0, min = 1, max = 1 },
        { itemId = "Crystal", chance = 0.9, min = 2, max = 5 },
        { itemId = "BroadSword", chance = 0.4, min = 1, max = 1 },
        { itemId = "RingOfStrength", chance = 0.3, min = 1, max = 1 },
})

drops("Scorpion", {
        { itemId = "Chitin", chance = 0.5, min = 1, max = 2 },
        { itemId = "RingOfSpeed", chance = 0.04, min = 1, max = 1 },
})
drops("SandWraith", {
        { itemId = "Crystal", chance = 0.4, min = 1, max = 2 },
        { itemId = "SpeedPotion", chance = 0.15, min = 1, max = 1 },
})
drops("SandWraithBoss", {
        { itemId = "BossToken", chance = 1.0, min = 1, max = 1 },
        { itemId = "AmuletOfLuck", chance = 0.5, min = 1, max = 1 },
        { itemId = "Katar", chance = 0.4, min = 1, max = 1 },
})

drops("EmberImp", {
        { itemId = "Ember", chance = 0.45, min = 1, max = 2 },
        { itemId = "StaffOfFire", chance = 0.03, min = 1, max = 1 },
})
drops("MagmaHound", {
        { itemId = "Ember", chance = 0.55, min = 1, max = 3 },
        { itemId = "IronOre", chance = 0.3, min = 1, max = 2 },
})
drops("VolcanoDragon", {
        { itemId = "BossToken", chance = 1.0, min = 1, max = 2 },
        { itemId = "DragonSlayer", chance = 0.4, min = 1, max = 1 },
        { itemId = "PlateArmor", chance = 0.35, min = 1, max = 1 },
        { itemId = "Ember", chance = 1.0, min = 5, max = 10 },
})

drops("VoidWisp", {
        { itemId = "RiftShard", chance = 0.45, min = 1, max = 2 },
        { itemId = "LuckPotion", chance = 0.12, min = 1, max = 1 },
})
drops("RiftStalker", {
        { itemId = "RiftShard", chance = 0.55, min = 1, max = 3 },
        { itemId = "ArcWand", chance = 0.04, min = 1, max = 1 },
})
drops("VoidSovereign", {
        { itemId = "BossToken", chance = 1.0, min = 2, max = 4 },
        { itemId = "VoidPendant", chance = 0.6, min = 1, max = 1 },
        { itemId = "Jur", chance = 0.4, min = 1, max = 1 },
        { itemId = "ArtemisBow", chance = 0.35, min = 1, max = 1 },
        { itemId = "DivineMace", chance = 0.35, min = 1, max = 1 },
})

drops("CelestialGuard", {
        { itemId = "CelestialFeather", chance = 0.5, min = 1, max = 2 },
        { itemId = "Crown", chance = 0.05, min = 1, max = 1 },
})
drops("Seraph", {
        { itemId = "CelestialFeather", chance = 0.7, min = 1, max = 3 },
        { itemId = "ArcWand", chance = 0.05, min = 1, max = 1 },
})
drops("HeavenGate", {
        { itemId = "BossToken", chance = 1.0, min = 3, max = 6 },
        { itemId = "CelestialFeather", chance = 1.0, min = 5, max = 12 },
        { itemId = "VoidPendant", chance = 0.7, min = 1, max = 1 },
        { itemId = "ArtemisBow", chance = 0.45, min = 1, max = 1 },
        { itemId = "DivineMace", chance = 0.45, min = 1, max = 1 },
        { itemId = "DragonSlayer", chance = 0.45, min = 1, max = 1 },
})

--------------------------------------------------------------------------

function Items.getDef(itemId: string): ItemDef?
        return DEFS[itemId]
end

function Items.list(): { ItemDef }
        local out: { ItemDef } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, DEFS[id])
        end
        return out
end

function Items.byKind(kind: Kind): { ItemDef }
        local out: { ItemDef } = {}
        for _, id in ipairs(ORDER) do
                if DEFS[id].kind == kind then
                        table.insert(out, DEFS[id])
                end
        end
        return out
end

function Items.slots(): { string }
        local out: { string } = {}
        for _, slot in ipairs(Config.Equipment.Slots) do
                table.insert(out, slot)
        end
        return out
end

-- The drop table for a monster, plus the generic rolls every monster gets.
function Items.dropsFor(monster: string): { DropEntry }
        local out: { DropEntry } = {}
        for _, entry in ipairs(COMMON) do
                table.insert(out, entry)
        end
        for _, entry in ipairs(DROPS[monster] or {}) do
                table.insert(out, entry)
        end
        return out
end

-- Roll one kill's drops. `rng` is the game RNG; `luckMultiplier` raises the
-- chance of anything above "common", the same way it does elsewhere.
-- Returns a list of { itemId, count }.
function Items.rollDrops(monster: string, rng, luckMultiplier: number?): { any }
        local luck = math.max(1, luckMultiplier or 1)
        local out: { any } = {}

        for _, entry in ipairs(Items.dropsFor(monster)) do
                local def = DEFS[entry.itemId]
                if def then
                        local rarityFactor = def.rarity == "common" and 1 or luck
                        local chance = math.min(1, entry.chance * rarityFactor)
                        if rng:nextNumber() < chance then
                                local count = entry.min
                                if entry.max > entry.min then
                                        count = rng:nextInteger(entry.min, entry.max)
                                end
                                table.insert(out, { itemId = entry.itemId, count = math.max(1, count) })
                        end
                end
        end

        return out
end

-- Combined attribute bonus of a set of worn items, so the stat sheet can be
-- rebuilt from equipment in one call.
function Items.equipmentBonus(worn: { [string]: string? }): { [string]: number }
        local bonus: { [string]: number } = {}
        for _, itemId in pairs(worn or {}) do
                local def = itemId and DEFS[itemId]
                if def and def.kind == "equipment" then
                        for name, value in pairs(def.bonus) do
                                bonus[name] = (bonus[name] or 0) + value
                        end
                end
        end
        return bonus
end

-- Extra flat attack and defense from worn equipment. Kept separate from the
-- attribute bonus because these are added after the stat sheet is derived.
function Items.equipmentCombat(worn: { [string]: string? }): { attack: number, defense: number }
        local attack, defense = 0, 0
        for _, itemId in pairs(worn or {}) do
                local def = itemId and DEFS[itemId]
                if def and def.kind == "equipment" then
                        attack += def.attack
                        defense += def.defense
                end
        end
        return { attack = attack, defense = defense }
end

-- Can this character wear the item? Returns (ok, reason).
function Items.canEquip(itemId: string, level: number, worn: { [string]: string? }): (boolean, string?)
        local def = DEFS[itemId]
        if not def then
                return false, "UNKNOWN_ITEM"
        end
        if def.kind ~= "equipment" then
                return false, "NOT_EQUIPMENT"
        end
        if level < def.levelRequirement then
                return false, "LEVEL_TOO_LOW"
        end

        -- A two-handed weapon blocks a shield, and a shield blocks a
        -- two-handed weapon. One of the two has to give.
        if def.twoHanded then
                return true, nil
        end
        if def.slot == "Shield" then
                local weaponId = worn.Weapon
                local weapon = weaponId and DEFS[weaponId]
                if weapon and weapon.twoHanded then
                        return false, "WEAPON_IS_TWO_HANDED"
                end
        end

        return true, nil
end

-- Wear an item, returning the new slot map. A two-handed weapon clears the
-- shield slot; a shield clears a two-handed weapon.
function Items.equipTo(worn: { [string]: string? }, itemId: string): { [string]: string? }
        local def = DEFS[itemId]
        if not def or def.kind ~= "equipment" or not def.slot then
                return worn
        end

        local next: { [string]: string? } = {}
        for slot, id in pairs(worn) do
                next[slot] = id
        end

        if def.twoHanded then
                for _, slot in ipairs(Config.Equipment.TwoHandedSlots) do
                        next[slot] = itemId
                end
                return next
        end

        if def.slot == "Shield" then
                local weaponId = next.Weapon
                local weapon = weaponId and DEFS[weaponId]
                if weapon and weapon.twoHanded then
                        next.Weapon = nil
                end
        end

        next[def.slot] = itemId
        return next
end

-- Take an item off. Returns the new slot map.
function Items.unequipFrom(worn: { [string]: string? }, slot: string): { [string]: string? }
        local next: { [string]: string? } = {}
        local removing = worn[slot]
        for s, id in pairs(worn) do
                -- A two-handed weapon fills two slots, so removing it has to
                -- clear both or the shield slot keeps a ghost.
                if s ~= slot and not (removing and id == removing) then
                        next[s] = id
                end
        end
        return next
end

-- Total defense from attributes plus armour, used by the damage path.
function Items.totalDefense(derived: any, worn: { [string]: string? }): number
        local combat = Items.equipmentCombat(worn)
        return (derived.defense or 0) + combat.defense
end

-- Total attack from attributes plus weapons.
function Items.totalAttack(derived: any, worn: { [string]: string? }): number
        local combat = Items.equipmentCombat(worn)
        return (derived.attack or 0) + combat.attack
end

return Items

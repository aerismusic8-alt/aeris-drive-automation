--!strict
-- Item icons. Pure Luau.
--
-- The bag used to be a list of text rows, so a Claymore and a Red Potion read
-- as the same thing: a word with a number next to it. An icon is a small recipe
-- of parts the client draws inside a ViewportFrame, so an item looks like the
-- object it is and two weapons do not share a silhouette.
--
-- Icon space: the origin is the centre of the tile, +Y is up, -Z faces the
-- camera. Everything fits inside roughly a 1x1x1 box so the client can scale a
-- tile without re-measuring. It uses the same part vocabulary as
-- MonsterShapes, so the same builder handles monsters, class accents and icons.

local ItemIcons = {}

export type Shape = "Block" | "Ball" | "Cylinder" | "Wedge"

export type Part = {
        name: string,
        shape: Shape,
        size: { number },
        at: { number },
        color: { number },
        rot: { number }?,
}

export type Icon = {
        parts: { Part },
        -- Rotation applied to the whole icon so a sword reads as diagonal.
        tilt: { number },
}

local function p(
        name: string,
        shape: Shape,
        size: { number },
        at: { number },
        color: { number },
        rot: { number }?
): Part
        return { name = name, shape = shape, size = size, at = at, color = color, rot = rot }
end

--------------------------------------------------------------------------
-- Materials by rarity, so a common and an epic shard differ at a glance.
--------------------------------------------------------------------------

local RARITY_COLOR: { [string]: { number } } = {
        common = { 170, 175, 185 },
        uncommon = { 110, 200, 130 },
        rare = { 100, 165, 255 },
        epic = { 200, 120, 245 },
        legendary = { 255, 200, 90 },
}

local WOOD = { 150, 110, 70 }
local STEEL = { 205, 212, 224 }
local STEEL_DARK = { 150, 158, 172 }
local GOLD = { 240, 205, 110 }
local LEATHER = { 140, 100, 65 }
local CLOTH = { 225, 225, 232 }

local function rarityColor(rarity: string?): { number }
        return RARITY_COLOR[rarity or "common"] or RARITY_COLOR.common
end

--------------------------------------------------------------------------
-- Weapon silhouettes. Each is built along the tile's diagonal so it fills the
-- square rather than sitting as a thin vertical line.
--------------------------------------------------------------------------

local function sword(bladeColor: { number }, guardColor: { number }, bladeLength: number): { Part }
        return {
                p("Blade", "Block", { 0.16, bladeLength, 0.34 }, { 0, bladeLength * 0.12, 0 }, bladeColor),
                p("Tip", "Wedge", { 0.16, 0.3, 0.34 }, { 0, bladeLength * 0.62 + 0.15, 0 }, bladeColor, { 180, 0, 0 }),
                p("Guard", "Block", { 0.85, 0.12, 0.22 }, { 0, -bladeLength * 0.38, 0 }, guardColor),
                p("Grip", "Cylinder", { 0.42, 0.13, 0.13 }, { 0, -bladeLength * 0.55, 0 }, LEATHER),
                p("Pommel", "Ball", { 0.2, 0.2, 0.2 }, { 0, -bladeLength * 0.75, 0 }, guardColor),
        }
end

local function dagger(): { Part }
        return {
                p("Blade", "Block", { 0.13, 0.9, 0.26 }, { 0, 0.16, 0 }, STEEL),
                p("Tip", "Wedge", { 0.13, 0.22, 0.26 }, { 0, 0.7, 0 }, STEEL, { 180, 0, 0 }),
                p("Guard", "Block", { 0.55, 0.1, 0.18 }, { 0, -0.32, 0 }, STEEL_DARK),
                p("Grip", "Cylinder", { 0.34, 0.11, 0.11 }, { 0, -0.5, 0 }, LEATHER),
        }
end

local function bow(limbColor: { number }): { Part }
        return {
                p("LimbTop", "Cylinder", { 0.9, 0.1, 0.1 }, { 0.18, 0.42, 0 }, limbColor, { 0, 0, 12 }),
                p("LimbBottom", "Cylinder", { 0.9, 0.1, 0.1 }, { 0.18, -0.42, 0 }, limbColor, { 0, 0, -12 }),
                p("Grip", "Cylinder", { 0.34, 0.13, 0.13 }, { 0.02, 0, 0 }, LEATHER),
                p("String", "Block", { 0.05, 1.6, 0.05 }, { -0.28, 0, 0 }, CLOTH),
                p("Arrow", "Block", { 0.06, 1.5, 0.06 }, { -0.14, 0, 0 }, WOOD, { 0, 0, 8 }),
                p("Head", "Wedge", { 0.16, 0.26, 0.16 }, { -0.03, 0.78, 0 }, STEEL, { 180, 0, 8 }),
        }
end

local function staff(woodColor: { number }, orbColor: { number }): { Part }
        return {
                p("Shaft", "Cylinder", { 1.7, 0.11, 0.11 }, { 0, -0.12, 0 }, woodColor),
                p("Collar", "Cylinder", { 0.12, 0.24, 0.24 }, { 0, 0.72, 0 }, GOLD),
                p("Orb", "Ball", { 0.5, 0.5, 0.5 }, { 0, 1.0, 0 }, orbColor),
                p("SparkL", "Wedge", { 0.14, 0.3, 0.14 }, { -0.34, 1.12, 0 }, orbColor, { 0, 0, -35 }),
                p("SparkR", "Wedge", { 0.14, 0.3, 0.14 }, { 0.34, 1.12, 0 }, orbColor, { 0, 0, 35 }),
        }
end

local function mace(headColor: { number }): { Part }
        return {
                p("Shaft", "Cylinder", { 1.2, 0.13, 0.13 }, { 0, -0.35, 0 }, WOOD),
                p("Head", "Ball", { 0.62, 0.62, 0.62 }, { 0, 0.42, 0 }, headColor),
                p("SpikeUp", "Wedge", { 0.2, 0.34, 0.2 }, { 0, 0.9, 0 }, headColor),
                p("SpikeL", "Wedge", { 0.2, 0.3, 0.2 }, { -0.5, 0.42, 0 }, headColor, { 0, 0, -70 }),
                p("SpikeR", "Wedge", { 0.2, 0.3, 0.2 }, { 0.5, 0.42, 0 }, headColor, { 0, 0, 70 }),
                p("Band", "Cylinder", { 0.1, 0.2, 0.2 }, { 0, 0.05, 0 }, GOLD),
        }
end

local function shield(): { Part }
        return {
                p("Face", "Block", { 0.8, 0.95, 0.14 }, { 0, 0, 0 }, LEATHER),
                p("Boss", "Ball", { 0.28, 0.28, 0.28 }, { 0, 0.02, -0.14 }, GOLD),
                p("Band", "Block", { 0.82, 0.1, 0.16 }, { 0, 0.3, 0 }, STEEL_DARK),
                p("BandLow", "Block", { 0.82, 0.1, 0.16 }, { 0, -0.3, 0 }, STEEL_DARK),
        }
end

local function armour(color: { number }, trim: { number }): { Part }
        return {
                p("Chest", "Block", { 0.85, 0.9, 0.34 }, { 0, 0.05, 0 }, color),
                p("Collar", "Block", { 0.5, 0.14, 0.3 }, { 0, 0.55, 0 }, trim),
                p("Waist", "Block", { 0.8, 0.14, 0.34 }, { 0, -0.4, 0 }, trim),
                p("ShoulderL", "Block", { 0.24, 0.26, 0.32 }, { -0.5, 0.36, 0 }, trim),
                p("ShoulderR", "Block", { 0.24, 0.26, 0.32 }, { 0.5, 0.36, 0 }, trim),
        }
end

local function helm(color: { number }, trim: { number }): { Part }
        return {
                p("Dome", "Ball", { 0.78, 0.72, 0.78 }, { 0, 0.05, 0 }, color),
                p("Brim", "Cylinder", { 0.14, 0.95, 0.95 }, { 0, -0.22, 0 }, trim),
                p("Crest", "Wedge", { 0.16, 0.5, 0.5 }, { 0, 0.45, 0 }, trim, { -18, 0, 0 }),
        }
end

local function cloak(color: { number }, trim: { number }): { Part }
        return {
                p("Cloth", "Block", { 0.9, 1.1, 0.14 }, { 0, -0.05, 0 }, color),
                p("Hood", "Ball", { 0.42, 0.42, 0.42 }, { 0, 0.55, 0 }, color),
                p("Clasp", "Ball", { 0.16, 0.16, 0.16 }, { 0, 0.42, -0.12 }, trim),
                p("Hem", "Block", { 0.92, 0.1, 0.16 }, { 0, -0.58, 0 }, trim),
        }
end

local function boots(): { Part }
        return {
                p("BootL", "Block", { 0.3, 0.7, 0.5 }, { -0.22, 0, 0 }, LEATHER),
                p("BootR", "Block", { 0.3, 0.7, 0.5 }, { 0.22, 0, 0 }, LEATHER),
                p("SoleL", "Block", { 0.32, 0.12, 0.52 }, { -0.22, -0.4, 0 }, STEEL_DARK),
                p("SoleR", "Block", { 0.32, 0.12, 0.52 }, { 0.22, -0.4, 0 }, STEEL_DARK),
                p("StrapL", "Block", { 0.32, 0.1, 0.52 }, { -0.22, 0.22, 0 }, GOLD),
                p("StrapR", "Block", { 0.32, 0.1, 0.52 }, { 0.22, 0.22, 0 }, GOLD),
        }
end

local function ring(gem: { number }): { Part }
        return {
                p("Band", "Cylinder", { 0.12, 0.7, 0.7 }, { 0, -0.06, 0 }, GOLD, { 0, 0, 90 }),
                p("Gem", "Ball", { 0.32, 0.32, 0.32 }, { 0, 0.36, 0 }, gem),
                p("ProngL", "Wedge", { 0.1, 0.2, 0.1 }, { -0.18, 0.2, 0 }, GOLD),
                p("ProngR", "Wedge", { 0.1, 0.2, 0.1 }, { 0.18, 0.2, 0 }, GOLD),
        }
end

local function potion(liquid: { number }, large: boolean): { Part }
        local bodyH = large and 0.95 or 0.7
        local bodyW = large and 0.72 or 0.56
        return {
                p("Glass", "Ball", { bodyW, bodyH, bodyW }, { 0, -0.1, 0 }, { 205, 225, 240 }),
                p("Liquid", "Ball", { bodyW * 0.82, bodyH * 0.62, bodyW * 0.82 }, { 0, -0.2, 0 }, liquid),
                p("Neck", "Cylinder", { 0.26, 0.2, 0.2 }, { 0, bodyH * 0.5 - 0.05, 0 }, { 205, 225, 240 }),
                p("Cork", "Cylinder", { 0.14, 0.22, 0.22 }, { 0, bodyH * 0.5 + 0.16, 0 }, LEATHER),
                p("Label", "Block", { bodyW * 0.7, 0.16, 0.04 }, { 0, -0.1, -bodyW * 0.52 }, CLOTH),
        }
end

local function crystal(gem: { number }): { Part }
        return {
                p("ShardC", "Wedge", { 0.42, 1.0, 0.42 }, { 0, 0.1, 0 }, gem),
                p("ShardL", "Wedge", { 0.28, 0.66, 0.28 }, { -0.34, -0.16, 0.06 }, gem, { 0, 0, -16 }),
                p("ShardR", "Wedge", { 0.28, 0.66, 0.28 }, { 0.34, -0.16, -0.06 }, gem, { 0, 0, 16 }),
                p("Base", "Block", { 0.7, 0.16, 0.5 }, { 0, -0.55, 0 }, STEEL_DARK),
        }
end

local function ore(chunk: { number }): { Part }
        return {
                p("Rock", "Block", { 0.85, 0.7, 0.7 }, { 0, -0.02, 0 }, { 120, 118, 120 }),
                p("VeinA", "Ball", { 0.26, 0.26, 0.26 }, { -0.2, 0.16, -0.3 }, chunk),
                p("VeinB", "Ball", { 0.2, 0.2, 0.2 }, { 0.24, -0.06, -0.28 }, chunk),
                p("VeinC", "Ball", { 0.16, 0.16, 0.16 }, { 0.05, 0.28, -0.3 }, chunk),
        }
end

local function feather(color: { number }): { Part }
        return {
                p("Quill", "Cylinder", { 1.3, 0.07, 0.07 }, { 0, 0, 0 }, CLOTH, { 0, 0, 18 }),
                p("VaneA", "Wedge", { 0.5, 0.36, 0.06 }, { -0.16, 0.16, 0 }, color, { 0, 0, -12 }),
                p("VaneB", "Wedge", { 0.5, 0.36, 0.06 }, { -0.16, -0.14, 0 }, color, { 0, 0, -12 }),
                p("VaneC", "Wedge", { 0.4, 0.3, 0.06 }, { -0.3, 0.42, 0 }, color, { 0, 0, -12 }),
        }
end

local function token(): { Part }
        return {
                p("Disc", "Cylinder", { 0.16, 0.95, 0.95 }, { 0, 0, 0 }, GOLD, { 0, 0, 90 }),
                p("Inner", "Cylinder", { 0.2, 0.66, 0.66 }, { 0, 0, 0 }, { 170, 130, 40 }, { 0, 0, 90 }),
                p("Gem", "Ball", { 0.34, 0.34, 0.34 }, { 0, 0, 0 }, { 255, 90, 90 }),
        }
end

--------------------------------------------------------------------------
-- Weapon type per item id, so a bow is not drawn as a sword.
--------------------------------------------------------------------------

local WEAPON_STYLE: { [string]: string } = {
        NoviceKnife = "dagger",
        ShortSword = "sword",
        LongSword = "sword",
        BroadSword = "sword",
        Claymore = "sword",
        DragonSlayer = "sword",
        ShortBow = "bow",
        HunterBow = "bow",
        GreatBow = "bow",
        ArtemisBow = "bow",
        NoviceRod = "staff",
        BoneWand = "staff",
        StaffOfFire = "staff",
        ArcWand = "staff",
        Dagger = "dagger",
        MainGauche = "dagger",
        Katar = "dagger",
        Jur = "dagger",
        NoviceMace = "mace",
        Mace = "mace",
        WarMace = "mace",
        DivineMace = "mace",
}

-- Blade length grows with the weapon's attack, so a Claymore is visibly longer
-- than a Short Sword instead of being the same drawing with a bigger number.
local function bladeLength(attack: number): number
        local scaled = 0.9 + math.clamp(attack, 0, 90) / 90 * 0.8
        return math.floor(scaled * 100 + 0.5) / 100
end

--------------------------------------------------------------------------
-- Potion colours, so red heals and blue restores SP at a glance.
--------------------------------------------------------------------------

local POTION_COLOR: { [string]: { number } } = {
        RedPotion = { 225, 60, 65 },
        RedPotionBig = { 235, 45, 55 },
        BluePotion = { 70, 120, 235 },
        BluePotionBig = { 55, 100, 245 },
        SpeedPotion = { 250, 215, 80 },
        LuckPotion = { 170, 110, 235 },
}

--------------------------------------------------------------------------
-- Materials get a shape from their id, so a Crystal Shard and an Iron Ore do
-- not look like the same rock.
--------------------------------------------------------------------------

local MATERIAL_SHAPE: { [string]: string } = {
        Jellopy = "jelly",
        Fluff = "feather",
        Chitin = "ore",
        Stone = "ore",
        IronOre = "ore",
        Crystal = "crystal",
        Ember = "crystal",
        RiftShard = "crystal",
        CelestialFeather = "feather",
        BossToken = "token",
}

local function jelly(color: { number }): { Part }
        return {
                p("Blob", "Ball", { 0.85, 0.8, 0.85 }, { 0, 0, 0 }, color),
                p("Core", "Ball", { 0.32, 0.32, 0.32 }, { 0, -0.02, -0.28 }, { 255, 255, 255 }),
        }
end

--------------------------------------------------------------------------
-- Public API.
--------------------------------------------------------------------------

local TILT: { [string]: { number } } = {
        sword = { 0, 0, 35 },
        dagger = { 0, 0, 30 },
        mace = { 0, 0, 25 },
        staff = { 0, 0, 20 },
        bow = { 0, 0, 0 },
}

-- Build the icon for one item. `def` is the Items.getDef record, so this reads
-- the same fields the rest of the game does and stays in step with the catalogue.
function ItemIcons.get(itemId: string, def: any): Icon
        local kind = def and def.kind or "material"
        local slot = def and def.slot
        local rarity = def and def.rarity
        local attack = def and def.attack or 0
        local tint = rarityColor(rarity)

        if kind == "equipment" then
                if slot == "Weapon" then
                        local style = WEAPON_STYLE[itemId] or "sword"
                        if style == "bow" then
                                return { parts = bow(WOOD), tilt = TILT.bow }
                        elseif style == "staff" then
                                return { parts = staff(WOOD, tint), tilt = TILT.staff }
                        elseif style == "dagger" then
                                return { parts = dagger(), tilt = TILT.dagger }
                        elseif style == "mace" then
                                return { parts = mace(tint), tilt = TILT.mace }
                        end
                        return { parts = sword(STEEL, GOLD, bladeLength(attack)), tilt = TILT.sword }
                elseif slot == "Shield" then
                        return { parts = shield(), tilt = { 0, 0, 0 } }
                elseif slot == "Head" then
                        return { parts = helm(tint, GOLD), tilt = { 0, 0, 0 } }
                elseif slot == "Body" then
                        return { parts = armour(tint, STEEL_DARK), tilt = { 0, 0, 0 } }
                elseif slot == "Garment" then
                        return { parts = cloak(tint, GOLD), tilt = { 0, 0, 0 } }
                elseif slot == "Shoes" then
                        return { parts = boots(), tilt = { 0, 0, 0 } }
                end
                return { parts = ring(tint), tilt = { 0, 0, 0 } }
        end

        if kind == "consumable" then
                local liquid = POTION_COLOR[itemId] or tint
                local large = string.find(itemId, "Big") ~= nil
                return { parts = potion(liquid, large), tilt = { 0, 0, 0 } }
        end

        -- Materials.
        local shape = MATERIAL_SHAPE[itemId] or "ore"
        if shape == "crystal" then
                return { parts = crystal(tint), tilt = { 0, 0, 0 } }
        elseif shape == "feather" then
                return { parts = feather(tint), tilt = { 0, 0, 0 } }
        elseif shape == "token" then
                return { parts = token(), tilt = { 0, 0, 0 } }
        elseif shape == "jelly" then
                return { parts = jelly(tint), tilt = { 0, 0, 0 } }
        end
        return { parts = ore(tint), tilt = { 0, 0, 0 } }
end

-- Which slot each icon style is expected for. The tests use this to prove a
-- weapon is never drawn with an armour icon.
ItemIcons.WEAPON_STYLE = WEAPON_STYLE
ItemIcons.MATERIAL_SHAPE = MATERIAL_SHAPE
ItemIcons.POTION_COLOR = POTION_COLOR

return ItemIcons

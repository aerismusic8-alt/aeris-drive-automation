--!strict
-- Monster silhouettes. Pure Luau: no Roblox globals, so the recipes are unit
-- testable and the server is the only place that turns them into parts.
--
-- Every archetype used to be the same box in a different colour, which made a
-- Rock Golem and a Hornet read as the same creature. A recipe is a small list
-- of parts in "creature space": the origin sits on the ground, +Y is up, and
-- the whole thing is roughly ENEMY_UNIT_HEIGHT studs tall before the server
-- scales it by the monster's sizeMul.
--
-- Shapes are deliberately limited to the four primitives Roblox can build from
-- a Part or a WedgePart, so nothing here needs a mesh asset that a Rojo build
-- cannot ship.

local MonsterShapes = {}

export type Shape = "Block" | "Ball" | "Cylinder" | "Wedge"

-- Where a part takes its colour from. "body" is the archetype's own colour, so
-- a monster still reads as itself even when its silhouette changes.
export type ColorRole = "body" | "dark" | "light" | "accent" | "eye" | "metal"

export type Part = {
        name: string,
        shape: Shape,
        size: { number },
        at: { number },
        color: ColorRole,
        rot: { number }?,
}

export type Recipe = {
        -- The part the server uses as the model pivot and the health-bar anchor.
        primary: string,
        parts: { Part },
}

-- The height a recipe is drawn at, in studs. World scales from here.
MonsterShapes.UNIT_HEIGHT = 5

local function part(name: string, shape: Shape, size: { number }, at: { number }, color: ColorRole, rot: { number }?): Part
        return { name = name, shape = shape, size = size, at = at, color = color, rot = rot }
end

--------------------------------------------------------------------------
-- Body plans. Each returns a full recipe so a family is described once and
-- reused by every monster that shares its shape.
--------------------------------------------------------------------------

-- A single round body with two eyes. Poring and friends.
local function orb(bodySize: number): { Part }
        return {
                part("Body", "Ball", { bodySize, bodySize, bodySize }, { 0, bodySize / 2, 0 }, "body"),
                part("EyeL", "Ball", { 0.5, 0.5, 0.5 }, { -bodySize * 0.22, bodySize * 0.62, -bodySize * 0.42 }, "eye"),
                part("EyeR", "Ball", { 0.5, 0.5, 0.5 }, { bodySize * 0.22, bodySize * 0.62, -bodySize * 0.42 }, "eye"),
                part("Mouth", "Block", { bodySize * 0.34, 0.18, 0.2 }, { 0, bodySize * 0.32, -bodySize * 0.48 }, "dark"),
        }
end

-- A squat dome, wider than it is tall. Slimes and toads.
local function blob(width: number, height: number): { Part }
        return {
                part("Body", "Ball", { width, height, width }, { 0, height / 2, 0 }, "body"),
                part("EyeL", "Ball", { 0.55, 0.55, 0.55 }, { -width * 0.2, height * 0.78, -width * 0.38 }, "eye"),
                part("EyeR", "Ball", { 0.55, 0.55, 0.55 }, { width * 0.2, height * 0.78, -width * 0.38 }, "eye"),
        }
end

-- Small body, two thin wings, a stinger. Hornets and bats.
local function flyer(bodySize: number, wingSpan: number, withStinger: boolean): { Part }
        local parts = {
                part("Body", "Ball", { bodySize, bodySize * 1.1, bodySize }, { 0, 3.2, 0 }, "body"),
                part("WingL", "Block", { wingSpan, 0.16, 1.5 }, { -wingSpan * 0.6, 3.6, 0.2 }, "light", { 0, 0, 18 }),
                part("WingR", "Block", { wingSpan, 0.16, 1.5 }, { wingSpan * 0.6, 3.6, 0.2 }, "light", { 0, 0, -18 }),
                part("EyeL", "Ball", { 0.36, 0.36, 0.36 }, { -0.42, 3.4, -bodySize * 0.5 }, "eye"),
                part("EyeR", "Ball", { 0.36, 0.36, 0.36 }, { 0.42, 3.4, -bodySize * 0.5 }, "eye"),
        }
        if withStinger then
                table.insert(parts, part("Stinger", "Wedge", { 0.4, 0.9, 0.4 }, { 0, 2.7, 0.7 }, "accent", { 180, 0, 0 }))
        end
        return parts
end

-- Four legs, a head and a tail. Boars, hounds, stalkers.
local function quadruped(length: number, legHeight: number, tail: boolean): { Part }
        local parts = {
                part("Body", "Block", { 2.2, 1.7, length }, { 0, legHeight + 0.85, 0 }, "body"),
                part("Head", "Block", { 1.5, 1.3, 1.5 }, { 0, legHeight + 1.15, -length * 0.55 }, "dark"),
                part("Snout", "Block", { 0.8, 0.6, 0.6 }, { 0, legHeight + 0.95, -length * 0.55 - 0.9 }, "light"),
                part("EyeL", "Ball", { 0.3, 0.3, 0.3 }, { -0.5, legHeight + 1.4, -length * 0.55 - 0.7 }, "eye"),
                part("EyeR", "Ball", { 0.3, 0.3, 0.3 }, { 0.5, legHeight + 1.4, -length * 0.55 - 0.7 }, "eye"),
                part("LegFL", "Block", { 0.55, legHeight, 0.55 }, { -0.75, legHeight / 2, -length * 0.32 }, "dark"),
                part("LegFR", "Block", { 0.55, legHeight, 0.55 }, { 0.75, legHeight / 2, -length * 0.32 }, "dark"),
                part("LegBL", "Block", { 0.55, legHeight, 0.55 }, { -0.75, legHeight / 2, length * 0.32 }, "dark"),
                part("LegBR", "Block", { 0.55, legHeight, 0.55 }, { 0.75, legHeight / 2, length * 0.32 }, "dark"),
        }
        if tail then
                table.insert(parts, part("Tail", "Block", { 0.35, 0.35, 1.6 }, { 0, legHeight + 1.3, length * 0.7 }, "body", { -25, 0, 0 }))
        end
        return parts
end

-- Two arms, two legs, a head. Skeletons, mummies, knights.
local function humanoid(shoulders: number, armLength: number, headSize: number): { Part }
        return {
                part("Body", "Block", { shoulders, 2.0, 1.1 }, { 0, 3.5, 0 }, "body"),
                part("Head", "Ball", { headSize, headSize, headSize }, { 0, 5.0, 0 }, "light"),
                part("EyeL", "Ball", { 0.24, 0.24, 0.24 }, { -0.35, 5.05, -headSize * 0.45 }, "eye"),
                part("EyeR", "Ball", { 0.24, 0.24, 0.24 }, { 0.35, 5.05, -headSize * 0.45 }, "eye"),
                part("ArmL", "Block", { 0.6, armLength, 0.6 }, { -shoulders / 2 - 0.35, 3.5 - armLength / 2 + 0.6, 0 }, "dark"),
                part("ArmR", "Block", { 0.6, armLength, 0.6 }, { shoulders / 2 + 0.35, 3.5 - armLength / 2 + 0.6, 0 }, "dark"),
                part("LegL", "Block", { 0.7, 2.5, 0.7 }, { -0.55, 1.25, 0 }, "dark"),
                part("LegR", "Block", { 0.7, 2.5, 0.7 }, { 0.55, 1.25, 0 }, "dark"),
        }
end

-- A wall of stone: heavy torso, huge arms, tiny head.
local function golem(): { Part }
        return {
                part("Body", "Block", { 3.2, 3.0, 2.2 }, { 0, 3.6, 0 }, "body"),
                part("Head", "Block", { 1.4, 1.2, 1.4 }, { 0, 5.7, 0 }, "dark"),
                part("EyeL", "Ball", { 0.34, 0.34, 0.34 }, { -0.34, 5.75, -0.75 }, "eye"),
                part("EyeR", "Ball", { 0.34, 0.34, 0.34 }, { 0.34, 5.75, -0.75 }, "eye"),
                part("ArmL", "Block", { 1.3, 3.2, 1.3 }, { -2.35, 3.3, 0 }, "dark"),
                part("ArmR", "Block", { 1.3, 3.2, 1.3 }, { 2.35, 3.3, 0 }, "dark"),
                part("LegL", "Block", { 1.2, 2.1, 1.2 }, { -0.85, 1.05, 0 }, "dark"),
                part("LegR", "Block", { 1.2, 2.1, 1.2 }, { 0.85, 1.05, 0 }, "dark"),
                part("ShardL", "Wedge", { 0.9, 1.6, 0.9 }, { -1.0, 5.9, 0.4 }, "light", { -20, 0, 0 }),
                part("ShardR", "Wedge", { 0.9, 1.6, 0.9 }, { 1.0, 5.9, 0.4 }, "light", { -20, 0, 0 }),
        }
end

-- A robe with a hood and no legs. Wraiths and priests.
local function robed(height: number, hoodSize: number, floating: boolean): { Part }
        local base = floating and 1.6 or 0
        return {
                part("Body", "Cylinder", { height, height, height }, { 0, base + height / 2, 0 }, "body", { 0, 0, 90 }),
                part("Hood", "Ball", { hoodSize, hoodSize, hoodSize }, { 0, base + height + hoodSize * 0.35, 0 }, "dark"),
                part("EyeL", "Ball", { 0.26, 0.26, 0.26 }, { -0.32, base + height + hoodSize * 0.3, -hoodSize * 0.42 }, "eye"),
                part("EyeR", "Ball", { 0.26, 0.26, 0.26 }, { 0.32, base + height + hoodSize * 0.3, -hoodSize * 0.42 }, "eye"),
                part("ArmL", "Block", { 0.7, 2.0, 0.7 }, { -1.1, base + height * 0.62, 0 }, "dark", { 0, 0, 12 }),
                part("ArmR", "Block", { 0.7, 2.0, 0.7 }, { 1.1, base + height * 0.62, 0 }, "dark", { 0, 0, -12 }),
        }
end

-- A neck, a head, wings, a tail and legs. The field bosses.
local function dragon(): { Part }
        return {
                part("Body", "Block", { 2.6, 2.2, 4.0 }, { 0, 2.6, 0.2 }, "body"),
                part("Neck", "Block", { 1.0, 2.2, 1.0 }, { 0, 4.2, -1.6 }, "dark", { 22, 0, 0 }),
                part("Head", "Block", { 1.5, 1.2, 2.1 }, { 0, 5.3, -2.6 }, "dark"),
                part("Jaw", "Block", { 1.2, 0.4, 1.7 }, { 0, 4.85, -2.9 }, "light"),
                part("EyeL", "Ball", { 0.34, 0.34, 0.34 }, { -0.5, 5.55, -3.3 }, "eye"),
                part("EyeR", "Ball", { 0.34, 0.34, 0.34 }, { 0.5, 5.55, -3.3 }, "eye"),
                part("WingL", "Block", { 3.4, 0.2, 2.6 }, { -2.6, 4.4, 0.6 }, "light", { 0, 0, 22 }),
                part("WingR", "Block", { 3.4, 0.2, 2.6 }, { 2.6, 4.4, 0.6 }, "light", { 0, 0, -22 }),
                part("Tail", "Block", { 0.6, 0.6, 3.0 }, { 0, 2.2, 2.9 }, "dark", { -18, 0, 0 }),
                part("LegL", "Block", { 0.9, 1.8, 0.9 }, { -1.0, 0.9, -0.9 }, "dark"),
                part("LegR", "Block", { 0.9, 1.8, 0.9 }, { 1.0, 0.9, -0.9 }, "dark"),
                part("LegL2", "Block", { 0.9, 1.8, 0.9 }, { -1.0, 0.9, 1.4 }, "dark"),
                part("LegR2", "Block", { 0.9, 1.8, 0.9 }, { 1.0, 0.9, 1.4 }, "dark"),
        }
end

-- A small body with two horns. Imps and familiars.
local function imp(): { Part }
        return {
                part("Body", "Ball", { 1.6, 1.8, 1.6 }, { 0, 2.2, 0 }, "body"),
                part("HornL", "Wedge", { 0.36, 1.1, 0.36 }, { -0.5, 3.4, 0 }, "dark", { -30, 0, 0 }),
                part("HornR", "Wedge", { 0.36, 1.1, 0.36 }, { 0.5, 3.4, 0 }, "dark", { -30, 0, 0 }),
                part("EyeL", "Ball", { 0.3, 0.3, 0.3 }, { -0.38, 2.4, -0.72 }, "eye"),
                part("EyeR", "Ball", { 0.3, 0.3, 0.3 }, { 0.38, 2.4, -0.72 }, "eye"),
                part("WingL", "Block", { 1.4, 0.14, 1.0 }, { -1.0, 2.6, 0.3 }, "light", { 0, 0, 20 }),
                part("WingR", "Block", { 1.4, 0.14, 1.0 }, { 1.0, 2.6, 0.3 }, "light", { 0, 0, -20 }),
                part("LegL", "Block", { 0.5, 1.3, 0.5 }, { -0.4, 0.65, 0 }, "dark"),
                part("LegR", "Block", { 0.5, 1.3, 0.5 }, { 0.4, 0.65, 0 }, "dark"),
        }
end

-- A burning core with flame licks. Elementals and wisps.
local function elemental(): { Part }
        return {
                part("Body", "Ball", { 2.0, 2.0, 2.0 }, { 0, 3.0, 0 }, "body"),
                part("FlameL", "Wedge", { 0.8, 1.8, 0.8 }, { -0.7, 4.4, 0 }, "light", { -18, 0, -12 }),
                part("FlameR", "Wedge", { 0.8, 1.8, 0.8 }, { 0.7, 4.4, 0 }, "light", { -18, 0, 12 }),
                part("FlameTop", "Wedge", { 0.9, 2.0, 0.9 }, { 0, 4.7, 0 }, "accent", { -12, 0, 0 }),
                part("EyeL", "Ball", { 0.34, 0.34, 0.34 }, { -0.42, 3.2, -0.86 }, "eye"),
                part("EyeR", "Ball", { 0.34, 0.34, 0.34 }, { 0.42, 3.2, -0.86 }, "eye"),
        }
end

-- Tail, claws, legs. Scorpions.
local function scorpion(): { Part }
        return {
                part("Body", "Block", { 1.6, 1.0, 2.4 }, { 0, 1.4, 0 }, "body"),
                part("Head", "Block", { 1.2, 0.9, 1.0 }, { 0, 1.5, -1.5 }, "dark"),
                part("EyeL", "Ball", { 0.24, 0.24, 0.24 }, { -0.3, 1.75, -1.9 }, "eye"),
                part("EyeR", "Ball", { 0.24, 0.24, 0.24 }, { 0.3, 1.75, -1.9 }, "eye"),
                part("Tail1", "Block", { 0.6, 0.6, 1.0 }, { 0, 2.0, 1.5 }, "dark", { -40, 0, 0 }),
                part("Tail2", "Block", { 0.55, 0.55, 1.0 }, { 0, 2.8, 1.9 }, "dark", { -70, 0, 0 }),
                part("Sting", "Wedge", { 0.4, 1.0, 0.4 }, { 0, 3.5, 1.5 }, "accent", { -140, 0, 0 }),
                part("ClawL", "Block", { 1.2, 0.6, 0.7 }, { -1.2, 1.3, -1.6 }, "dark", { 0, 0, 14 }),
                part("ClawR", "Block", { 1.2, 0.6, 0.7 }, { 1.2, 1.3, -1.6 }, "dark", { 0, 0, -14 }),
                part("LegL", "Block", { 0.4, 1.0, 0.4 }, { -1.0, 0.5, 0.4 }, "dark"),
                part("LegR", "Block", { 0.4, 1.0, 0.4 }, { 1.0, 0.5, 0.4 }, "dark"),
        }
end

-- A round body with two long ears. Lunatics.
local function rabbit(): { Part }
        return {
                part("Body", "Ball", { 1.7, 1.8, 1.7 }, { 0, 2.4, 0 }, "body"),
                part("Head", "Ball", { 1.1, 1.1, 1.1 }, { 0, 4.0, 0 }, "light"),
                part("EarL", "Block", { 0.34, 1.7, 0.22 }, { -0.3, 5.2, 0 }, "light", { -8, 0, -6 }),
                part("EarR", "Block", { 0.34, 1.7, 0.22 }, { 0.3, 5.2, 0 }, "light", { -8, 0, 6 }),
                part("EyeL", "Ball", { 0.26, 0.26, 0.26 }, { -0.34, 4.05, -0.5 }, "eye"),
                part("EyeR", "Ball", { 0.26, 0.26, 0.26 }, { 0.34, 4.05, -0.5 }, "eye"),
                part("FootL", "Block", { 0.6, 0.9, 1.1 }, { -0.5, 0.45, -0.2 }, "dark"),
                part("FootR", "Block", { 0.6, 0.9, 1.1 }, { 0.5, 0.45, -0.2 }, "dark"),
        }
end

-- A wide body with two big eyes and short legs. Toads.
local function toad(): { Part }
        return {
                part("Body", "Ball", { 3.0, 2.0, 3.0 }, { 0, 1.8, 0 }, "body"),
                part("EyeL", "Ball", { 0.8, 0.8, 0.8 }, { -0.9, 3.1, -0.8 }, "light"),
                part("EyeR", "Ball", { 0.8, 0.8, 0.8 }, { 0.9, 3.1, -0.8 }, "light"),
                part("PupilL", "Ball", { 0.34, 0.34, 0.34 }, { -0.9, 3.15, -1.5 }, "eye"),
                part("PupilR", "Ball", { 0.34, 0.34, 0.34 }, { 0.9, 3.15, -1.5 }, "eye"),
                part("Mouth", "Block", { 1.8, 0.22, 0.3 }, { 0, 1.4, -1.5 }, "dark"),
                part("LegL", "Block", { 0.7, 1.0, 0.7 }, { -1.4, 0.5, -0.6 }, "dark"),
                part("LegR", "Block", { 0.7, 1.0, 0.7 }, { 1.4, 0.5, -0.6 }, "dark"),
                part("LegL2", "Block", { 0.7, 1.0, 0.7 }, { -1.3, 0.5, 1.0 }, "dark"),
                part("LegR2", "Block", { 0.7, 1.0, 0.7 }, { 1.3, 0.5, 1.0 }, "dark"),
        }
end

-- A core with tendrils hanging below. Void wisps.
local function wisp(): { Part }
        return {
                part("Body", "Ball", { 1.9, 1.9, 1.9 }, { 0, 3.2, 0 }, "body"),
                part("EyeL", "Ball", { 0.3, 0.3, 0.3 }, { -0.4, 3.3, -0.8 }, "eye"),
                part("EyeR", "Ball", { 0.3, 0.3, 0.3 }, { 0.4, 3.3, -0.8 }, "eye"),
                part("TendrilL", "Cylinder", { 1.8, 0.3, 0.3 }, { -0.6, 2.0, 0 }, "light", { 0, 0, 8 }),
                part("TendrilC", "Cylinder", { 2.2, 0.3, 0.3 }, { 0, 1.8, 0 }, "light"),
                part("TendrilR", "Cylinder", { 1.8, 0.3, 0.3 }, { 0.6, 2.0, 0 }, "light", { 0, 0, -8 }),
        }
end

-- Two pillars and an arch with a light in it. Heaven's Gate.
local function gate(): { Part }
        return {
                part("Body", "Block", { 1.0, 6.0, 1.0 }, { -2.2, 3.0, 0 }, "body"),
                part("PillarR", "Block", { 1.0, 6.0, 1.0 }, { 2.2, 3.0, 0 }, "body"),
                part("Arch", "Block", { 5.4, 0.9, 1.0 }, { 0, 6.2, 0 }, "dark"),
                part("Core", "Ball", { 2.0, 2.0, 2.0 }, { 0, 3.4, 0 }, "accent"),
                part("EyeL", "Ball", { 0.34, 0.34, 0.34 }, { -0.5, 3.6, -1.0 }, "eye"),
                part("EyeR", "Ball", { 0.34, 0.34, 0.34 }, { 0.5, 3.6, -1.0 }, "eye"),
                part("Step", "Block", { 4.6, 0.5, 2.0 }, { 0, 0.25, 0 }, "light"),
        }
end

-- A humanoid with wings and a helm. Guards, knights, seraphs.
local function wingedGuard(withHalo: boolean): { Part }
        local parts = humanoid(2.6, 2.4, 1.3)
        table.insert(parts, part("WingL", "Block", { 2.6, 0.2, 2.0 }, { -1.8, 4.0, 0.5 }, "light", { 0, 0, 24 }))
        table.insert(parts, part("WingR", "Block", { 2.6, 0.2, 2.0 }, { 1.8, 4.0, 0.5 }, "light", { 0, 0, -24 }))
        table.insert(parts, part("Helm", "Block", { 1.4, 0.7, 1.4 }, { 0, 5.6, 0 }, "metal"))
        table.insert(parts, part("Crest", "Wedge", { 0.3, 0.9, 1.2 }, { 0, 6.1, 0 }, "accent", { -20, 0, 0 }))
        if withHalo then
                table.insert(parts, part("Halo", "Cylinder", { 0.25, 1.8, 1.8 }, { 0, 6.4, 0 }, "accent", { 0, 0, 90 }))
        end
        return parts
end

-- A big crowned orb. Slime King.
local function crownedOrb(): { Part }
        local parts = orb(4.4)
        table.insert(parts, part("Crown", "Cylinder", { 0.7, 2.2, 2.2 }, { 0, 4.5, 0 }, "accent"))
        table.insert(parts, part("SpikeL", "Wedge", { 0.4, 1.0, 0.4 }, { -1.0, 5.3, 0 }, "accent"))
        table.insert(parts, part("SpikeC", "Wedge", { 0.4, 1.3, 0.4 }, { 0, 5.5, 0 }, "accent"))
        table.insert(parts, part("SpikeR", "Wedge", { 0.4, 1.0, 0.4 }, { 1.0, 5.3, 0 }, "accent"))
        return parts
end

--------------------------------------------------------------------------
-- Which body plan each archetype uses. A monster that is not listed falls back
-- to a plain orb, so a new archetype is never invisible.
--------------------------------------------------------------------------

local PLANS: { [string]: () -> { Part } } = {
        -- Meadow.
        Poring = function()
                return orb(2.2)
        end,
        Slime = function()
                return blob(2.6, 2.0)
        end,
        Hornet = function()
                return flyer(1.1, 1.6, true)
        end,
        BabyBoar = function()
                return quadruped(3.0, 1.0, true)
        end,
        Lunatic = function()
                return rabbit()
        end,
        SlimeKing = function()
                return crownedOrb()
        end,

        -- Cavern.
        CaveBat = function()
                return flyer(1.0, 2.0, false)
        end,
        Skeleton = function()
                return humanoid(2.2, 2.6, 1.2)
        end,
        RockGolem = function()
                return golem()
        end,
        Familiar = function()
                return imp()
        end,
        CrystalGolem = function()
                return golem()
        end,

        -- Desert.
        Scorpion = function()
                return scorpion()
        end,
        Mummy = function()
                return humanoid(2.3, 2.4, 1.25)
        end,
        Anubis = function()
                return humanoid(2.5, 2.5, 1.3)
        end,
        SandWraith = function()
                return robed(3.6, 1.3, true)
        end,

        -- Volcano.
        EmberImp = function()
                return imp()
        end,
        MagmaHound = function()
                return quadruped(3.4, 1.1, true)
        end,
        FireElemental = function()
                return elemental()
        end,
        LavaToad = function()
                return toad()
        end,
        VolcanoDragon = function()
                return dragon()
        end,

        -- Void.
        VoidWisp = function()
                return wisp()
        end,
        RiftStalker = function()
                return quadruped(3.2, 1.3, true)
        end,
        AbyssHound = function()
                return quadruped(3.6, 1.2, true)
        end,
        VoidPriest = function()
                return robed(3.8, 1.4, false)
        end,
        VoidSovereign = function()
                local parts = robed(4.2, 1.6, true)
                table.insert(parts, part("Crown", "Cylinder", { 0.6, 2.0, 2.0 }, { 0, 6.6, 0 }, "accent"))
                table.insert(parts, part("SpikeC", "Wedge", { 0.4, 1.4, 0.4 }, { 0, 7.4, 0 }, "accent"))
                return parts
        end,

        -- Heaven.
        CelestialGuard = function()
                return wingedGuard(false)
        end,
        Seraph = function()
                return wingedGuard(true)
        end,
        DivineKnight = function()
                return wingedGuard(false)
        end,
        HeavenGate = function()
                return gate()
        end,
}

MonsterShapes.PLANS = PLANS

-- The plan for an archetype id, or a plain orb for an unknown one.
function MonsterShapes.get(archetypeId: string): Recipe
        local plan = PLANS[archetypeId]
        local parts = plan and plan() or orb(2.4)
        return { primary = "Body", parts = parts }
end

-- Every archetype id that has its own silhouette. Used by the tests to prove
-- no monster in the game falls back to the generic orb.
function MonsterShapes.knownIds(): { string }
        local out: { string } = {}
        for id in pairs(PLANS) do
                table.insert(out, id)
        end
        table.sort(out)
        return out
end

return MonsterShapes

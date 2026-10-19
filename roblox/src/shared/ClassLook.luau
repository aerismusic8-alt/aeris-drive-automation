--!strict
-- How each class looks. Pure Luau.
--
-- The class already changed the stat sheet, but not the character, so every job
-- was the same avatar with a different number. A look is two things:
--
--   * colours, which apply to the avatar's own body parts and work on both the
--     R6 and R15 rigs without touching either one;
--   * accents, which are extra parts welded to the character. They use the same
--     recipe shape as MonsterShapes, so one builder in the server handles both.
--
-- Accessory parts are positioned in "character space": the origin is the
-- HumanoidRootPart, +Y is up, -Z is the direction the character faces. Sizes
-- are in studs and are chosen to sit on a standard R15 avatar.

local ClassLook = {}

export type Color = { number }

export type Accent = {
        name: string,
        shape: "Block" | "Ball" | "Cylinder" | "Wedge",
        size: { number },
        at: { number },
        color: Color,
        rot: { number }?,
}

export type Look = {
        -- Applied to the avatar's body parts. `skin` also tints the head.
        shirt: Color,
        pants: Color,
        skin: Color,
        -- Slight build differences so a Knight reads as heavier than a Thief.
        bodyScale: { number },
        accents: { Accent },
        -- The swing style the client uses for the attack animation.
        swing: "slash" | "thrust" | "cast" | "stab" | "smite",
}

local function accent(
        name: string,
        shape: "Block" | "Ball" | "Cylinder" | "Wedge",
        size: { number },
        at: { number },
        color: Color,
        rot: { number }?
): Accent
        return { name = name, shape = shape, size = size, at = at, color = color, rot = rot }
end

--------------------------------------------------------------------------
-- Palettes. One per class, kept in the same muted range as the HUD so a player
-- on a phone can tell two characters apart at a glance.
--------------------------------------------------------------------------

local LOOKS: { [string]: Look } = {}

local function look(id: string, l: Look)
        LOOKS[id] = l
end

look("Novice", {
        shirt = { 210, 205, 190 },
        pants = { 150, 145, 135 },
        skin = { 235, 200, 170 },
        bodyScale = { 1.0, 1.0, 1.0 },
        accents = {},
        swing = "slash",
})

-- Swordsman line: plate, a shoulder pad, a sheathed blade.
look("Swordsman", {
        shirt = { 90, 130, 200 },
        pants = { 70, 90, 140 },
        skin = { 235, 200, 170 },
        bodyScale = { 1.05, 1.0, 1.05 },
        accents = {
                accent("PauldronL", "Block", { 0.9, 0.5, 0.9 }, { -1.15, 0.75, 0 }, { 180, 190, 210 }),
                accent("PauldronR", "Block", { 0.9, 0.5, 0.9 }, { 1.15, 0.75, 0 }, { 180, 190, 210 }),
                accent("Blade", "Block", { 0.18, 2.6, 0.5 }, { -0.85, -0.4, 0.5 }, { 200, 205, 215 }, { 0, 0, -12 }),
        },
        swing = "slash",
})

look("Knight", {
        shirt = { 160, 170, 190 },
        pants = { 120, 130, 150 },
        skin = { 235, 200, 170 },
        bodyScale = { 1.12, 1.05, 1.12 },
        accents = {
                accent("PauldronL", "Block", { 1.1, 0.6, 1.1 }, { -1.2, 0.8, 0 }, { 205, 215, 230 }),
                accent("PauldronR", "Block", { 1.1, 0.6, 1.1 }, { 1.2, 0.8, 0 }, { 205, 215, 230 }),
                accent("Helm", "Block", { 1.1, 0.7, 1.1 }, { 0, 1.55, 0 }, { 190, 200, 220 }),
                accent("Plume", "Wedge", { 0.2, 0.9, 0.7 }, { 0, 2.05, 0.1 }, { 220, 80, 80 }, { -20, 0, 0 }),
                accent("Shield", "Block", { 1.2, 1.4, 0.24 }, { -1.0, 0.1, -0.45 }, { 150, 160, 180 }),
                accent("Blade", "Block", { 0.2, 2.8, 0.55 }, { 0.9, -0.5, 0.4 }, { 210, 215, 225 }, { 0, 0, 10 }),
        },
        swing = "slash",
})

-- Archer line: leather, a quiver, a bow.
look("Archer", {
        shirt = { 90, 170, 110 },
        pants = { 80, 120, 85 },
        skin = { 235, 200, 170 },
        bodyScale = { 0.98, 1.0, 0.98 },
        accents = {
                accent("Quiver", "Block", { 0.5, 1.3, 0.5 }, { 0.7, 0.35, 0.6 }, { 120, 85, 55 }),
                accent("Fletch", "Block", { 0.4, 0.4, 0.4 }, { 0.7, 1.1, 0.6 }, { 220, 90, 90 }),
                accent("Bow", "Block", { 0.14, 2.4, 0.3 }, { -0.95, 0, 0.2 }, { 150, 110, 70 }, { 0, 0, -14 }),
                accent("Hood", "Block", { 1.0, 0.45, 1.0 }, { 0, 1.45, 0 }, { 70, 130, 90 }),
        },
        swing = "thrust",
})

look("Hunter", {
        shirt = { 70, 140, 95 },
        pants = { 60, 100, 70 },
        skin = { 235, 200, 170 },
        bodyScale = { 1.0, 1.02, 1.0 },
        accents = {
                accent("Quiver", "Block", { 0.55, 1.5, 0.55 }, { 0.75, 0.4, 0.6 }, { 110, 75, 50 }),
                accent("Fletch", "Block", { 0.45, 0.45, 0.45 }, { 0.75, 1.25, 0.6 }, { 230, 200, 90 }),
                accent("Bow", "Block", { 0.15, 2.7, 0.32 }, { -1.0, 0, 0.2 }, { 160, 120, 75 }, { 0, 0, -14 }),
                accent("Cloak", "Block", { 1.5, 1.7, 0.18 }, { 0, 0.1, 0.62 }, { 50, 105, 75 }),
                accent("Cap", "Block", { 1.0, 0.4, 1.0 }, { 0, 1.5, 0 }, { 60, 120, 80 }),
        },
        swing = "thrust",
})

-- Mage line: robes, a staff, a wide-brim hat.
look("Mage", {
        shirt = { 120, 100, 200 },
        pants = { 90, 75, 160 },
        skin = { 235, 200, 170 },
        bodyScale = { 0.98, 1.0, 0.98 },
        accents = {
                accent("Robe", "Cylinder", { 1.6, 1.3, 1.3 }, { 0, -0.55, 0 }, { 110, 90, 190 }, { 0, 0, 90 }),
                accent("Staff", "Cylinder", { 3.0, 0.16, 0.16 }, { -0.95, 0, 0.15 }, { 130, 100, 70 }),
                accent("Orb", "Ball", { 0.42, 0.42, 0.42 }, { -0.95, 1.55, 0.15 }, { 170, 140, 255 }),
                accent("HatBrim", "Cylinder", { 0.14, 1.9, 1.9 }, { 0, 1.6, 0 }, { 100, 80, 180 }),
                accent("HatCone", "Wedge", { 1.0, 1.0, 1.0 }, { 0, 2.05, 0 }, { 100, 80, 180 }, { 180, 0, 0 }),
        },
        swing = "cast",
})

look("Wizard", {
        shirt = { 80, 70, 170 },
        pants = { 60, 55, 130 },
        skin = { 235, 200, 170 },
        bodyScale = { 1.0, 1.02, 1.0 },
        accents = {
                accent("Robe", "Cylinder", { 2.1, 1.5, 1.5 }, { 0, -0.7, 0 }, { 70, 60, 160 }, { 0, 0, 90 }),
                accent("Staff", "Cylinder", { 3.4, 0.18, 0.18 }, { -1.0, 0.05, 0.15 }, { 120, 95, 65 }),
                accent("Orb", "Ball", { 0.5, 0.5, 0.5 }, { -1.0, 1.8, 0.15 }, { 120, 200, 255 }),
                accent("HatBrim", "Cylinder", { 0.16, 2.2, 2.2 }, { 0, 1.65, 0 }, { 65, 55, 155 }),
                accent("HatCone", "Wedge", { 1.15, 1.3, 1.15 }, { 0, 2.25, 0 }, { 65, 55, 155 }, { 180, 0, 0 }),
                accent("Mantle", "Block", { 1.6, 0.3, 1.0 }, { 0, 1.15, 0 }, { 120, 110, 220 }),
        },
        swing = "cast",
})

-- Thief line: dark cloth, twin daggers, a scarf.
look("Thief", {
        shirt = { 80, 80, 95 },
        pants = { 60, 60, 75 },
        skin = { 235, 200, 170 },
        bodyScale = { 0.95, 0.98, 0.95 },
        accents = {
                accent("Scarf", "Block", { 0.95, 0.28, 0.95 }, { 0, 1.25, 0 }, { 170, 60, 70 }),
                accent("DaggerL", "Block", { 0.14, 1.1, 0.4 }, { -0.85, -0.15, 0.3 }, { 190, 195, 205 }, { 0, 0, -14 }),
                accent("DaggerR", "Block", { 0.14, 1.1, 0.4 }, { 0.85, -0.15, 0.3 }, { 190, 195, 205 }, { 0, 0, 14 }),
        },
        swing = "stab",
})

look("Assassin", {
        shirt = { 45, 45, 60 },
        pants = { 35, 35, 48 },
        skin = { 235, 200, 170 },
        bodyScale = { 0.97, 1.0, 0.97 },
        accents = {
                accent("Mask", "Block", { 0.9, 0.4, 0.9 }, { 0, 1.4, -0.1 }, { 30, 30, 42 }),
                accent("Scarf", "Block", { 1.0, 0.3, 1.0 }, { 0, 1.2, 0 }, { 120, 40, 60 }),
                accent("DaggerL", "Block", { 0.15, 1.3, 0.42 }, { -0.9, -0.2, 0.3 }, { 200, 205, 215 }, { 0, 0, -14 }),
                accent("DaggerR", "Block", { 0.15, 1.3, 0.42 }, { 0.9, -0.2, 0.3 }, { 200, 205, 215 }, { 0, 0, 14 }),
                accent("Cape", "Block", { 1.4, 1.6, 0.16 }, { 0, 0.0, 0.6 }, { 40, 40, 55 }),
        },
        swing = "stab",
})

-- Acolyte line: white robes, a cross, a halo.
look("Acolyte", {
        shirt = { 235, 235, 240 },
        pants = { 190, 190, 200 },
        skin = { 235, 200, 170 },
        bodyScale = { 1.0, 1.0, 1.0 },
        accents = {
                accent("Robe", "Cylinder", { 1.7, 1.3, 1.3 }, { 0, -0.55, 0 }, { 230, 230, 238 }, { 0, 0, 90 }),
                accent("Cross", "Block", { 0.22, 1.0, 0.22 }, { -0.9, 0.3, 0.15 }, { 240, 205, 110 }),
                accent("CrossArm", "Block", { 0.7, 0.22, 0.22 }, { -0.9, 0.55, 0.15 }, { 240, 205, 110 }),
                accent("Hood", "Block", { 1.0, 0.42, 1.0 }, { 0, 1.45, 0 }, { 245, 245, 250 }),
        },
        swing = "smite",
})

look("Priest", {
        shirt = { 250, 248, 235 },
        pants = { 210, 205, 190 },
        skin = { 235, 200, 170 },
        bodyScale = { 1.02, 1.02, 1.02 },
        accents = {
                accent("Robe", "Cylinder", { 2.2, 1.5, 1.5 }, { 0, -0.7, 0 }, { 250, 248, 238 }, { 0, 0, 90 }),
                accent("Stole", "Block", { 0.35, 1.7, 0.2 }, { 0, 0.25, -0.55 }, { 240, 205, 110 }),
                accent("Cross", "Block", { 0.22, 1.1, 0.22 }, { -0.95, 0.35, 0.15 }, { 245, 215, 120 }),
                accent("CrossArm", "Block", { 0.75, 0.22, 0.22 }, { -0.95, 0.6, 0.15 }, { 245, 215, 120 }),
                accent("Halo", "Cylinder", { 0.14, 1.5, 1.5 }, { 0, 1.85, 0 }, { 255, 235, 150 }, { 0, 0, 90 }),
                accent("Hood", "Block", { 1.05, 0.45, 1.05 }, { 0, 1.45, 0 }, { 252, 250, 240 }),
        },
        swing = "smite",
})

-- Every class id that has a look. The tests use this to prove no class falls
-- back to the default, which would silently make a new job look like a Novice.
function ClassLook.knownIds(): { string }
        local out: { string } = {}
        for id in pairs(LOOKS) do
                table.insert(out, id)
        end
        table.sort(out)
        return out
end

local DEFAULT: Look = LOOKS.Novice

function ClassLook.get(classId: string?): Look
        if classId and LOOKS[classId] then
                return LOOKS[classId]
        end
        return DEFAULT
end

return ClassLook

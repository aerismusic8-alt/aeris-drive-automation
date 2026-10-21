--!strict
-- Scenery. Pure Luau: no Roblox globals, so every prop recipe and every
-- placement can be unit tested and the server is the only place that turns
-- them into parts.
--
-- The maps used to be a disc with a glowing rim and nothing else, which is why
-- they read as a test arena rather than a place. This module is the missing
-- layer: a recipe per prop (tree, rock, crystal, ruin, house) and a
-- deterministic scatter that decides where each one stands.
--
-- Two rules keep it honest:
--
--   * Colours and materials are roles, not literal values. The same conifer
--     recipe is used in the Meadow, the Volcano and Heaven; the palette per
--     place is what makes the leaves green in one and ash-grey in another.
--   * Placement is seeded per place, so a map looks the same on every server
--     and a test can assert exactly where things land.
--
-- Shape note: Roblox has no cone or pyramid primitive that renders reliably.
-- SpecialMesh's Pyramid and Prism types are deprecated and have long-standing
-- reports of rendering nothing at all, so a cone here is built the way the
-- engine's own trees are: a short stack of shrinking cylinders. That keeps
-- every prop to primitives a Rojo build can ship with no uploaded asset.

local Random = require("./Random")

local Scenery = {}

export type Shape = "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"

-- Where a part takes its colour from. Resolved by Scenery.palette.
export type ColorRole =
    "wood"
    | "bark"
    | "leaf"
    | "leafDark"
    | "stone"
    | "stoneDark"
    | "metal"
    | "cloth"
    | "roof"
    | "glow"
    | "pale"
    | "soil"
    | "water"

export type Part = {
    name: string,
    shape: Shape,
    size: { number },
    at: { number },
    color: ColorRole,
    rot: { number }?,
    -- How see-through the part is, 0..1. Only water and glass use it; the
    -- default 0 keeps every other prop opaque.
    alpha: number?,
}

export type Prop = {
    -- How wide the prop stands, in studs. The scatter uses it to keep props
    -- from growing through each other.
    footprint: number,
    -- How tall it stands. Used to reject props that would poke out of a field.
    height: number,
    parts: { Part },
}

local function part(
    name: string,
    shape: Shape,
    size: { number },
    at: { number },
    color: ColorRole,
    rot: { number }?,
    alpha: number?
): Part
    return { name = name, shape = shape, size = size, at = at, color = color, rot = rot, alpha = alpha }
end

-- A tapered column: stacked discs of decreasing width, standing on the ground.
-- Four steps reads as a spike, six as a smooth cone.
local function taper(base: number, height: number, steps: number, role: ColorRole): { Part }
    local parts = {}
    local slice = height / steps
    for i = 1, steps do
        local t = (i - 1) / math.max(1, steps - 1)
        local width = base * (1 - t * 0.82)
        table.insert(
            parts,
            part(
                "Slice" .. i,
                "Cylinder",
                { slice * 1.12, width, width },
                { 0, slice * (i - 0.5), 0 },
                role,
                { 0, 0, 90 }
            )
        )
    end
    return parts
end

-- A leaning shard: stacked discs whose centre drifts as they rise, so a
-- stalagmite or a crystal leans instead of standing perfectly straight.
local function lean(base: number, height: number, steps: number, drift: number, role: ColorRole): { Part }
    local parts = {}
    local slice = height / steps
    for i = 1, steps do
        local t = (i - 1) / math.max(1, steps - 1)
        local width = base * (1 - t * 0.7)
        table.insert(
            parts,
            part(
                "Slice" .. i,
                "Cylinder",
                { slice * 1.12, width, width },
                { drift * t, slice * (i - 0.5), 0 },
                role,
                { 0, 0, 90 }
            )
        )
    end
    return parts
end

--------------------------------------------------------------------------
-- Palettes. One per place, so a recipe is drawn in that place's materials.
--------------------------------------------------------------------------

local PALETTES: { [string]: { [string]: { number } } } = {
    Town = {
        wood = { 138, 102, 66 },
        bark = { 104, 76, 50 },
        leaf = { 96, 168, 92 },
        leafDark = { 68, 128, 74 },
        stone = { 176, 170, 158 },
        stoneDark = { 132, 126, 116 },
        metal = { 198, 205, 218 },
        cloth = { 216, 96, 88 },
        roof = { 176, 72, 62 },
        glow = { 255, 214, 92 },
        pale = { 232, 226, 210 },
        soil = { 104, 76, 54 },
        water = { 96, 150, 190 },
    },
    Meadow = {
        wood = { 140, 108, 70 },
        bark = { 106, 78, 52 },
        leaf = { 104, 178, 96 },
        leafDark = { 70, 132, 76 },
        stone = { 168, 166, 158 },
        stoneDark = { 126, 124, 118 },
        metal = { 190, 198, 210 },
        cloth = { 226, 206, 128 },
        roof = { 150, 92, 70 },
        glow = { 140, 255, 170 },
        pale = { 226, 232, 216 },
        soil = { 110, 82, 58 },
        water = { 96, 158, 198 },
    },
    Cavern = {
        wood = { 92, 84, 84 },
        bark = { 68, 62, 66 },
        leaf = { 110, 132, 150 },
        leafDark = { 74, 92, 112 },
        stone = { 118, 124, 148 },
        stoneDark = { 84, 90, 112 },
        metal = { 176, 186, 206 },
        cloth = { 110, 126, 176 },
        roof = { 92, 100, 134 },
        glow = { 150, 200, 255 },
        pale = { 196, 206, 224 },
        soil = { 74, 78, 96 },
        water = { 92, 132, 178 },
    },
    Volcano = {
        wood = { 96, 66, 54 },
        bark = { 64, 44, 38 },
        leaf = { 128, 74, 58 },
        leafDark = { 92, 52, 42 },
        stone = { 116, 92, 86 },
        stoneDark = { 76, 60, 58 },
        metal = { 158, 140, 132 },
        cloth = { 196, 84, 58 },
        roof = { 150, 62, 44 },
        glow = { 255, 138, 62 },
        pale = { 208, 180, 160 },
        soil = { 88, 58, 48 },
        water = { 220, 110, 62 },
    },
    Void = {
        wood = { 78, 70, 104 },
        bark = { 56, 50, 78 },
        leaf = { 122, 96, 176 },
        leafDark = { 88, 66, 132 },
        stone = { 112, 104, 148 },
        stoneDark = { 76, 70, 106 },
        metal = { 168, 158, 208 },
        cloth = { 138, 92, 196 },
        roof = { 106, 74, 154 },
        glow = { 180, 130, 255 },
        pale = { 198, 186, 232 },
        soil = { 70, 62, 96 },
        water = { 132, 96, 196 },
    },
    Heaven = {
        wood = { 210, 198, 168 },
        bark = { 186, 172, 140 },
        leaf = { 200, 226, 196 },
        leafDark = { 168, 200, 172 },
        stone = { 226, 228, 238 },
        stoneDark = { 192, 194, 208 },
        metal = { 255, 246, 200 },
        cloth = { 240, 240, 255 },
        roof = { 214, 210, 226 },
        glow = { 255, 246, 200 },
        pale = { 244, 246, 255 },
        soil = { 206, 202, 196 },
        water = { 190, 222, 240 },
    },
}

-- The palette for a place, falling back to the town's.
function Scenery.palette(placeId: string?): { [string]: { number } }
    return PALETTES[placeId or "Town"] or PALETTES.Town
end

-- The Roblox material a colour role is drawn in. Wooden things are Wood,
-- stone is Slate, foliage is Grass, and anything that emits light is Neon.
-- Material is what stops a grey boulder and a grey wall reading as the same
-- box: one is rough stone, the other is smooth plaster.
local MATERIALS: { [string]: string } = {
    wood = "Wood",
    bark = "Wood",
    leaf = "Grass",
    leafDark = "Grass",
    stone = "Slate",
    stoneDark = "Slate",
    metal = "Metal",
    cloth = "Fabric",
    roof = "WoodPlanks",
    glow = "Neon",
    pale = "Marble",
    soil = "Ground",
    water = "Glass",
}

function Scenery.materialFor(role: string): string
    return MATERIALS[role] or "SmoothPlastic"
end

--------------------------------------------------------------------------
-- Prop recipes. Each is described in "prop space": the origin sits on the
-- ground and +Y is up, exactly like a monster recipe, so the server places a
-- prop the same way it places a creature.
--------------------------------------------------------------------------

-- A conifer: a trunk under one long taper. Reads as a fir at a glance and is
-- only seven parts, which matters when a field holds sixty of them.
local function pine(trunk: number): Prop
    local parts = {
        part("Trunk", "Cylinder", { trunk * 0.7, trunk * 0.26, trunk * 0.26 }, { 0, trunk * 0.35, 0 }, "bark", { 0, 0, 90 }),
    }
    local crownBase = trunk * 0.4
    local crownHeight = trunk * 1.7
    for _, p in ipairs(taper(trunk * 0.95, crownHeight, 6, "leaf")) do
        table.insert(
            parts,
            part(p.name, p.shape, p.size, { p.at[1], p.at[2] + crownBase, p.at[3] }, p.color, p.rot)
        )
    end
    return { footprint = trunk * 0.95, height = crownBase + crownHeight, parts = parts }
end

-- A round tree: a trunk with a cluster of leaf balls. The offsets are fixed
-- rather than random so two trees of the same size are identical, which keeps
-- the placement test deterministic.
local function broadleaf(trunk: number, canopy: number): Prop
    return {
        footprint = canopy * 1.6,
        height = trunk + canopy * 1.6,
        parts = {
            part("Trunk", "Cylinder", { trunk, trunk * 0.26, trunk * 0.26 }, { 0, trunk * 0.5, 0 }, "bark", { 0, 0, 90 }),
            part("Canopy", "Ball", { canopy, canopy, canopy }, { 0, trunk + canopy * 0.42, 0 }, "leaf"),
            part("CanopyL", "Ball", { canopy * 0.7, canopy * 0.7, canopy * 0.7 }, { -canopy * 0.5, trunk + canopy * 0.28, 0 }, "leafDark"),
            part("CanopyR", "Ball", { canopy * 0.7, canopy * 0.7, canopy * 0.7 }, { canopy * 0.5, trunk + canopy * 0.28, 0 }, "leafDark"),
            part("CanopyTop", "Ball", { canopy * 0.62, canopy * 0.62, canopy * 0.62 }, { 0, trunk + canopy * 1.02, 0 }, "leaf"),
        },
    }
end

-- A palm: a leaning trunk and wedge fronds. The fronds sit at five angles so
-- the crown is never seen edge-on and disappear.
local function palm(trunk: number): Prop
    local parts = {
        part("Trunk", "Cylinder", { trunk * 1.25, trunk * 0.22, trunk * 0.22 }, { trunk * 0.12, trunk * 0.6, 0 }, "bark", { 0, 0, 82 }),
    }
    for i = 1, 5 do
        local angle = (i - 1) / 5 * math.pi * 2
        table.insert(
            parts,
            part(
                "Frond" .. i,
                "Wedge",
                { trunk * 0.36, trunk * 0.1, trunk * 1.1 },
                {
                    math.cos(angle) * trunk * 0.5,
                    trunk * 1.2,
                    math.sin(angle) * trunk * 0.5,
                },
                "leaf",
                { -18, math.deg(angle), 0 }
            )
        )
    end
    table.insert(parts, part("Crown", "Ball", { trunk * 0.32, trunk * 0.32, trunk * 0.32 }, { 0, trunk * 1.16, 0 }, "leafDark"))
    return { footprint = trunk * 1.5, height = trunk * 1.5, parts = parts }
end

-- A bare tree for the Cavern and the Volcano: no leaves, angled branches.
local function deadTree(trunk: number): Prop
    return {
        footprint = trunk * 1.6,
        height = trunk * 1.5,
        parts = {
            part("Trunk", "Cylinder", { trunk, trunk * 0.22, trunk * 0.22 }, { 0, trunk * 0.5, 0 }, "bark", { 0, 0, 86 }),
            part("BranchA", "Block", { trunk * 0.14, trunk * 0.7, trunk * 0.14 }, { -trunk * 0.34, trunk * 0.86, 0 }, "bark", { 0, 0, 42 }),
            part("BranchB", "Block", { trunk * 0.12, trunk * 0.6, trunk * 0.12 }, { trunk * 0.3, trunk * 0.94, 0 }, "bark", { 0, 0, -38 }),
            part("BranchC", "Block", { trunk * 0.1, trunk * 0.44, trunk * 0.1 }, { 0, trunk * 1.1, trunk * 0.2 }, "bark", { 34, 0, 0 }),
        },
    }
end

-- A boulder cluster: three rounded rocks at different heights.
local function rocks(size: number): Prop
    return {
        footprint = size * 2.2,
        height = size * 1.3,
        parts = {
            part("RockA", "Ball", { size * 1.5, size * 1.1, size * 1.5 }, { 0, size * 0.5, 0 }, "stone"),
            part("RockB", "Ball", { size * 0.95, size * 0.8, size * 0.95 }, { size * 0.85, size * 0.35, size * 0.3 }, "stoneDark"),
            part("RockC", "Block", { size * 0.8, size * 0.6, size * 0.7 }, { -size * 0.8, size * 0.28, -size * 0.2 }, "stoneDark", { 0, 24, 0 }),
        },
    }
end

-- A crystal cluster. Leaning tapers, so a cluster is never a single spike and
-- reads as a formation rather than a marker.
local function crystals(size: number): Prop
    local parts = {}
    local offsets = { { 0, 0, 1.0 }, { -0.6, 0, 0.6 }, { 0.6, 0.1, 0.55 } }
    for i, o in ipairs(offsets) do
        for _, p in ipairs(lean(size * 0.5 * o[3], size * 1.9 * o[3], 4, size * 0.22 * (i - 1), "glow")) do
            table.insert(
                parts,
                part(
                    p.name .. i,
                    p.shape,
                    p.size,
                    { p.at[1] + o[1] * size, p.at[2], p.at[3] + o[2] * size },
                    p.color,
                    p.rot
                )
            )
        end
    end
    return { footprint = size * 2, height = size * 2, parts = parts }
end

-- A stalagmite: a leaning taper with a smaller tooth beside it.
local function spike(height: number): Prop
    local parts = {}
    for _, p in ipairs(lean(height * 0.34, height, 5, height * 0.1, "stone")) do
        table.insert(parts, p)
    end
    table.insert(
        parts,
        part("SpikeSmall", "Cylinder", { height * 0.4, height * 0.16, height * 0.16 }, { height * 0.3, height * 0.2, 0 }, "stoneDark", { 0, 0, 84 })
    )
    return { footprint = height * 0.5, height = height, parts = parts }
end

-- A shallow glowing pool, for the Volcano and the Void.
local function pool(size: number): Prop
    return {
        footprint = size * 2,
        height = 1,
        parts = {
            part("Pool", "Cylinder", { 0.6, size * 2, size * 2 }, { 0, 0.3, 0 }, "glow", { 0, 0, 90 }),
            part("Lip", "Cylinder", { 0.9, size * 2.3, size * 2.3 }, { 0, 0.12, 0 }, "stoneDark", { 0, 0, 90 }),
        },
    }
end

-- A broken wall and a toppled column. The only thing on the map that says
-- somebody built here before the monsters arrived.
local function ruin(size: number): Prop
    return {
        footprint = size * 2.4,
        height = size * 1.6,
        parts = {
            part("Wall", "Block", { size * 2.2, size * 1.5, size * 0.5 }, { 0, size * 0.75, 0 }, "stone", { 0, 8, 0 }),
            part("WallGap", "Block", { size * 0.6, size * 0.7, size * 0.5 }, { -size * 0.6, size * 0.35, 0 }, "stoneDark", { 0, 8, 0 }),
            part("Column", "Cylinder", { size * 1.9, size * 0.5, size * 0.5 }, { size * 1.3, size * 0.5, size * 0.6 }, "stoneDark", { 0, 0, 78 }),
            part("Capital", "Block", { size * 0.9, size * 0.3, size * 0.9 }, { size * 1.9, size * 0.22, size * 0.6 }, "stone", { 0, 20, 0 }),
        },
    }
end

-- A standing pillar. Heaven is colonnades, so this is its basic unit.
local function pillar(height: number): Prop
    return {
        footprint = height * 0.5,
        height = height * 1.1,
        parts = {
            part("Base", "Block", { height * 0.5, height * 0.16, height * 0.5 }, { 0, height * 0.08, 0 }, "stoneDark"),
            part("Shaft", "Cylinder", { height * 0.8, height * 0.32, height * 0.32 }, { 0, height * 0.48, 0 }, "stone", { 0, 0, 90 }),
            part("Capital", "Block", { height * 0.46, height * 0.14, height * 0.46 }, { 0, height * 0.94, 0 }, "stoneDark"),
            part("Glow", "Ball", { height * 0.16, height * 0.16, height * 0.16 }, { 0, height * 1.06, 0 }, "glow"),
        },
    }
end

-- A cloud built from overlapping balls. High up, non-collidable, pale.
local function cloud(size: number): Prop
    local parts = {}
    local offsets = {
        { 0, size * 0.4, 0, 1.0 },
        { -size * 0.7, size * 0.3, 0, 0.75 },
        { size * 0.7, size * 0.32, 0, 0.8 },
        { size * 0.2, size * 0.7, size * 0.3, 0.6 },
    }
    for i, o in ipairs(offsets) do
        table.insert(
            parts,
            part("Puff" .. i, "Ball", { size * o[4], size * o[4] * 0.62, size * o[4] }, { o[1], o[2], o[3] }, "pale")
        )
    end
    return { footprint = size * 2.6, height = size * 1.4, parts = parts }
end

-- A house for the town: a body, a pitched roof, a door and a lit window.
local function house(width: number): Prop
    return {
        footprint = width * 1.3,
        height = width * 1.5,
        parts = {
            part("Body", "Block", { width, width * 0.9, width * 0.8 }, { 0, width * 0.45, 0 }, "pale"),
            part("Roof", "Wedge", { width * 1.15, width * 0.6, width * 0.95 }, { 0, width * 1.2, 0 }, "roof"),
            part("Door", "Block", { width * 0.24, width * 0.44, width * 0.06 }, { 0, width * 0.22, -width * 0.42 }, "bark"),
            part("Window", "Block", { width * 0.2, width * 0.2, width * 0.06 }, { width * 0.28, width * 0.6, -width * 0.42 }, "glow"),
            part("Beam", "Block", { width * 1.05, width * 0.08, width * 0.06 }, { 0, width * 0.9, -width * 0.42 }, "bark"),
        },
    }
end

-- A market stall: a cloth canopy on four posts. Town furniture.
local function stall(width: number): Prop
    return {
        footprint = width * 1.2,
        height = width * 1.1,
        parts = {
            part("Canopy", "Block", { width, width * 0.1, width * 0.8 }, { 0, width * 0.95, 0 }, "cloth"),
            part("Counter", "Block", { width * 0.9, width * 0.12, width * 0.5 }, { 0, width * 0.42, 0 }, "wood"),
            part("LegA", "Block", { width * 0.07, width * 0.9, width * 0.07 }, { -width * 0.42, width * 0.45, -width * 0.32 }, "bark"),
            part("LegB", "Block", { width * 0.07, width * 0.9, width * 0.07 }, { width * 0.42, width * 0.45, -width * 0.32 }, "bark"),
            part("LegC", "Block", { width * 0.07, width * 0.9, width * 0.07 }, { -width * 0.42, width * 0.45, width * 0.32 }, "bark"),
            part("LegD", "Block", { width * 0.07, width * 0.9, width * 0.07 }, { width * 0.42, width * 0.45, width * 0.32 }, "bark"),
        },
    }
end

-- A lamp post. The town's light source, and the reason a town reads as a town
-- at night.
local function lamp(height: number): Prop
    return {
        footprint = height * 0.4,
        height = height * 1.1,
        parts = {
            part("Post", "Cylinder", { height, height * 0.09, height * 0.09 }, { 0, height / 2, 0 }, "metal", { 0, 0, 90 }),
            part("Arm", "Block", { height * 0.4, height * 0.06, height * 0.06 }, { height * 0.2, height * 0.98, 0 }, "metal"),
            part("Lantern", "Ball", { height * 0.22, height * 0.26, height * 0.22 }, { height * 0.4, height * 0.88, 0 }, "glow"),
        },
    }
end

local function barrel(size: number): Prop
    return {
        footprint = size * 1.2,
        height = size * 1.2,
        parts = {
            part("Body", "Cylinder", { size, size * 0.75, size * 0.75 }, { 0, size * 0.5, 0 }, "wood", { 0, 0, 90 }),
            part("HoopA", "Cylinder", { size * 0.1, size * 0.82, size * 0.82 }, { 0, size * 0.24, 0 }, "metal", { 0, 0, 90 }),
            part("HoopB", "Cylinder", { size * 0.1, size * 0.82, size * 0.82 }, { 0, size * 0.78, 0 }, "metal", { 0, 0, 90 }),
        },
    }
end

local function crate(size: number): Prop
    return {
        footprint = size * 1.2,
        height = size,
        parts = {
            part("Box", "Block", { size, size, size }, { 0, size * 0.5, 0 }, "wood"),
            part("Band", "Block", { size * 1.02, size * 0.1, size * 1.02 }, { 0, size * 0.5, 0 }, "bark"),
        },
    }
end

-- A low bush, used to break up open ground.
local function bush(size: number): Prop
    return {
        footprint = size * 2,
        height = size * 1.2,
        parts = {
            part("BushA", "Ball", { size, size * 0.85, size }, { 0, size * 0.42, 0 }, "leafDark"),
            part("BushB", "Ball", { size * 0.7, size * 0.6, size * 0.7 }, { size * 0.5, size * 0.3, size * 0.3 }, "leaf"),
        },
    }
end

-- A giant mushroom. The Meadow's signature oddity.
local function mushroom(size: number): Prop
    return {
        footprint = size * 1.6,
        height = size * 1.5,
        parts = {
            part("Stem", "Cylinder", { size, size * 0.26, size * 0.26 }, { 0, size * 0.5, 0 }, "pale", { 0, 0, 90 }),
            part("Cap", "Ball", { size * 1.1, size * 0.6, size * 1.1 }, { 0, size * 1.02, 0 }, "cloth"),
            part("Spot", "Ball", { size * 0.22, size * 0.12, size * 0.22 }, { size * 0.3, size * 1.24, 0 }, "pale"),
        },
    }
end

-- A clump of flowers. Tiny, so it only ever appears as ground texture.
local function flowers(size: number): Prop
    local parts = {}
    for i = 1, 4 do
        local angle = (i - 1) / 4 * math.pi * 2
        table.insert(
            parts,
            part("Stem" .. i, "Block", { size * 0.06, size * 0.7, size * 0.06 }, { math.cos(angle) * size * 0.4, size * 0.35, math.sin(angle) * size * 0.4 }, "leafDark")
        )
        table.insert(
            parts,
            part("Bloom" .. i, "Ball", { size * 0.3, size * 0.24, size * 0.3 }, { math.cos(angle) * size * 0.4, size * 0.76, math.sin(angle) * size * 0.4 }, i % 2 == 0 and "cloth" or "glow")
        )
    end
    return { footprint = size * 1.4, height = size, parts = parts }
end

-- A floating shard, for the Void. It hangs above the ground, which is what
-- makes that map feel like it is falling apart.
local function shard(size: number): Prop
    local parts = {
        part("Core", "CornerWedge", { size, size * 1.6, size }, { 0, size * 1.6, 0 }, "glow", { 22, 34, 12 }),
    }
    for _, p in ipairs(lean(size * 0.34, size * 0.9, 3, size * 0.1, "pale")) do
        table.insert(parts, part(p.name, p.shape, p.size, { p.at[1], p.at[2] + size * 0.9, p.at[3] }, p.color, p.rot))
    end
    return { footprint = size * 1.2, height = size * 2.4, parts = parts }
end

-- A leaning fence: two posts and two rails. Town edge furniture.
local function fence(width: number): Prop
    return {
        footprint = width * 1.1,
        height = width * 0.7,
        parts = {
            part("PostA", "Block", { width * 0.08, width * 0.62, width * 0.08 }, { -width * 0.45, width * 0.31, 0 }, "bark"),
            part("PostB", "Block", { width * 0.08, width * 0.62, width * 0.08 }, { width * 0.45, width * 0.31, 0 }, "bark"),
            part("RailA", "Block", { width, width * 0.07, width * 0.05 }, { 0, width * 0.46, 0 }, "wood"),
            part("RailB", "Block", { width, width * 0.07, width * 0.05 }, { 0, width * 0.24, 0 }, "wood"),
        },
    }
end

-- An ice spire, for the cold end of the Cavern.
local function spire(height: number): Prop
    local parts = {}
    for _, p in ipairs(lean(height * 0.3, height, 5, height * 0.05, "pale")) do
        table.insert(parts, p)
    end
    return { footprint = height * 0.5, height = height, parts = parts }
end

--------------------------------------------------------------------------
-- Prontera furniture. The town in Ragnarok Online is a walled city of pale
-- stone with red tiled roofs, built around a market square and a fountain,
-- with the roads running out of the square to the gates. These recipes are
-- that vocabulary, so the town reads as a city rather than a field with
-- houses on it.
--------------------------------------------------------------------------

-- The central fountain: a stepped basin with a column and a jet. This is the
-- landmark every Ragnarok town is built around, so it is the biggest single
-- prop in the town.
local function fountain(size: number): Prop
    local parts = {
        part("Basin", "Cylinder", { size * 0.5, size * 1.5, size * 1.5 }, { 0, size * 0.25, 0 }, "stone", { 0, 0, 90 }),
        part("BasinLip", "Cylinder", { size * 0.16, size * 1.72, size * 1.72 }, { 0, size * 0.5, 0 }, "stoneDark", { 0, 0, 90 }),
        part("Water", "Cylinder", { size * 0.44, size * 1.3, size * 1.3 }, { 0, size * 0.44, 0 }, "water", { 0, 0, 90 }, 0.45),
        part("Pedestal", "Cylinder", { size * 0.4, size * 0.5, size * 0.5 }, { 0, size * 0.7, 0 }, "stone", { 0, 0, 90 }),
        part("Column", "Cylinder", { size * 0.7, size * 0.28, size * 0.28 }, { 0, size * 1.15, 0 }, "pale", { 0, 0, 90 }),
        part("Bowl", "Cylinder", { size * 0.2, size * 0.8, size * 0.8 }, { 0, size * 1.55, 0 }, "stoneDark", { 0, 0, 90 }),
        part("Jet", "Cylinder", { size * 0.5, size * 0.14, size * 0.14 }, { 0, size * 1.85, 0 }, "glow", { 0, 0, 90 }, 0.35),
    }
    return { footprint = size * 1.8, height = size * 2.1, parts = parts }
end

-- A run of city wall: a stone band with a walkway and a crenellated top. The
-- town is walled, and a wall is what tells the player where the city ends.
local function wallPanel(width: number): Prop
    local parts = {
        part("Base", "Block", { width, width * 0.18, width * 0.34 }, { 0, width * 0.09, 0 }, "stoneDark"),
        part("Body", "Block", { width, width * 0.62, width * 0.3 }, { 0, width * 0.49, 0 }, "stone"),
        part("Walkway", "Block", { width, width * 0.1, width * 0.42 }, { 0, width * 0.85, 0 }, "stoneDark"),
    }
    -- Merlons along the top, spaced so the gaps read as battlements.
    local count = 5
    for i = 1, count do
        local t = (i - 0.5) / count
        table.insert(parts, part("Merlon" .. i, "Block", { width * 0.09, width * 0.2, width * 0.36 },
            { -width * 0.5 + width * t, width * 1.0, 0 }, "stone"))
    end
    return { footprint = width * 1.05, height = width * 1.1, parts = parts }
end

-- A gate tower: a squat tower wider at the top than the wall, with a red
-- tiled cap. Flanks the city gates.
local function gateTower(size: number): Prop
    return {
        footprint = size * 1.1,
        height = size * 2.2,
        parts = {
            part("Body", "Block", { size, size * 1.5, size }, { 0, size * 0.75, 0 }, "stone"),
            part("Belt", "Block", { size * 1.12, size * 0.14, size * 1.12 }, { 0, size * 1.45, 0 }, "stoneDark"),
            part("Cap", "Block", { size * 1.2, size * 0.16, size * 1.2 }, { 0, size * 1.6, 0 }, "roof"),
            part("RoofA", "Wedge", { size * 1.24, size * 0.5, size * 1.24 }, { 0, size * 1.9, 0 }, "roof"),
            part("Window", "Block", { size * 0.22, size * 0.3, size * 0.06 }, { 0, size * 0.95, -size * 0.52 }, "glow"),
        },
    }
end

-- A gate arch: two piers with a lintel, the way into the city. Solid, so the
-- player walks through the gap rather than over the top.
local function gateArch(size: number): Prop
    local half = size * 0.5
    return {
        footprint = size * 1.1,
        height = size * 1.5,
        parts = {
            part("PierL", "Block", { size * 0.22, size * 1.1, size * 0.4 }, { -half, size * 0.55, 0 }, "stone"),
            part("PierR", "Block", { size * 0.22, size * 1.1, size * 0.4 }, { half, size * 0.55, 0 }, "stone"),
            part("Lintel", "Block", { size * 1.05, size * 0.26, size * 0.46 }, { 0, size * 1.2, 0 }, "stoneDark"),
            part("Banner", "Block", { size * 0.3, size * 0.42, size * 0.04 }, { 0, size * 0.86, -size * 0.22 }, "cloth"),
        },
    }
end

-- The church: a tall hall with a steep red roof and a spire. Ragnarok's
-- Prontera Church is the tallest thing on the skyline, so it is here too.
local function church(size: number): Prop
    local parts = {
        part("Nave", "Block", { size * 1.5, size * 0.9, size * 0.8 }, { 0, size * 0.45, 0 }, "pale"),
        part("Roof", "Wedge", { size * 1.6, size * 0.7, size * 0.92 }, { 0, size * 1.2, 0 }, "roof"),
        part("Door", "Block", { size * 0.3, size * 0.5, size * 0.06 }, { 0, size * 0.25, -size * 0.42 }, "bark"),
        part("Rose", "Ball", { size * 0.24, size * 0.24, size * 0.06 }, { 0, size * 0.66, -size * 0.42 }, "glow"),
        part("Tower", "Block", { size * 0.42, size * 1.7, size * 0.42 }, { -size * 0.68, size * 0.85, 0 }, "pale"),
    }
    for _, p in ipairs(taper(size * 0.5, size * 0.9, 4, "roof")) do
        table.insert(parts, part(p.name, p.shape, p.size, { p.at[1] - size * 0.68, p.at[2] + size * 1.7, p.at[3] }, p.color, p.rot))
    end
    table.insert(parts, part("Cross", "Block", { size * 0.06, size * 0.3, size * 0.06 }, { -size * 0.68, size * 2.75, 0 }, "metal"))
    table.insert(parts, part("CrossArm", "Block", { size * 0.22, size * 0.06, size * 0.06 }, { -size * 0.68, size * 2.8, 0 }, "metal"))
    return { footprint = size * 1.9, height = size * 2.9, parts = parts }
end

-- A hero statue on a plinth. Squares have them; this one is the town's.
local function statue(size: number): Prop
    return {
        footprint = size * 1.1,
        height = size * 2.4,
        parts = {
            part("Plinth", "Block", { size, size * 0.5, size }, { 0, size * 0.25, 0 }, "stoneDark"),
            part("Step", "Block", { size * 1.15, size * 0.12, size * 1.15 }, { 0, size * 0.56, 0 }, "stone"),
            part("Legs", "Block", { size * 0.34, size * 0.6, size * 0.3 }, { 0, size * 0.92, 0 }, "metal"),
            part("Torso", "Block", { size * 0.5, size * 0.55, size * 0.36 }, { 0, size * 1.48, 0 }, "metal"),
            part("Head", "Ball", { size * 0.3, size * 0.32, size * 0.3 }, { 0, size * 1.88, 0 }, "metal"),
            part("Arm", "Block", { size * 0.14, size * 0.5, size * 0.14 }, { size * 0.36, size * 1.55, 0 }, "metal", { 0, 0, -24 }),
            part("Sword", "Block", { size * 0.08, size * 0.9, size * 0.08 }, { size * 0.52, size * 1.9, 0 }, "pale", { 0, 0, -18 }),
        },
    }
end

-- A signpost: a post with two boards. Marks where the roads leave the square.
local function signpost(size: number): Prop
    return {
        footprint = size * 0.9,
        height = size * 2.2,
        parts = {
            part("Post", "Block", { size * 0.14, size * 1.8, size * 0.14 }, { 0, size * 0.9, 0 }, "bark"),
            part("BoardA", "Block", { size * 1.1, size * 0.28, size * 0.08 }, { size * 0.36, size * 1.66, 0 }, "wood"),
            part("BoardB", "Block", { size * 0.9, size * 0.26, size * 0.08 }, { -size * 0.3, size * 1.3, 0 }, "wood"),
        },
    }
end

-- A stone bench. Street furniture, so the square is somewhere people sit.
local function bench(size: number): Prop
    return {
        footprint = size * 1.2,
        height = size * 0.8,
        parts = {
            part("Seat", "Block", { size * 1.1, size * 0.12, size * 0.4 }, { 0, size * 0.44, 0 }, "wood"),
            part("Back", "Block", { size * 1.1, size * 0.34, size * 0.1 }, { 0, size * 0.66, size * 0.16 }, "wood"),
            part("LegA", "Block", { size * 0.12, size * 0.4, size * 0.36 }, { -size * 0.44, size * 0.2, 0 }, "stoneDark"),
            part("LegB", "Block", { size * 0.12, size * 0.4, size * 0.36 }, { size * 0.44, size * 0.2, 0 }, "stoneDark"),
        },
    }
end

-- A hand cart with sacks on it. Market trade, and the reason the square has
-- clutter in it rather than only buildings.
local function cart(size: number): Prop
    return {
        footprint = size * 1.5,
        height = size * 1.1,
        parts = {
            part("Bed", "Block", { size * 1.3, size * 0.12, size * 0.7 }, { 0, size * 0.5, 0 }, "wood"),
            part("WallF", "Block", { size * 1.3, size * 0.3, size * 0.08 }, { 0, size * 0.7, -size * 0.3 }, "wood"),
            part("WallB", "Block", { size * 1.3, size * 0.3, size * 0.08 }, { 0, size * 0.7, size * 0.3 }, "wood"),
            part("SackA", "Ball", { size * 0.4, size * 0.34, size * 0.4 }, { -size * 0.3, size * 0.7, 0 }, "cloth"),
            part("SackB", "Ball", { size * 0.34, size * 0.3, size * 0.34 }, { size * 0.25, size * 0.68, size * 0.06 }, "cloth"),
            part("WheelA", "Cylinder", { size * 0.1, size * 0.5, size * 0.5 }, { -size * 0.34, size * 0.26, -size * 0.36 }, "bark", { 0, 0, 90 }),
            part("WheelB", "Cylinder", { size * 0.1, size * 0.5, size * 0.5 }, { size * 0.34, size * 0.26, -size * 0.36 }, "bark", { 0, 0, 90 }),
        },
    }
end

-- A hanging banner on two posts. Marks a shop or a guild, and adds height
-- and colour to a street that would otherwise be stone.
local function banner(size: number): Prop
    return {
        footprint = size * 0.8,
        height = size * 2.4,
        parts = {
            part("Post", "Block", { size * 0.1, size * 2.2, size * 0.1 }, { 0, size * 1.1, 0 }, "bark"),
            part("Arm", "Block", { size * 0.8, size * 0.08, size * 0.08 }, { size * 0.4, size * 2.1, 0 }, "bark"),
            part("Cloth", "Block", { size * 0.6, size * 0.9, size * 0.05 }, { size * 0.5, size * 1.6, 0 }, "cloth"),
        },
    }
end

-- A paved square: a flat stone disc laid on the ground. Non-solid, so it is
-- the one prop the player walks over rather than around.
local function paving(size: number): Prop
    return {
        footprint = size * 2,
        height = 1,
        parts = {
            part("Pave", "Cylinder", { 0.4, size * 2, size * 2 }, { 0, 0.2, 0 }, "stoneDark", { 0, 0, 90 }),
            part("Inlay", "Cylinder", { 0.5, size * 1.2, size * 1.2 }, { 0, 0.22, 0 }, "stone", { 0, 0, 90 }),
        },
    }
end

-- A still pond with a stone rim and reeds. The Meadow and the Cavern both
-- want standing water that is not a lava pool.
local function pond(size: number): Prop
    return {
        footprint = size * 2.2,
        height = size * 0.4,
        parts = {
            part("Water", "Cylinder", { 0.4, size * 2, size * 2 }, { 0, 0.22, 0 }, "water", { 0, 0, 90 }, 0.35),
            part("Rim", "Cylinder", { 0.5, size * 2.2, size * 2.2 }, { 0, 0.14, 0 }, "stoneDark", { 0, 0, 90 }),
        },
    }
end

-- A well: a stone drum, two posts and a tiled hood.
local function well(size: number): Prop
    return {
        footprint = size * 1.2,
        height = size * 1.6,
        parts = {
            part("Drum", "Cylinder", { size * 0.7, size, size }, { 0, size * 0.35, 0 }, "stone", { 0, 0, 90 }),
            part("Lip", "Cylinder", { size * 0.14, size * 1.15, size * 1.15 }, { 0, size * 0.74, 0 }, "stoneDark", { 0, 0, 90 }),
            part("PostL", "Block", { size * 0.12, size * 0.8, size * 0.12 }, { -size * 0.44, size * 1.15, 0 }, "bark"),
            part("PostR", "Block", { size * 0.12, size * 0.8, size * 0.12 }, { size * 0.44, size * 1.15, 0 }, "bark"),
            part("Hood", "Wedge", { size * 1.2, size * 0.4, size * 0.9 }, { 0, size * 1.7, 0 }, "roof"),
        },
    }
end

-- A field gate: a wooden arch at the edge of a monster field. Every field
-- gets one, so walking in reads as entering somewhere.
local function fieldGate(size: number): Prop
    local half = size * 0.5
    return {
        footprint = size * 1.1,
        height = size * 1.4,
        parts = {
            part("PostL", "Block", { size * 0.16, size * 1.1, size * 0.16 }, { -half, size * 0.55, 0 }, "bark"),
            part("PostR", "Block", { size * 0.16, size * 1.1, size * 0.16 }, { half, size * 0.55, 0 }, "bark"),
            part("Lintel", "Block", { size * 1.08, size * 0.16, size * 0.2 }, { 0, size * 1.2, 0 }, "wood"),
            part("Sign", "Block", { size * 0.5, size * 0.3, size * 0.06 }, { 0, size * 0.95, 0 }, "wood"),
        },
    }
end

-- A shrine: a small stone plinth with a glowing offering. The thing a
-- monster field has instead of a fountain.
local function shrine(size: number): Prop
    return {
        footprint = size * 1.1,
        height = size * 1.4,
        parts = {
            part("Base", "Block", { size, size * 0.3, size }, { 0, size * 0.15, 0 }, "stoneDark"),
            part("Body", "Block", { size * 0.6, size * 0.6, size * 0.6 }, { 0, size * 0.6, 0 }, "stone"),
            part("Relic", "Ball", { size * 0.4, size * 0.4, size * 0.4 }, { 0, size * 1.05, 0 }, "glow"),
        },
    }
end

-- A monolith: one tall slab, leaning slightly. The Void's landmark.
local function monolith(size: number): Prop
    local parts = {
        part("Base", "Block", { size * 1.4, size * 0.3, size * 1.2 }, { 0, size * 0.15, 0 }, "stoneDark"),
        part("Slab", "Block", { size * 0.8, size * 2.6, size * 0.5 }, { size * 0.1, size * 1.45, 0 }, "stone", { 4, 12, 0 }),
        part("Rune", "Block", { size * 0.3, size * 1.2, size * 0.06 }, { size * 0.22, size * 1.6, -size * 0.26 }, "glow", { 4, 12, 0 }),
    }
    return { footprint = size * 1.5, height = size * 2.9, parts = parts }
end

-- A hanging stalactite: an inverted taper, for the Cavern's ceiling.
local function stalactite(height: number): Prop
    local parts = {}
    for _, p in ipairs(taper(height * 0.4, height, 5, "stoneDark")) do
        -- Flip the stack upside down and hang it from the top.
        table.insert(parts, part(p.name, p.shape, p.size,
            { p.at[1], height - p.at[2], p.at[3] }, p.color, p.rot))
    end
    return { footprint = height * 0.5, height = height, parts = parts }
end

-- A lava vent: a cracked mound with a glowing throat. The Volcano's hazard.
local function vent(size: number): Prop
    local parts = {
        part("Mound", "Ball", { size * 1.8, size * 0.7, size * 1.8 }, { 0, size * 0.2, 0 }, "stoneDark"),
        part("Throat", "Cylinder", { 0.5, size * 0.9, size * 0.9 }, { 0, size * 0.55, 0 }, "glow", { 0, 0, 90 }),
    }
    for i = 1, 4 do
        local angle = (i - 1) / 4 * math.pi * 2
        table.insert(parts, part("Crack" .. i, "Block", { size * 0.9, size * 0.1, size * 0.16 },
            { math.cos(angle) * size * 0.75, size * 0.42, math.sin(angle) * size * 0.75 }, "glow", { 0, math.deg(angle), 0 }, 0.3))
    end
    return { footprint = size * 2, height = size * 1.1, parts = parts }
end

--------------------------------------------------------------------------
-- The catalogue. `base` is the prop's own size in studs and `variation` is how
-- much the scatter may change it, so one recipe covers a sapling and a great
-- tree.
--------------------------------------------------------------------------

export type KindDef = {
    id: string,
    -- Relative share of the place's prop budget.
    weight: number,
    base: number,
    variation: number,
    build: (size: number) -> Prop,
    -- Whether the player is stopped by it. Trees and houses block; grass and
    -- flowers do not.
    solid: boolean,
    -- Whether the prop hangs above the ground rather than standing on it.
    floating: boolean?,
    -- Whether the scatter must leave this prop's footprint clear when it is
    -- placed as a landmark. Paving is a floor, so props may stand on it; the
    -- default is true because a tree inside a church does not read as a city.
    reserve: boolean?,
}

local KINDS: { [string]: KindDef } = {}

local function kind(def: KindDef)
    KINDS[def.id] = def
end

-- Town: somewhere people live.
kind({ id = "House", weight = 3, base = 22, variation = 0.25, build = house, solid = true })
kind({ id = "Stall", weight = 2, base = 12, variation = 0.2, build = stall, solid = true })
kind({ id = "Lamp", weight = 3, base = 16, variation = 0.15, build = lamp, solid = false })
kind({ id = "Barrel", weight = 2, base = 4, variation = 0.25, build = barrel, solid = true })
kind({ id = "Crate", weight = 2, base = 5, variation = 0.25, build = crate, solid = true })
kind({ id = "Fence", weight = 3, base = 10, variation = 0.2, build = fence, solid = false })
kind({
    id = "TownTree",
    weight = 3,
    base = 16,
    variation = 0.3,
    build = function(s)
        return broadleaf(s, s * 0.8)
    end,
    solid = true,
})
kind({ id = "Bush", weight = 3, base = 4, variation = 0.35, build = bush, solid = false })
kind({ id = "Flowers", weight = 2, base = 4, variation = 0.4, build = flowers, solid = false })

-- Town, continued: the street furniture that turns a scatter of houses into a
-- city. Ragnarok's Prontera is a market square with roads out to the gates, so
-- the square needs stalls, benches, carts and paving, and the streets need
-- signs and banners.
kind({ id = "Signpost", weight = 2, base = 7, variation = 0.2, build = signpost, solid = true })
kind({ id = "Bench", weight = 3, base = 6, variation = 0.25, build = bench, solid = false })
kind({ id = "Cart", weight = 2, base = 8, variation = 0.25, build = cart, solid = true })
kind({ id = "Banner", weight = 2, base = 10, variation = 0.25, build = banner, solid = false })
kind({ id = "Paving", weight = 2, base = 9, variation = 0.3, build = paving, solid = false, reserve = false })
kind({ id = "Well", weight = 1, base = 8, variation = 0.2, build = well, solid = true })
-- Built by the world at the centre of the square rather than scattered, but
-- registered here so it has a recipe like everything else.
kind({ id = "Fountain", weight = 1, base = 14, variation = 0, build = fountain, solid = true })
kind({ id = "Wall", weight = 1, base = 16, variation = 0.1, build = wallPanel, solid = true })
kind({ id = "GateTower", weight = 1, base = 14, variation = 0.1, build = gateTower, solid = true })
kind({ id = "GateArch", weight = 1, base = 16, variation = 0.1, build = gateArch, solid = true })
kind({ id = "Church", weight = 1, base = 26, variation = 0.1, build = church, solid = true })
kind({ id = "Statue", weight = 1, base = 8, variation = 0.15, build = statue, solid = true })

-- Meadow: forest.
kind({ id = "Pine", weight = 4, base = 30, variation = 0.3, build = pine, solid = true })
kind({
    id = "Oak",
    weight = 3,
    base = 26,
    variation = 0.3,
    build = function(s)
        return broadleaf(s, s * 0.8)
    end,
    solid = true,
})
kind({ id = "Palm", weight = 1, base = 24, variation = 0.25, build = palm, solid = true })
kind({ id = "Mushroom", weight = 2, base = 7, variation = 0.4, build = mushroom, solid = false })
kind({ id = "MeadowRock", weight = 2, base = 7, variation = 0.4, build = rocks, solid = true })
kind({ id = "MeadowBush", weight = 3, base = 5, variation = 0.4, build = bush, solid = false })
kind({ id = "MeadowFlowers", weight = 3, base = 4, variation = 0.45, build = flowers, solid = false })
-- A pond and a shrine give the Meadow somewhere to be other than a corridor
-- of trees, and the shrine is what the arrival pad looks out at.
kind({ id = "MeadowPond", weight = 2, base = 11, variation = 0.3, build = pond, solid = false })
kind({ id = "MeadowShrine", weight = 1, base = 8, variation = 0.15, build = shrine, solid = true })
kind({ id = "MeadowGate", weight = 1, base = 12, variation = 0.1, build = fieldGate, solid = true })
kind({ id = "MeadowBench", weight = 2, base = 6, variation = 0.25, build = bench, solid = false })

-- Cavern: stone teeth.
kind({ id = "Stalagmite", weight = 4, base = 14, variation = 0.5, build = spike, solid = true })
kind({ id = "CaveRock", weight = 3, base = 9, variation = 0.45, build = rocks, solid = true })
kind({ id = "Crystal", weight = 3, base = 6, variation = 0.4, build = crystals, solid = false })
kind({ id = "IceSpire", weight = 2, base = 13, variation = 0.35, build = spire, solid = true })
kind({ id = "CaveRuin", weight = 1, base = 12, variation = 0.25, build = ruin, solid = true })
-- The ceiling hangs as well as the floor: stalactites give the Cavern a roof,
-- and a shrine marks where the road in ends.
kind({ id = "Stalactite", weight = 3, base = 16, variation = 0.4, build = stalactite, solid = false })
kind({ id = "CavernPond", weight = 2, base = 10, variation = 0.3, build = pond, solid = false })
kind({ id = "CavernShrine", weight = 1, base = 8, variation = 0.15, build = shrine, solid = true })
kind({ id = "CavernGate", weight = 1, base = 12, variation = 0.1, build = fieldGate, solid = true })

-- Volcano: burnt and glowing.
kind({ id = "DeadTree", weight = 3, base = 22, variation = 0.3, build = deadTree, solid = true })
kind({ id = "VolcanoRock", weight = 3, base = 10, variation = 0.45, build = rocks, solid = true })
kind({ id = "LavaPool", weight = 2, base = 9, variation = 0.4, build = pool, solid = false })
kind({ id = "VolcanoCrystal", weight = 2, base = 6, variation = 0.4, build = crystals, solid = false })
kind({ id = "AshSpike", weight = 2, base = 12, variation = 0.45, build = spike, solid = true })
-- Vents are the Volcano's own hazard: the ground itself is cracked and lit.
kind({ id = "VolcanoVent", weight = 3, base = 9, variation = 0.4, build = vent, solid = false })
kind({ id = "VolcanoShrine", weight = 1, base = 8, variation = 0.15, build = shrine, solid = true })
kind({ id = "VolcanoGate", weight = 1, base = 12, variation = 0.1, build = fieldGate, solid = true })
kind({ id = "VolcanoRuin", weight = 1, base = 13, variation = 0.25, build = ruin, solid = true })

-- Void: broken and floating.
kind({ id = "VoidCrystal", weight = 3, base = 7, variation = 0.45, build = crystals, solid = false })
kind({ id = "VoidShard", weight = 3, base = 8, variation = 0.5, build = shard, solid = false, floating = true })
kind({ id = "VoidPillar", weight = 2, base = 20, variation = 0.3, build = pillar, solid = true })
kind({ id = "VoidRuin", weight = 2, base = 13, variation = 0.3, build = ruin, solid = true })
kind({ id = "VoidTree", weight = 2, base = 20, variation = 0.3, build = deadTree, solid = true })
kind({ id = "VoidPool", weight = 1, base = 8, variation = 0.4, build = pool, solid = false })
-- The Void's landmark is a monolith, and its gate is the only thing standing
-- straight on the map.
kind({ id = "VoidMonolith", weight = 2, base = 10, variation = 0.3, build = monolith, solid = true })
kind({ id = "VoidShrine", weight = 1, base = 8, variation = 0.15, build = shrine, solid = true })
kind({ id = "VoidGate", weight = 1, base = 12, variation = 0.1, build = fieldGate, solid = true })

-- Heaven: colonnades and cloud.
kind({ id = "Pillar", weight = 4, base = 24, variation = 0.25, build = pillar, solid = true })
kind({ id = "HeavenRuin", weight = 2, base = 14, variation = 0.25, build = ruin, solid = true })
kind({ id = "HeavenCloud", weight = 3, base = 18, variation = 0.4, build = cloud, solid = false, floating = true })
kind({ id = "HeavenCrystal", weight = 2, base = 6, variation = 0.4, build = crystals, solid = false })
kind({ id = "HeavenBush", weight = 2, base = 5, variation = 0.4, build = bush, solid = false })
-- Heaven's landmark is a statue, and its paving is what makes the colonnade
-- read as a built place rather than a ring of columns on grass.
kind({ id = "HeavenStatue", weight = 1, base = 10, variation = 0.15, build = statue, solid = true })
kind({ id = "HeavenPaving", weight = 3, base = 10, variation = 0.3, build = paving, solid = false, reserve = false })
kind({ id = "HeavenShrine", weight = 1, base = 8, variation = 0.15, build = shrine, solid = true })
kind({ id = "HeavenGate", weight = 1, base = 12, variation = 0.1, build = fieldGate, solid = true })

-- The prop for a kind id, built at the given size, or nil for an unknown id.
function Scenery.build(kindId: string, size: number?): Prop?
    local def = KINDS[kindId]
    if not def then
        return nil
    end
    return def.build(size or def.base)
end

function Scenery.kindDef(kindId: string): KindDef?
    return KINDS[kindId]
end

function Scenery.kindIds(): { string }
    local out: { string } = {}
    for id in pairs(KINDS) do
        table.insert(out, id)
    end
    table.sort(out)
    return out
end

--------------------------------------------------------------------------
-- Placement. Each place names how much scenery it wants and out of which
-- families; the scatter then decides where each piece stands.
--------------------------------------------------------------------------

export type Plan = {
    -- Total props to attempt. Some attempts are rejected by the clearance and
    -- spacing rules, so the real count is a little lower.
    count: number,
    -- How far from the centre the scatter is allowed to reach, as a fraction
    -- of the place's radius.
    inner: number,
    outer: number,
    -- Minimum distance between two props, in studs.
    spacing: number,
    -- How far above the ground a floating prop hangs, in studs.
    floatHeight: number?,
    kinds: { string },
}

local PLANS: { [string]: Plan } = {
    Town = {
        count = 62,
        inner = 0.42,
        outer = 0.94,
        spacing = 11,
        kinds = {
            "House", "Stall", "Lamp", "Barrel", "Crate", "Fence", "TownTree", "Bush", "Flowers",
            "Signpost", "Bench", "Cart", "Banner", "Paving", "Well",
        },
    },
    Meadow = {
        count = 78,
        inner = 0.22,
        outer = 0.96,
        spacing = 12,
        kinds = {
            "Pine", "Oak", "Palm", "Mushroom", "MeadowRock", "MeadowBush", "MeadowFlowers",
            "MeadowPond", "MeadowShrine", "MeadowGate", "MeadowBench",
        },
    },
    Cavern = {
        count = 72,
        inner = 0.2,
        outer = 0.96,
        spacing = 11,
        kinds = {
            "Stalagmite", "CaveRock", "Crystal", "IceSpire", "CaveRuin",
            "Stalactite", "CavernPond", "CavernShrine", "CavernGate",
        },
    },
    Volcano = {
        count = 70,
        inner = 0.22,
        outer = 0.96,
        spacing = 12,
        kinds = {
            "DeadTree", "VolcanoRock", "LavaPool", "VolcanoCrystal", "AshSpike",
            "VolcanoVent", "VolcanoShrine", "VolcanoGate", "VolcanoRuin",
        },
    },
    Void = {
        count = 68,
        inner = 0.22,
        outer = 0.96,
        spacing = 12,
        floatHeight = 10,
        kinds = {
            "VoidCrystal", "VoidShard", "VoidPillar", "VoidRuin", "VoidTree", "VoidPool",
            "VoidMonolith", "VoidShrine", "VoidGate",
        },
    },
    Heaven = {
        count = 64,
        inner = 0.24,
        outer = 0.96,
        spacing = 13,
        floatHeight = 26,
        kinds = {
            "Pillar", "HeavenRuin", "HeavenCloud", "HeavenCrystal", "HeavenBush",
            "HeavenStatue", "HeavenPaving", "HeavenShrine", "HeavenGate",
        },
    },
}

function Scenery.plan(placeId: string?): Plan
    return PLANS[placeId or "Town"] or PLANS.Town
end

export type Placement = {
    kind: string,
    x: number,
    y: number,
    z: number,
    -- Size in studs the recipe is built at.
    size: number,
    -- Rotation about Y, in degrees.
    yaw: number,
    solid: boolean,
}

export type KeepOut = { x: number, z: number, radius: number }

-- The distance from the centre a prop is allowed to stand, in studs.
local function ring(plan: Plan, radius: number): (number, number)
    return radius * plan.inner, radius * plan.outer
end

-- Place the scenery for one place.
--
-- Everything is derived from `seed`, so the same place looks identical on
-- every server and a test can assert the exact result. `keepOut` is how the
-- spawn pad, the portals and the farm plots stay clear: the caller passes the
-- circles it needs protected.
--
-- Kinds are filled largest-first. A big prop needs more room, so on a crowded
-- map it is the one that gets rejected; filling it first is what keeps a
-- meadow a forest instead of a field of flowers with two trees in it.
function Scenery.scatter(
    placeId: string,
    centre: { x: number, y: number, z: number },
    radius: number,
    seed: number,
    keepOut: { KeepOut }?
): { Placement }
    local plan = Scenery.plan(placeId)
    local rng = Random.new(seed)
    local inner, outer = ring(plan, radius)

    local placed: { Placement } = {}
    local taken: { KeepOut } = {}
    for _, circle in ipairs(keepOut or {}) do
        table.insert(taken, circle)
    end

    -- Each kind's share of the plan comes from its weight, so the families the
    -- plan cares about most are the ones that fill the map.
    local kinds: { string } = {}
    local totalWeight = 0
    for _, id in ipairs(plan.kinds) do
        local def = KINDS[id]
        if def then
            table.insert(kinds, id)
            totalWeight = totalWeight + def.weight
        end
    end
    table.sort(kinds, function(a, b)
        local da, db = KINDS[a], KINDS[b]
        if da.base ~= db.base then
            return da.base > db.base
        end
        return a < b
    end)

    -- A prop is rejected when it lands inside a protected circle or closer to
    -- an earlier prop than the spacing rule allows.
    local function attempt(kindId: string): boolean
        local def = KINDS[kindId]
        local angle = rng:nextNumber() * math.pi * 2
        -- sqrt keeps the scatter even across the ring instead of bunching at
        -- the inner edge, which is where a naive random radius always lands.
        local t = math.sqrt(rng:nextNumber())
        local distance = inner + (outer - inner) * t
        local x = centre.x + math.cos(angle) * distance
        local z = centre.z + math.sin(angle) * distance

        local size = def.base * (1 + (rng:nextNumber() * 2 - 1) * def.variation)
        local prop = def.build(size)
        -- Small props are allowed to sit closer together, otherwise a single
        -- global spacing leaves a full forest with no undergrowth in it.
        local gap = math.max(plan.spacing * 0.35, prop.footprint * 0.6)

        for _, circle in ipairs(taken) do
            local dx, dz = x - circle.x, z - circle.z
            if dx * dx + dz * dz < (circle.radius + prop.footprint * 0.5) ^ 2 then
                return false
            end
        end

        local y = centre.y or 0
        if def.floating then
            y = y + (plan.floatHeight or 0) + size * (0.6 + rng:nextNumber() * 1.4)
        end
        table.insert(placed, {
            kind = kindId,
            x = x,
            y = y,
            z = z,
            size = size,
            yaw = rng:nextNumber() * 360,
            solid = def.solid,
        })
        table.insert(taken, { x = x, z = z, radius = gap })
        return true
    end

    for _, kindId in ipairs(kinds) do
        local def = KINDS[kindId]
        local share = math.max(1, math.floor(plan.count * def.weight / totalWeight + 0.5))
        local tries = 0
        local made = 0
        -- The try budget is generous because a large prop is rejected often;
        -- it is still bounded, so a saturated map finishes instead of looping.
        while made < share and tries < share * 10 do
            tries += 1
            if attempt(kindId) then
                made += 1
            end
        end
    end

    return placed
end

-- The seed for a place. Fixed per id so the layout never shifts between
-- servers or between restarts.
function Scenery.seedFor(placeId: string): number
    local seed = 2166136261
    for i = 1, #placeId do
        seed = bit32.bxor(seed, string.byte(placeId, i))
        seed = bit32.band(seed * 16777619, 0xFFFFFFFF)
    end
    return seed
end

--------------------------------------------------------------------------
-- Landmarks. The scatter makes a place look inhabited; the landmarks make it
-- look built. These are placed on purpose rather than at random: a fountain
-- belongs at the centre of the square, a church on the skyline, and a wall on
-- the rim, and a random scatter would put any of them anywhere.
--
-- Ragnarok's Prontera is the model: a walled city with gates, a market square
-- and a fountain at its heart, a church on the high ground, and roads running
-- out of the square to the gates.
--------------------------------------------------------------------------

export type Landmark = Placement

-- How many wall segments ring the town. Sixteen gives a panel every 22.5
-- degrees, which at the town's radius is a wall about 25 studs long: wide
-- enough to read as a wall, short enough to follow the curve.
local WALL_SEGMENTS = 16

export type LandmarkOpts = {
    -- Where the player arrives, so a field's gate can be built over it.
    arrival: { x: number, y: number, z: number }?,
    -- Directions (radians) the town's gates face. The world passes the field
    -- directions in, so every road out of the square leads to a real portal
    -- instead of to a wall the player has to walk around.
    gates: { number }?,
}

-- The town layout: square, fountain, church, walls and gates.
local function townLandmarks(
    centre: { x: number, y: number, z: number },
    radius: number,
    gates: { number }?
): { Landmark }
    local out: { Landmark } = {}
    local y = centre.y or 0

    local function add(kind: string, size: number, x: number, z: number, yaw: number)
        local def = KINDS[kind]
        table.insert(out, {
            kind = kind,
            x = x,
            y = y,
            z = z,
            size = size,
            yaw = yaw,
            solid = def and def.solid or true,
        })
    end

    -- The fountain is the centre of the square, exactly as in Prontera.
    add("Fountain", 15, centre.x, centre.z, 0)

    -- A paved apron around the fountain, so the market square reads as a floor
    -- rather than as grass with a fountain on it. It stops short of the farm
    -- plots at PlotRingRadius, so a paving stone never sits under a plot.
    for i = 1, 8 do
        local angle = (i - 1) / 8 * math.pi * 2
        add("Paving", 6, centre.x + math.cos(angle) * 14, centre.z + math.sin(angle) * 14, math.deg(angle))
    end

    -- The church sits on the skyline in the gap between two gates, with its
    -- door facing the square. The gates are cut at the field directions and the
    -- farm plots ring the square every 60 degrees, so the church goes on a
    -- bearing that clears both: at 36 degrees it is 24 degrees off the nearest
    -- plot and 36 off the nearest gate.
    local churchAngle = math.rad(36)
    local churchR = radius * 0.6
    add(
        "Church",
        15,
        centre.x + math.cos(churchAngle) * churchR,
        centre.z + math.sin(churchAngle) * churchR,
        math.deg(churchAngle) - 90
    )

    -- A statue in the gap between two farm plots, facing the fountain. The
    -- plots ring the square at PlotRingRadius, so the statue is placed on the
    -- half-angle between two of them rather than at a plot's own bearing.
    local plotGap = math.pi / 6
    add(
        "Statue",
        8,
        centre.x + math.cos(plotGap) * 21,
        centre.z + math.sin(plotGap) * 21,
        math.deg(plotGap) - 90
    )

    -- The city wall: a ring of panels with a gate wherever a road leaves the
    -- city. The gate directions come from the caller, so a gate always lines up
    -- with the portal behind it and the player walks straight out.
    local wallR = radius * 0.93
    local gateAngles = gates or {}
    local segmentWidth = 2 * math.pi * wallR / WALL_SEGMENTS
    local gateHalf = segmentWidth * 0.85

    -- Panels first: every segment that is not inside a gate opening.
    for step = 1, WALL_SEGMENTS do
        local angle = (step - 0.5) / WALL_SEGMENTS * math.pi * 2
        local blocked = false
        for _, gate in ipairs(gateAngles) do
            local delta = math.abs(((angle - gate + math.pi) % (math.pi * 2)) - math.pi)
            if delta * wallR < gateHalf then
                blocked = true
                break
            end
        end
        if not blocked then
            add(
                "Wall",
                segmentWidth * 0.98,
                centre.x + math.cos(angle) * wallR,
                centre.z + math.sin(angle) * wallR,
                -- 90 - angle lines the panel's long axis up with the tangent,
                -- so a run of panels traces the ring. angle + 90 would stand
                -- every panel on end and point its thin edge along the wall.
                math.deg(math.pi / 2 - angle)
            )
        end
    end

    -- Then a gate in each opening: an arch with a tower butted against each
    -- side of it, so the wall, the towers and the arch close the gap rather
    -- than leaving a slit the player can slip through beside the gate.
    --
    -- The arch's opening runs along its local Z axis, so its yaw lines that
    -- axis up with the road: the radial direction. The towers are wall pieces,
    -- so they take the wall's tangent yaw instead.
    local archHalf = 18 * 1.1 * 0.5
    for _, gate in ipairs(gateAngles) do
        add(
            "GateArch",
            18,
            centre.x + math.cos(gate) * wallR,
            centre.z + math.sin(gate) * wallR,
            math.deg(math.atan2(math.cos(gate), math.sin(gate)))
        )
        for _, side in ipairs({ -1, 1 }) do
            local offset = (archHalf + 6.6) / wallR
            local ta = gate + side * offset
            add(
                "GateTower",
                12,
                centre.x + math.cos(ta) * wallR,
                centre.z + math.sin(ta) * wallR,
                math.deg(math.pi / 2 - ta)
            )
        end
    end

    return out
end

-- A monster field's layout: a gate where the road comes in, a landmark at the
-- centre, and paving on the approach.
local function fieldLandmarks(
    placeId: string,
    centre: { x: number, y: number, z: number },
    radius: number,
    arrival: { x: number, y: number, z: number }?
): { Landmark }
    local out: { Landmark } = {}
    local y = centre.y or 0

    local function add(kind: string, size: number, x: number, z: number, yaw: number)
        local def = KINDS[kind]
        table.insert(out, {
            kind = kind,
            x = x,
            y = y,
            z = z,
            size = size,
            yaw = yaw,
            solid = def and def.solid or true,
        })
    end

    -- The landmark a field is known by. The Void gets a monolith and Heaven a
    -- statue; the rest get a shrine, which is a landmark without being a
    -- second town square.
    local landmarks: { [string]: string } = {
        Meadow = "MeadowShrine",
        Cavern = "CavernShrine",
        Volcano = "VolcanoShrine",
        Void = "VoidMonolith",
        Heaven = "HeavenStatue",
    }
    local gates: { [string]: string } = {
        Meadow = "MeadowGate",
        Cavern = "CavernGate",
        Volcano = "VolcanoGate",
        Void = "VoidGate",
        Heaven = "HeavenGate",
    }
    local pavings: { [string]: string } = {
        Meadow = "Paving",
        Cavern = "Paving",
        Volcano = "Paving",
        Void = "Paving",
        Heaven = "HeavenPaving",
    }

    local landmark = landmarks[placeId]
    if landmark then
        add(landmark, KINDS[landmark].base, centre.x, centre.z, 0)
    end

    -- The gate stands over the arrival point and faces the middle of the map,
    -- so the player walks in under the arch and straight down the road. The
    -- arch's opening runs along its local Z axis, so the yaw is chosen to line
    -- that axis up with the direction from the gate to the middle.
    local gate = gates[placeId]
    if gate and arrival then
        local gx, gz = centre.x - arrival.x, centre.z - arrival.z
        local gl = math.max(1, math.sqrt(gx * gx + gz * gz))
        add(gate, KINDS[gate].base, arrival.x, arrival.z, math.deg(math.atan2(gx / gl, gz / gl)))
    end

    -- A paved approach from the gate toward the landmark.
    local paving = pavings[placeId]
    if paving and arrival then
        local dx, dz = centre.x - arrival.x, centre.z - arrival.z
        local length = math.max(1, math.sqrt(dx * dx + dz * dz))
        local ux, uz = dx / length, dz / length
        local yaw = math.deg(math.atan2(dz, dx))
        for step = 1, 4 do
            local t = step / 5
            add(paving, 9, arrival.x + ux * length * t, arrival.z + uz * length * t, yaw)
        end
    end

    return out
end

-- The structural props for a place, placed on purpose.
function Scenery.landmarks(
    placeId: string,
    centre: { x: number, y: number, z: number },
    radius: number,
    opts: LandmarkOpts?
): { Landmark }
    local options = opts or {}
    if placeId == "Town" then
        return townLandmarks(centre, radius, options.gates)
    end
    return fieldLandmarks(placeId, centre, radius, options.arrival)
end

return Scenery

--!strict
-- The five monster fields and the town hub. Pure Luau.
--
-- This is the map layer: where each field sits in the world, what level it
-- wants, what it pays, and which monsters live there. Zones.luau keeps the
-- reward/difficulty tiers that the rest of the game already multiplies by;
-- Fields adds the physical layout on top, so the world can be built from data
-- instead of hard-coded coordinates in the Roblox layer.

local Config = require("./Config")
local Zones = require("./Zones")

local Fields = {}

export type FieldDef = {
        id: string,
        name: string,
        levelRequirement: number,
        coinMultiplier: number,
        difficultyMultiplier: number,
        index: number,
        -- World position of the field centre.
        position: { x: number, y: number, z: number },
        groundColor: { number },
        -- Short line shown under the name, so the map has some character.
        tagline: string,
}

-- The town sits at the origin and the fields ring it. Index 0 is the town.
local ORDER = { "Meadow", "Cavern", "Volcano", "Void", "Heaven" }

local TAGLINES: { [string]: string } = {
        Meadow = "Where every adventurer starts.",
        Cavern = "Cold stone and colder things.",
        Volcano = "The ground remembers fire.",
        Void = "Nothing here wants you to leave.",
        Heaven = "The last gate before the end.",
}

local GROUND: { [string]: { number } } = {
        Meadow = { 96, 168, 104 },
        Cavern = { 92, 96, 128 },
        Volcano = { 140, 78, 62 },
        Void = { 88, 76, 132 },
        Heaven = { 214, 214, 236 },
}

-- How each place looks: ambient light, fog, and the accent colour used for
-- its glow, particles and sign. This is what makes the five maps read as five
-- places rather than the same disc with a different floor tint.
export type Look = {
        ambient: { number },
        outdoorAmbient: { number },
        fog: { number },
        fogEnd: number,
        brightness: number,
        -- Colour of the glowing rim and floating motes.
        accent: { number },
        -- Sky tint the client lerps toward on arrival.
        sky: { number },
        -- Whether this place has floating light motes.
        motes: boolean,
}

local LOOKS: { [string]: Look } = {
        Town = {
                ambient = { 140, 136, 128 },
                outdoorAmbient = { 150, 144, 132 },
                fog = { 196, 206, 226 },
                fogEnd = 900,
                brightness = 2.2,
                accent = { 255, 214, 92 },
                sky = { 120, 170, 255 },
                motes = false,
        },
        Meadow = {
                ambient = { 130, 150, 120 },
                outdoorAmbient = { 140, 160, 125 },
                fog = { 168, 206, 168 },
                fogEnd = 620,
                brightness = 2.6,
                accent = { 140, 255, 170 },
                sky = { 130, 190, 255 },
                motes = true,
        },
        Cavern = {
                ambient = { 70, 78, 110 },
                outdoorAmbient = { 62, 70, 104 },
                fog = { 60, 70, 104 },
                fogEnd = 320,
                brightness = 1.1,
                accent = { 150, 200, 255 },
                sky = { 60, 70, 120 },
                motes = true,
        },
        Volcano = {
                ambient = { 150, 90, 70 },
                outdoorAmbient = { 140, 84, 66 },
                fog = { 120, 58, 44 },
                fogEnd = 300,
                brightness = 1.5,
                accent = { 255, 120, 60 },
                sky = { 150, 70, 50 },
                motes = true,
        },
        Void = {
                ambient = { 80, 66, 120 },
                outdoorAmbient = { 74, 60, 116 },
                fog = { 52, 42, 88 },
                fogEnd = 260,
                brightness = 0.9,
                accent = { 180, 130, 255 },
                sky = { 50, 40, 90 },
                motes = true,
        },
        Heaven = {
                ambient = { 200, 202, 230 },
                outdoorAmbient = { 210, 212, 240 },
                fog = { 226, 232, 255 },
                fogEnd = 520,
                brightness = 2.8,
                accent = { 255, 246, 200 },
                sky = { 200, 220, 255 },
                motes = true,
        },
}

-- The look for a place. Falls back to the town's, so an unknown id is still
-- lit rather than black.
function Fields.look(id: string?): Look
        if id == nil then
                return LOOKS.Town
        end
        if id == "Town" then
                return LOOKS.Town
        end
        return LOOKS[id] or LOOKS.Town
end

local POSITIONS: { [string]: { x: number, y: number, z: number } } = {}

-- Place the fields evenly on a ring around the town, starting north.
local function computePositions()
        local count = #ORDER
        local radius = Config.Fields.RingRadius
        for index, id in ipairs(ORDER) do
                local angle = ((index - 1) / count) * math.pi * 2
                POSITIONS[id] = {
                        x = math.floor(math.cos(angle) * radius + 0.5),
                        y = 0,
                        z = math.floor(math.sin(angle) * radius + 0.5),
                }
        end
end

computePositions()

function Fields.town(): any
        return {
                id = "Town",
                name = "Prontera Town",
                position = { x = 0, y = 0, z = 0 },
                radius = Config.Town.Radius,
                safe = Config.Town.Safe,
                groundColor = Config.Town.GroundColor,
        }
end

function Fields.list(): { FieldDef }
        local out: { FieldDef } = {}
        for _, id in ipairs(ORDER) do
                local zone = Zones.getDef(id)
                if zone then
                        local pos = POSITIONS[id]
                        table.insert(out, {
                                id = id,
                                name = zone.name,
                                levelRequirement = zone.levelRequirement,
                                coinMultiplier = zone.coinMultiplier,
                                difficultyMultiplier = zone.difficultyMultiplier,
                                index = zone.index,
                                position = pos,
                                groundColor = GROUND[id] or { 120, 140, 120 },
                                tagline = TAGLINES[id] or "",
                        })
                end
        end
        return out
end

function Fields.getDef(id: string): FieldDef?
        if id == "Town" or id == nil then
                return nil
        end
        for _, def in ipairs(Fields.list()) do
                if def.id == id then
                        return def
                end
        end
        return nil
end

function Fields.isTown(id: string): boolean
        return id == "Town"
end

-- Position of a place by id. The town is the origin.
function Fields.positionOf(id: string): { x: number, y: number, z: number }
        if Fields.isTown(id) then
                return { x = 0, y = 0, z = 0 }
        end
        local pos = POSITIONS[id]
        return pos or { x = 0, y = 0, z = 0 }
end

-- Where a player lands when they arrive. In town that is just south of the
-- centre; in a field it is the edge of the arrival platform.
function Fields.arrivalOf(id: string): { x: number, y: number, z: number }
        local base = Fields.positionOf(id)
        if Fields.isTown(id) then
                return { x = base.x, y = base.y, z = base.z + Config.Town.ArrivalOffsetZ }
        end
        return { x = base.x, y = base.y, z = base.z + Config.Fields.PortalRadius + 6 }
end

-- Can this player travel here? Returns (allowed, reason).
function Fields.canEnter(id: string, level: number, ownedPass: boolean?): (boolean, string?)
        if Fields.isTown(id) then
                return true, nil
        end
        local def = Fields.getDef(id)
        if not def then
                return false, "UNKNOWN_FIELD"
        end
        if not Zones.isUnlocked(id, level, ownedPass) then
                return false, "FIELD_LOCKED"
        end
        return true, nil
end

-- The next field the player has not unlocked yet, used to point them onward.
function Fields.nextLocked(level: number, ownedPass: boolean?): FieldDef?
        for _, def in ipairs(Fields.list()) do
                if not Zones.isUnlocked(def.id, level, ownedPass) then
                        return def
                end
        end
        return nil
end

-- Spawn point for a monster in a field. Deterministic given the index, and
-- never on the arrival platform.
function Fields.spawnPoint(id: string, index: number, total: number): { x: number, y: number, z: number }
        local centre = Fields.positionOf(id)
        local count = math.max(1, total)
        local angle = (index / count) * math.pi * 2
        -- Alternate two radii so monsters do not spawn on one thin ring.
        local radius = Config.Fields.SpawnRadius * (0.7 + 0.3 * ((index % 2)))
        return {
                x = centre.x + math.floor(math.cos(angle) * radius + 0.5),
                y = 0,
                z = centre.z + math.floor(math.sin(angle) * radius + 0.5),
        }
end

function Fields.snapshot(level: number, ownedPass: boolean?): { any }
        local out = {}
        for _, def in ipairs(Fields.list()) do
                table.insert(out, {
                        id = def.id,
                        name = def.name,
                        tagline = def.tagline,
                        levelRequirement = def.levelRequirement,
                        coinMultiplier = def.coinMultiplier,
                        unlocked = Zones.isUnlocked(def.id, level, ownedPass),
                })
        end
        return out
end

return Fields

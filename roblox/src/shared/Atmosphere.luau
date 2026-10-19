--!strict
-- Atmosphere. Pure Luau: the numbers that make a place feel like it has air.
--
-- Fields.look already owns the lighting that the game logic cares about
-- (ambient, fog, brightness). This module adds the effects that are pure
-- presentation: haze, clouds, glow and colour grading. They are kept apart
-- because a test can check a fog distance as a gameplay number, while bloom
-- intensity is only ever a look.
--
-- Roblox has exactly one Lighting service and one Atmosphere, so these follow
-- the player: entering a field re-grades the world for that field, the same
-- way applyLook already re-lights it.

local Atmosphere = {}

export type Profile = {
    -- Haze. Density is how thick the air is; Offset lifts the haze band off
    -- the ground so the player is not walking in soup.
    density: number,
    offset: number,
    -- Haze colour, and how fast it fades with distance.
    color: { number },
    decay: { number },
    glare: number,
    haze: number,
    -- Cloud layer. Cover 0..1, density is thickness, colour is its tint.
    cloudCover: number,
    cloudDensity: number,
    cloudColor: { number },
    -- Glow. Threshold is the brightness a pixel needs before it blooms, so a
    -- low threshold makes the whole map glow and a high one only catches the
    -- neon parts.
    bloomIntensity: number,
    bloomSize: number,
    bloomThreshold: number,
    -- Colour grade. Brightness and contrast are multipliers around 1.
    brightness: number,
    contrast: number,
    saturation: number,
    tint: { number },
    -- Sun rays, for the places with a sun worth looking at.
    sunRays: number,
    -- Ambient wind the client applies to foliage and motes, in studs per
    -- second. Purely a reading of the map's mood.
    wind: number,
}

local PROFILES: { [string]: Profile } = {
    Town = {
        density = 0.32,
        offset = 6,
        color = { 214, 220, 232 },
        decay = { 40, 60, 90 },
        glare = 0.15,
        haze = 1.2,
        cloudCover = 0.5,
        cloudDensity = 0.6,
        cloudColor = { 255, 252, 244 },
        bloomIntensity = 0.4,
        bloomSize = 22,
        bloomThreshold = 1.1,
        brightness = 1.02,
        contrast = 1.03,
        saturation = 1.05,
        tint = { 255, 248, 236 },
        sunRays = 0.06,
        wind = 0.6,
    },
    Meadow = {
        density = 0.38,
        offset = 8,
        color = { 200, 226, 198 },
        decay = { 70, 120, 80 },
        glare = 0.2,
        haze = 1.6,
        cloudCover = 0.55,
        cloudDensity = 0.7,
        cloudColor = { 250, 255, 246 },
        bloomIntensity = 0.55,
        bloomSize = 26,
        bloomThreshold = 1.0,
        brightness = 1.04,
        contrast = 1.04,
        saturation = 1.12,
        tint = { 244, 255, 240 },
        sunRays = 0.12,
        wind = 1.4,
    },
    Cavern = {
        density = 0.55,
        offset = 2,
        color = { 96, 108, 146 },
        decay = { 60, 70, 110 },
        glare = 0.05,
        haze = 0.8,
        cloudCover = 0.7,
        cloudDensity = 0.9,
        cloudColor = { 150, 164, 200 },
        bloomIntensity = 0.75,
        bloomSize = 30,
        bloomThreshold = 0.75,
        brightness = 0.95,
        contrast = 1.1,
        saturation = 0.95,
        tint = { 214, 224, 255 },
        sunRays = 0,
        wind = 0.3,
    },
    Volcano = {
        density = 0.6,
        offset = 4,
        color = { 128, 74, 58 },
        decay = { 90, 50, 40 },
        glare = 0.08,
        haze = 1.0,
        cloudCover = 0.8,
        cloudDensity = 1.0,
        cloudColor = { 96, 68, 62 },
        bloomIntensity = 1.0,
        bloomSize = 34,
        bloomThreshold = 0.7,
        brightness = 0.98,
        contrast = 1.14,
        saturation = 1.16,
        tint = { 255, 208, 180 },
        sunRays = 0.03,
        wind = 0.9,
    },
    Void = {
        density = 0.5,
        offset = 10,
        color = { 92, 78, 140 },
        decay = { 70, 55, 120 },
        glare = 0.25,
        haze = 1.8,
        cloudCover = 0.65,
        cloudDensity = 0.85,
        cloudColor = { 120, 104, 170 },
        bloomIntensity = 1.2,
        bloomSize = 38,
        bloomThreshold = 0.6,
        brightness = 0.92,
        contrast = 1.18,
        saturation = 1.2,
        tint = { 208, 190, 255 },
        sunRays = 0,
        wind = 1.1,
    },
    Heaven = {
        density = 0.24,
        offset = 20,
        color = { 244, 246, 255 },
        decay = { 90, 100, 140 },
        glare = 0.4,
        haze = 2.2,
        cloudCover = 0.35,
        cloudDensity = 0.45,
        cloudColor = { 255, 255, 255 },
        bloomIntensity = 1.35,
        bloomSize = 44,
        bloomThreshold = 0.55,
        brightness = 1.08,
        contrast = 1.02,
        saturation = 1.05,
        tint = { 255, 250, 226 },
        sunRays = 0.25,
        wind = 1.8,
    },
}

-- The profile for a place, falling back to the town's so an unknown id is
-- still lit rather than black.
function Atmosphere.profileFor(placeId: string?): Profile
    return PROFILES[placeId or "Town"] or PROFILES.Town
end

function Atmosphere.placeIds(): { string }
    local out: { string } = {}
    for id in pairs(PROFILES) do
        table.insert(out, id)
    end
    table.sort(out)
    return out
end

-- Whether this place is dim enough that its motes should read as the main
-- light source. Used to pick the mote brightness.
function Atmosphere.isDim(placeId: string?): boolean
    local profile = Atmosphere.profileFor(placeId)
    return profile.brightness < 1.0 or profile.bloomThreshold < 0.8
end

return Atmosphere

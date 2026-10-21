--!strict
-- Zone progression. Pure Luau.
--
-- Zones are the visible "I got further" signal: each one unlocks at a level,
-- pays better, and spawns tougher enemies. They also give the shop something
-- to sell (early access to a zone the player has not reached yet).

local Config = require("./Config")

local Zones = {}

export type ZoneDef = {
	id: string,
	name: string,
	levelRequirement: number,
	-- Multiplies coin rewards and enemy strength in this zone.
	coinMultiplier: number,
	difficultyMultiplier: number,
	-- Whether a monster here can kill a player. The first field is where a new
	-- character grinds forever, so it is deliberately non-lethal: damage there
	-- stops at 1 HP. Every later field is lethal, and each one hits harder than
	-- the last.
	lethal: boolean,
	-- Order shown in the UI.
	index: number,
}

local DEFS: { [string]: ZoneDef } = {
	Meadow = {
		id = "Meadow",
		name = "Sunny Meadow",
		levelRequirement = 1,
		coinMultiplier = 1.0,
		difficultyMultiplier = 1.0,
		lethal = false,
		index = 1,
	},
	Cavern = {
		id = "Cavern",
		name = "Crystal Cavern",
		levelRequirement = 10,
		coinMultiplier = 1.8,
		difficultyMultiplier = 1.5,
		lethal = true,
		index = 2,
	},
	Volcano = {
		id = "Volcano",
		name = "Ember Volcano",
		levelRequirement = 25,
		coinMultiplier = 3.2,
		difficultyMultiplier = 2.4,
		lethal = true,
		index = 3,
	},
	Void = {
		id = "Void",
		name = "Void Rift",
		levelRequirement = 50,
		coinMultiplier = 6.0,
		difficultyMultiplier = 4.0,
		lethal = true,
		index = 4,
	},
	Heaven = {
		id = "Heaven",
		name = "Celestial Gate",
		levelRequirement = 80,
		coinMultiplier = 12.0,
		difficultyMultiplier = 7.0,
		lethal = true,
		index = 5,
	},
}

local ORDER = { "Meadow", "Cavern", "Volcano", "Void", "Heaven" }

function Zones.getDef(zoneId: string): ZoneDef?
	return DEFS[zoneId]
end

function Zones.list(): { ZoneDef }
	local out: { ZoneDef } = {}
	for _, id in ipairs(ORDER) do
		table.insert(out, DEFS[id])
	end
	return out
end

function Zones.defaultZone(): string
	local id = Config.Zones.Default
	if DEFS[id] then
		return id
	end
	return ORDER[1]
end

function Zones.isUnlocked(zoneId: string, level: number, ownedPass: boolean?): boolean
	local def = DEFS[zoneId]
	if not def then
		return false
	end
	-- A purchased zone pass bypasses the level gate.
	if ownedPass then
		return true
	end
	return level >= def.levelRequirement
end

-- Resolve a travel request. Returns (zoneId, reason) - zoneId is nil on denial.
function Zones.resolveTravel(zoneId: string, level: number, ownedPass: boolean?): (string?, string?)
	local def = DEFS[zoneId]
	if not def then
		return nil, "UNKNOWN_ZONE"
	end
	if not Zones.isUnlocked(zoneId, level, ownedPass) then
		return nil, "ZONE_LOCKED"
	end
	return zoneId, nil
end

-- Coin multiplier for the zone, used on top of pets, level and rebirth.
function Zones.coinMultiplier(zoneId: string): number
	local def = DEFS[zoneId]
	return def and def.coinMultiplier or 1
end

function Zones.difficultyMultiplier(zoneId: string): number
	local def = DEFS[zoneId]
	return def and def.difficultyMultiplier or 1
end

-- Whether monsters in this zone are allowed to kill the player. An unknown
-- zone is treated as lethal, so a typo can never make the whole game safe.
function Zones.isLethal(zoneId: string): boolean
	local def = DEFS[zoneId]
	if not def then
		return true
	end
	return def.lethal
end

return Zones

--!strict
-- Save data schema with validation and forward migration.
-- Pure Luau so it can be exercised by tests without DataStore.

local Config = require("./Config")
local Stats = require("./Stats")
local Inventory = require("./Inventory")
local Attributes = require("./Attributes")
local Classes = require("./Classes")
local Skills = require("./Skills")
local Items = require("./Items")
local Pets = require("./Pets")
local Rebirth = require("./Rebirth")
local Zones = require("./Zones")
local Monetization = require("./Monetization")
local DailyRewards = require("./DailyRewards")
local Codes = require("./Codes")

local SaveSchema = {}

export type SaveData = {
	version: number,
	coins: number,
	upgrades: { [string]: number },
	inventory: { { itemId: string, count: number } },
	-- Character build (schema v5): the stat sheet, the class, the skills
	-- learned and what is being worn.
	attributes: { [string]: number },
	attributePoints: number,
	class: string,
	jobLevel: number,
	jobXp: number,
	skillPoints: number,
	skills: { [string]: number },
	equipment: { [string]: string? },
	stats: { kills: number, wavesCleared: number, deaths: number },
	level: number,
	xp: number,
	rebirths: number,
	zone: string,
	pets: any,
	entitlements: any,
	daily: any,
	redeemed: any,
	updatedAt: number,
}

local CURRENT = Config.Persistence.SchemaVersion
local MIN_SUPPORTED = Config.Persistence.MinSupportedVersion

function SaveSchema.new(): SaveData
	return {
		version = CURRENT,
		coins = Config.Economy.StartingCoins,
		upgrades = Stats.newUpgrades(),
		inventory = {},
		attributes = Attributes.new(),
		attributePoints = 0,
		class = Config.Classes.StartingClass,
		jobLevel = 1,
		jobXp = 0,
		skillPoints = 0,
		skills = { BasicAttack = 1 },
		equipment = {},
		stats = { kills = 0, wavesCleared = 0, deaths = 0 },
		level = 1,
		xp = 0,
		rebirths = 0,
		zone = Zones.defaultZone(),
		pets = Pets.snapshot(Pets.new()),
		entitlements = Monetization.newEntitlements(),
		daily = DailyRewards.new(),
		redeemed = {},
		updatedAt = 0,
	}
end

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Structural validation. Returns ok plus a list of problems.
function SaveSchema.validate(data: any): (boolean, { string })
	local problems: { string } = {}

	if type(data) ~= "table" then
		return false, { "ROOT_NOT_TABLE" }
	end

	if not isFiniteNumber(data.version) then
		table.insert(problems, "MISSING_VERSION")
	elseif data.version < MIN_SUPPORTED then
		table.insert(problems, "UNSUPPORTED_VERSION")
	elseif data.version > CURRENT then
		table.insert(problems, "FUTURE_VERSION")
	end

	if not isFiniteNumber(data.coins) or data.coins < 0 then
		table.insert(problems, "INVALID_COINS")
	elseif data.coins > Config.Economy.MaxCoins then
		table.insert(problems, "COINS_OVERFLOW")
	end

	if type(data.upgrades) ~= "table" then
		table.insert(problems, "MISSING_UPGRADES")
	else
		for id, def in pairs(Config.Upgrades) do
			local level = data.upgrades[id]
			if level == nil then
				table.insert(problems, "MISSING_UPGRADE:" .. id)
			elseif not isFiniteNumber(level) or level < 0 or level > def.MaxLevel then
				table.insert(problems, "INVALID_UPGRADE:" .. id)
			end
		end
	end

	if type(data.inventory) ~= "table" then
		table.insert(problems, "MISSING_INVENTORY")
	elseif #data.inventory > Config.Inventory.MaxCapacity then
		table.insert(problems, "INVENTORY_OVER_CAPACITY")
	else
		for index, slot in ipairs(data.inventory) do
			if type(slot) ~= "table" then
				table.insert(problems, "INVALID_SLOT:" .. tostring(index))
			elseif Inventory.getItemDef(slot.itemId) == nil then
				table.insert(problems, "UNKNOWN_ITEM:" .. tostring(slot.itemId))
			elseif not isFiniteNumber(slot.count) or slot.count <= 0 then
				table.insert(problems, "INVALID_COUNT:" .. tostring(index))
			end
		end
	end

	if type(data.stats) ~= "table" then
		table.insert(problems, "MISSING_STATS")
	else
		for _, key in ipairs({ "kills", "wavesCleared", "deaths" }) do
			local v = data.stats[key]
			if not isFiniteNumber(v) or v < 0 then
				table.insert(problems, "INVALID_STAT:" .. key)
			end
		end
	end

	-- Progression fields (schema v3). Absent on older saves, which migrate.
	if data.level ~= nil then
		if not isFiniteNumber(data.level) or data.level < 1 or data.level > Config.Leveling.MaxLevel then
			table.insert(problems, "INVALID_LEVEL")
		end
	end
	if data.xp ~= nil then
		if not isFiniteNumber(data.xp) or data.xp < 0 then
			table.insert(problems, "INVALID_XP")
		end
	end
	if data.rebirths ~= nil then
		if not isFiniteNumber(data.rebirths) or data.rebirths < 0 or data.rebirths > Config.Rebirth.MaxRebirths then
			table.insert(problems, "INVALID_REBIRTHS")
		end
	end
	if data.zone ~= nil then
		if type(data.zone) ~= "string" or Zones.getDef(data.zone) == nil then
			table.insert(problems, "INVALID_ZONE")
		end
	end
	if data.pets ~= nil then
		if type(data.pets) ~= "table" then
			table.insert(problems, "INVALID_PETS")
		elseif #(data.pets.pets or {}) > Config.Pets.MaxInventory then
			table.insert(problems, "PET_INVENTORY_OVER_CAPACITY")
		end
	end
	if data.entitlements ~= nil and type(data.entitlements) ~= "table" then
		table.insert(problems, "INVALID_ENTITLEMENTS")
	end

	-- Character build (schema v5). Absent on older saves, which migrate.
	if data.attributes ~= nil then
		if type(data.attributes) ~= "table" then
			table.insert(problems, "INVALID_ATTRIBUTES")
		else
			for _, name in ipairs(Attributes.NAMES) do
				local value = data.attributes[name]
				if value == nil then
					table.insert(problems, "MISSING_ATTRIBUTE:" .. name)
				elseif not isFiniteNumber(value) or value < Config.Attributes.BaseValue
					or value > Config.Attributes.MaxValue then
					table.insert(problems, "INVALID_ATTRIBUTE:" .. name)
				end
			end
		end
	end
	if data.attributePoints ~= nil then
		if not isFiniteNumber(data.attributePoints) or data.attributePoints < 0 then
			table.insert(problems, "INVALID_ATTRIBUTE_POINTS")
		end
	end
	if data.class ~= nil then
		if type(data.class) ~= "string" or Classes.getDef(data.class) == nil then
			table.insert(problems, "INVALID_CLASS")
		end
	end
	if data.jobLevel ~= nil then
		if not isFiniteNumber(data.jobLevel) or data.jobLevel < 1
			or data.jobLevel > Config.Classes.MaxJobLevel then
			table.insert(problems, "INVALID_JOB_LEVEL")
		end
	end
	if data.jobXp ~= nil then
		if not isFiniteNumber(data.jobXp) or data.jobXp < 0 then
			table.insert(problems, "INVALID_JOB_XP")
		end
	end
	if data.skillPoints ~= nil then
		if not isFiniteNumber(data.skillPoints) or data.skillPoints < 0 then
			table.insert(problems, "INVALID_SKILL_POINTS")
		end
	end
	if data.skills ~= nil then
		if type(data.skills) ~= "table" then
			table.insert(problems, "INVALID_SKILLS")
		else
			for skillId, level in pairs(data.skills) do
				local def = Skills.getDef(skillId)
				if def == nil then
					table.insert(problems, "UNKNOWN_SKILL:" .. tostring(skillId))
				elseif not isFiniteNumber(level) or level < 0 or level > def.maxLevel then
					table.insert(problems, "INVALID_SKILL_LEVEL:" .. tostring(skillId))
				end
			end
		end
	end
	if data.equipment ~= nil then
		if type(data.equipment) ~= "table" then
			table.insert(problems, "INVALID_EQUIPMENT")
		else
			for slot, itemId in pairs(data.equipment) do
				if itemId ~= nil then
					local def = Items.getDef(itemId)
					if def == nil or def.kind ~= "equipment" then
						table.insert(problems, "UNKNOWN_EQUIPMENT:" .. tostring(itemId))
					elseif def.slot ~= slot and not (def.twoHanded and slot == "Shield") then
						table.insert(problems, "EQUIPMENT_WRONG_SLOT:" .. tostring(itemId))
					end
				end
			end
		end
	end

	-- Daily streak and redeemed codes (schema v4).
	if data.daily ~= nil then
		if type(data.daily) ~= "table" then
			table.insert(problems, "INVALID_DAILY")
		else
			local streak = data.daily.streak
			if streak ~= nil and (not isFiniteNumber(streak) or streak < 0
				or streak > Config.Daily.MaxStreak) then
				table.insert(problems, "INVALID_DAILY_STREAK")
			end
			local lastClaimAt = data.daily.lastClaimAt
			if lastClaimAt ~= nil and (not isFiniteNumber(lastClaimAt) or lastClaimAt < 0) then
				table.insert(problems, "INVALID_DAILY_CLAIM_TIME")
			end
		end
	end
	if data.redeemed ~= nil and type(data.redeemed) ~= "table" then
		table.insert(problems, "INVALID_REDEEMED")
	end

	return #problems == 0, problems
end

-- Bring older saves up to the current schema. Returns nil when impossible.
function SaveSchema.migrate(data: any): SaveData?
	if type(data) ~= "table" then
		return nil
	end
	local version = isFiniteNumber(data.version) and data.version or MIN_SUPPORTED
	if version < MIN_SUPPORTED or version > CURRENT then
		return nil
	end

	local fresh = SaveSchema.new()
	-- Carry legacy values forward, clamped to the current legal ranges.
	local upgrades: { [string]: number } = {}
	for _, id in ipairs(Config.UpgradeOrder) do
		local def = Config.Upgrades[id]
		local level = (type(data.upgrades) == "table" and data.upgrades[id]) or 0
		if not isFiniteNumber(level) or level < 0 then
			level = 0
		end
		upgrades[id] = math.min(math.floor(level), def.MaxLevel)
	end

	-- Older saves predate progression; fall back to fresh defaults so a
	-- returning player starts the new systems cleanly instead of erroring.
	local level = math.clamp(math.floor(tonumber(data.level) or 1), 1, Config.Leveling.MaxLevel)
	local rebirths = math.clamp(math.floor(tonumber(data.rebirths) or 0), 0, Config.Rebirth.MaxRebirths)

	-- Character build. An older save has no stat sheet, so it gets the fresh
	-- one; its banked points are the points it earned by its current level, so a
	-- returning player is not punished for having played before this existed.
	local attributes = Attributes.new()
	if type(data.attributes) == "table" then
		for _, name in ipairs(Attributes.NAMES) do
			local value = data.attributes[name]
			if isFiniteNumber(value) then
				attributes[name] = math.clamp(math.floor(value),
					Config.Attributes.BaseValue, Config.Attributes.MaxValue)
			end
		end
	end
	local attributePoints = isFiniteNumber(data.attributePoints)
		and math.max(0, math.floor(data.attributePoints))
		or Attributes.available(attributes, level)

	local class = (type(data.class) == "string" and Classes.getDef(data.class)) and data.class
		or Config.Classes.StartingClass
	local jobLevel = math.clamp(math.floor(tonumber(data.jobLevel) or 1), 1, Config.Classes.MaxJobLevel)
	local jobXp = isFiniteNumber(data.jobXp) and math.max(0, data.jobXp) or 0

	-- Skills: drop anything the catalogue no longer knows, clamp the rest.
	local skills: { [string]: number } = {}
	if type(data.skills) == "table" then
		for skillId, level in pairs(data.skills) do
			local def = Skills.getDef(skillId)
			if def and isFiniteNumber(level) and level > 0 then
				skills[skillId] = math.min(math.floor(level), def.maxLevel)
			end
		end
	end
	if not skills.BasicAttack then
		skills.BasicAttack = 1
	end
	-- A point is spent per skill level, so the unspent count is derived rather
	-- than stored, which keeps a hand-edited save from minting free points.
	local spentPoints = 0
	for _, level in pairs(skills) do
		spentPoints += level
	end
	local earnedPoints = Classes.skillPointsForJobLevel(jobLevel)
	local skillPoints = math.max(0, earnedPoints - spentPoints)

	-- Equipment: keep only what still exists and still fits its slot.
	local equipment: { [string]: string? } = {}
	if type(data.equipment) == "table" then
		for slot, itemId in pairs(data.equipment) do
			local def = type(itemId) == "string" and Items.getDef(itemId) or nil
			if def and def.kind == "equipment" and (def.slot == slot or (def.twoHanded and slot == "Shield")) then
				equipment[slot] = itemId
			end
		end
	end

	local migrated: SaveData = {
		version = CURRENT,
		coins = isFiniteNumber(data.coins) and math.max(0, data.coins) or fresh.coins,
		upgrades = upgrades,
		inventory = data.inventory or {},
		attributes = attributes,
		attributePoints = attributePoints,
		class = class,
		jobLevel = jobLevel,
		jobXp = jobXp,
		skillPoints = skillPoints,
		skills = skills,
		equipment = equipment,
		stats = data.stats or fresh.stats,
		level = level,
		xp = isFiniteNumber(data.xp) and math.max(0, data.xp) or 0,
		rebirths = rebirths,
		zone = (Zones.getDef(data.zone) and data.zone) or Zones.defaultZone(),
		pets = Pets.snapshot(Pets.fromSnapshot(data.pets)),
		entitlements = Monetization.fromSnapshot(data.entitlements),
		daily = DailyRewards.fromSnapshot(data.daily),
		redeemed = Codes.fromSnapshot(data.redeemed),
		updatedAt = isFiniteNumber(data.updatedAt) and data.updatedAt or 0,
	}

	return migrated
end

-- Validate, then migrate. Returns nil plus reasons when the save is unusable.
function SaveSchema.load(data: any): (SaveData?, { string })
	local migrated = SaveSchema.migrate(data)
	if not migrated then
		return nil, { "MIGRATION_FAILED" }
	end
	local ok, problems = SaveSchema.validate(migrated)
	if not ok then
		return nil, problems
	end
	return migrated, {}
end

-- Emit deterministic JSON. Fixed key ordering keeps stored blobs diff-friendly.
function SaveSchema.serialize(data: SaveData, now: number): string
	return string.format(
		'{"version":%d,"coins":%d,"upgrades":%s,"inventory":%s,"attributes":%s,"attributePoints":%d,"class":"%s","jobLevel":%d,"jobXp":%d,"skills":%s,"equipment":%s,"stats":%s,"level":%d,"xp":%d,"rebirths":%d,"zone":"%s","daily":%s,"redeemed":%s,"updatedAt":%d}',
		CURRENT,
		math.floor(data.coins),
		SaveSchema.encodeUpgrades(data.upgrades),
		SaveSchema.encodeInventory(data.inventory),
		SaveSchema.encodeAttributes(data.attributes),
		math.floor(data.attributePoints or 0),
		data.class or Config.Classes.StartingClass,
		math.floor(data.jobLevel or 1),
		math.floor(data.jobXp or 0),
		SaveSchema.encodeSkills(data.skills),
		SaveSchema.encodeEquipment(data.equipment),
		SaveSchema.encodeStats(data.stats),
		math.floor(data.level or 1),
		math.floor(data.xp or 0),
		math.floor(data.rebirths or 0),
		data.zone or Zones.defaultZone(),
		SaveSchema.encodeDaily(data.daily),
		SaveSchema.encodeRedeemed(data.redeemed),
		math.floor(now)
	)
end

function SaveSchema.encodeUpgrades(upgrades: { [string]: number }): string
	local parts = {}
	for _, id in ipairs(Config.UpgradeOrder) do
		table.insert(parts, string.format('"%s":%d', id, upgrades[id] or 0))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function SaveSchema.encodeAttributes(attributes: { [string]: number }?): string
	local parts = {}
	for _, name in ipairs(Attributes.NAMES) do
		table.insert(parts, string.format('"%s":%d', name,
			math.floor((attributes or {})[name] or Config.Attributes.BaseValue)))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function SaveSchema.encodeSkills(skills: { [string]: number }?): string
	-- Sorted so the blob is stable between saves, which keeps a diff readable.
	local ids = {}
	for skillId, level in pairs(skills or {}) do
		if level and level > 0 then
			table.insert(ids, skillId)
		end
	end
	table.sort(ids)
	local parts = {}
	for _, skillId in ipairs(ids) do
		table.insert(parts, string.format('"%s":%d', skillId, math.floor(skills[skillId])))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function SaveSchema.encodeEquipment(equipment: { [string]: string? }?): string
	local parts = {}
	for _, slot in ipairs(Config.Equipment.Slots) do
		local itemId = (equipment or {})[slot]
		if itemId then
			table.insert(parts, string.format('"%s":"%s"', slot, itemId))
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function SaveSchema.encodeInventory(slots): string
	local parts = {}
	for _, slot in ipairs(slots or {}) do
		table.insert(parts, string.format('{"itemId":"%s","count":%d}', slot.itemId, slot.count))
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

function SaveSchema.encodeDaily(daily: any): string
	local d = DailyRewards.snapshot(daily or DailyRewards.new())
	return string.format(
		'{"streak":%d,"lastClaimAt":%d,"totalClaims":%d}',
		d.streak, d.lastClaimAt, d.totalClaims
	)
end

function SaveSchema.encodeRedeemed(redeemed: any): string
	local clean = Codes.snapshot(redeemed)
	local codes = {}
	for code, _ in pairs(clean) do
		table.insert(codes, code)
	end
	table.sort(codes)
	local parts = {}
	for _, code in ipairs(codes) do
		table.insert(parts, string.format('"%s":%d', code, clean[code].at))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function SaveSchema.encodeStats(stats): string
	return string.format(
		'{"kills":%d,"wavesCleared":%d,"deaths":%d}',
		stats.kills or 0,
		stats.wavesCleared or 0,
		stats.deaths or 0
	)
end

return SaveSchema

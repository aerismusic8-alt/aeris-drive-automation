--!strict
-- Save data schema with validation and forward migration.
-- Pure Luau so it can be exercised by tests without DataStore.

local Config = require("./Config")
local Stats = require("./Stats")
local Inventory = require("./Inventory")
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

	local migrated: SaveData = {
		version = CURRENT,
		coins = isFiniteNumber(data.coins) and math.max(0, data.coins) or fresh.coins,
		upgrades = upgrades,
		inventory = data.inventory or {},
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
		'{"version":%d,"coins":%d,"upgrades":%s,"inventory":%s,"stats":%s,"level":%d,"xp":%d,"rebirths":%d,"zone":"%s","daily":%s,"redeemed":%s,"updatedAt":%d}',
		CURRENT,
		math.floor(data.coins),
		SaveSchema.encodeUpgrades(data.upgrades),
		SaveSchema.encodeInventory(data.inventory),
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

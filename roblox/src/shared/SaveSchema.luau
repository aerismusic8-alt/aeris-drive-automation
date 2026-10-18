--!strict
-- Save data schema with validation and forward migration.
-- Pure Luau so it can be exercised by tests without DataStore.

local Config = require("./Config")
local Stats = require("./Stats")
local Inventory = require("./Inventory")

local SaveSchema = {}

export type SaveData = {
	version: number,
	coins: number,
	upgrades: { [string]: number },
	inventory: { { itemId: string, count: number } },
	stats: { kills: number, wavesCleared: number, deaths: number },
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

	local migrated: SaveData = {
		version = CURRENT,
		coins = isFiniteNumber(data.coins) and math.max(0, data.coins) or fresh.coins,
		upgrades = upgrades,
		inventory = data.inventory or {},
		stats = data.stats or fresh.stats,
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
		'{"version":%d,"coins":%d,"upgrades":%s,"inventory":%s,"stats":%s,"updatedAt":%d}',
		CURRENT,
		math.floor(data.coins),
		SaveSchema.encodeUpgrades(data.upgrades),
		SaveSchema.encodeInventory(data.inventory),
		SaveSchema.encodeStats(data.stats),
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

function SaveSchema.encodeStats(stats): string
	return string.format(
		'{"kills":%d,"wavesCleared":%d,"deaths":%d}',
		stats.kills or 0,
		stats.wavesCleared or 0,
		stats.deaths or 0
	)
end

return SaveSchema

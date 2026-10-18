--!strict
-- Player stat derivation and upgrade math.
-- Pure Luau: no Roblox globals, fully unit testable.

local Config = require("./Config")

local Stats = {}

export type Upgrades = { [string]: number }

export type DerivedStats = {
	maxHealth: number,
	walkSpeed: number,
	damage: number,
	critChance: number,
	critMultiplier: number,
}

-- Cost to buy the next level, given the current level (0-based).
function Stats.upgradeCost(upgradeId: string, currentLevel: number): number
	local def = Config.Upgrades[upgradeId]
	assert(def, "unknown upgrade: " .. tostring(upgradeId))
	if currentLevel < 0 then
		currentLevel = 0
	end
	if currentLevel >= def.MaxLevel then
		return math.huge
	end
	return math.floor(def.BaseCost * (def.Growth ^ currentLevel) + 0.5)
end

function Stats.canUpgrade(upgrades: Upgrades, upgradeId: string): (boolean, string?)
	local def = Config.Upgrades[upgradeId]
	if not def then
		return false, "UNKNOWN_UPGRADE"
	end
	local level = upgrades[upgradeId] or 0
	if level >= def.MaxLevel then
		return false, "MAX_LEVEL"
	end
	return true, nil
end

function Stats.newUpgrades(): Upgrades
	local upgrades: Upgrades = {}
	for _, id in ipairs(Config.UpgradeOrder) do
		upgrades[id] = 0
	end
	return upgrades
end

-- Returns true plus the new upgrades table, or false plus a reason.
function Stats.applyUpgrade(
	upgrades: Upgrades,
	upgradeId: string,
	coins: number
): (boolean, Upgrades | string, number?)
	local ok, reason = Stats.canUpgrade(upgrades, upgradeId)
	if not ok then
		return false, reason, nil
	end

	local level = upgrades[upgradeId] or 0
	local cost = Stats.upgradeCost(upgradeId, level)
	if coins < cost then
		return false, "INSUFFICIENT_COINS", nil
	end

	local nextUpgrades: Upgrades = {}
	for k, v in pairs(upgrades) do
		nextUpgrades[k] = v
	end
	nextUpgrades[upgradeId] = level + 1
	return true, nextUpgrades, coins - cost
end

-- Convert upgrade levels into concrete runtime stats, clamped to config caps.
function Stats.derive(upgrades: Upgrades): DerivedStats
	local cfg = Config.Player
	local health = cfg.BaseHealth
	local speed = cfg.BaseWalkSpeed
	local damage = cfg.BaseDamage
	local crit = cfg.BaseCritChance

	for _, id in ipairs(Config.UpgradeOrder) do
		local def = Config.Upgrades[id]
		local level = math.clamp(upgrades[id] or 0, 0, def.MaxLevel)
		local bonus = def.PerLevel * level
		if id == "Health" then
			health += bonus
		elseif id == "Speed" then
			speed += bonus
		elseif id == "Damage" then
			damage += bonus
		elseif id == "CritChance" then
			crit += bonus
		end
	end

	return {
		maxHealth = math.min(health, cfg.MaxHealth),
		walkSpeed = speed,
		damage = damage,
		critChance = math.min(crit, 1),
		critMultiplier = cfg.BaseCritMultiplier,
	}
end

-- Resolve a damage roll, applying crit chance deterministically via `rng`.
function Stats.rollDamage(stats: DerivedStats, rng): (number, boolean)
	local isCrit = rng:nextNumber() < stats.critChance
	local amount = stats.damage
	if isCrit then
		amount *= stats.critMultiplier
	end
	return amount, isCrit
end

return Stats

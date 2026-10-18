--!strict
-- AX Arena - shared game configuration.
-- Pure Luau: no Roblox globals so it can be unit tested outside Studio.

local Config = {}

Config.Version = "1.0.0"
Config.GameName = "AX Arena"

Config.Tick = {
	Rate = 30,
	MaxDeltaTime = 0.25,
}

Config.Wave = {
	BaseEnemyCount = 4,
	EnemiesPerWave = 2,
	MaxEnemiesPerWave = 40,
	BaseEnemyHealth = 100,
	HealthGrowth = 1.18,
	BaseEnemyDamage = 8,
	DamageGrowth = 1.09,
	BaseReward = 25,
	RewardGrowth = 1.08,
	IntermissionSeconds = 12,
	EnemyAttackInterval = 1.5,
}

Config.Player = {
	BaseHealth = 100,
	MaxHealth = 500,
	BaseWalkSpeed = 16,
	BaseDamage = 12,
	BaseCritChance = 0.05,
	BaseCritMultiplier = 2.0,
	RespawnDelay = 4,
}

-- Mobile-first combat: the player never has to tap to fight, so a session
-- works with one hand. Range is generous because the arena is small.
Config.Combat = {
        AttackRange = 30,
        AttackInterval = 0.8,
        AutoAttack = true,
}

Config.Economy = {
	StartingCoins = 150,
	MaxCoins = 1e9,
	KillBonusPerWave = 5,
}

Config.Inventory = {
	DefaultCapacity = 20,
	MaxCapacity = 100,
}

-- Upgrade definitions. `Growth` is the multiplicative cost curve per level.
Config.Upgrades = {
	Damage = { Id = "Damage", MaxLevel = 25, BaseCost = 100, Growth = 1.35, PerLevel = 4 },
	Health = { Id = "Health", MaxLevel = 25, BaseCost = 120, Growth = 1.32, PerLevel = 15 },
	Speed = { Id = "Speed", MaxLevel = 10, BaseCost = 150, Growth = 1.45, PerLevel = 1.5 },
	CritChance = { Id = "CritChance", MaxLevel = 10, BaseCost = 200, Growth = 1.5, PerLevel = 0.03 },
}

Config.Network = {
	-- Token bucket applied per player per remote.
	RemoteBurst = 12,
	RemoteRefillPerSecond = 6,
}

Config.Persistence = {
	SchemaVersion = 4,
	MinSupportedVersion = 1,
	SaveIntervalSeconds = 90,
}

-- Daily login rewards. The streak resets if a player misses more than the
-- grace window, which is what makes the daily habit stick.
Config.Daily = {
	CooldownSeconds = 20 * 60 * 60, -- 20h: forgiving, but still once a day
	StreakGraceSeconds = 48 * 60 * 60, -- 48h before the streak breaks
	MaxStreak = 365,
	CycleLength = 7,
	CycleGrowth = 1.25,
	-- Day 1..7 of each cycle. Later cycles scale by CycleGrowth.
	Rewards = {
		{ coins = 500, xp = 50, luckCharges = 0 },
		{ coins = 900, xp = 90, luckCharges = 0 },
		{ coins = 1400, xp = 140, luckCharges = 1 },
		{ coins = 2000, xp = 200, luckCharges = 0 },
		{ coins = 2800, xp = 280, luckCharges = 1 },
		{ coins = 4000, xp = 400, luckCharges = 1 },
		{ coins = 6000, xp = 600, luckCharges = 2 },
	},
}

Config.Codes = {
	MaxAttemptsPerMinute = 10,
}

-- Ordered list keeps iteration deterministic across server restarts.
Config.UpgradeOrder = { "Damage", "Health", "Speed", "CritChance" }

--------------------------------------------------------------------------
-- Progression: levels, pets, rebirths, zones.
-- These are what turn a wave shooter into a farm-and-grow game, which is the
-- loop that keeps a Roblox front page session long enough to trend.
--------------------------------------------------------------------------

Config.Leveling = {
	MaxLevel = 100,
	-- XP needed for the next level: BaseXp * Growth^(level-1).
	BaseXp = 50,
	XpGrowth = 1.15,
	-- XP granted per kill, scaled by the enemy's wave.
	BaseXpPerKill = 8,
	-- Growth must be at least 1 + 1/BaseXpPerKill, otherwise rounding to a
	-- whole number leaves the reward flat for several waves at a time.
	XpGrowthPerWave = 1.15,
	-- Each level adds a small permanent coin bonus.
	CoinBonusPerLevel = 0.01,
}

Config.Pets = {
	MaxEquipped = 4,
	MaxInventory = 200,
	-- A pet's coin/damage contribution is its rarity factor times power.
	RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
	RarityFactor = {
		Common = 1,
		Uncommon = 1.5,
		Rare = 2.5,
		Epic = 4,
		Legendary = 7,
		Mythic = 12,
	},
}

Config.Rebirth = {
	-- Level required for the first rebirth; grows each time.
	BaseLevelRequirement = 25,
	LevelGrowth = 1.35,
	MaxRebirths = 20,
	-- Permanent multipliers, additive per rebirth.
	CoinMultiplierPerRebirth = 0.5,
	DamageMultiplierPerRebirth = 0.25,
	-- Rebirth resets level, XP and coins but keeps pets and upgrades.
	ResetLevel = true,
	ResetCoins = true,
	ResetUpgrades = false,
	StartingCoinsAfterRebirth = 250,
}

Config.Zones = {
	Default = "Meadow",
	-- Switching zones costs nothing; unlocking is level gated.
	SwitchCooldownSeconds = 3,
}

Config.Monetization = {
	-- Robux catalogue. Prices live here so the server is the single
	-- source of truth and the client cannot invent a cheaper purchase.
	Enabled = true,
	-- Premium/VIP style perks are expressed as multipliers.
	VipCoinMultiplier = 2.0,
	VipXpMultiplier = 1.5,
	VipExtraPetSlots = 2,
}

Config.Codes = {
	-- Promo codes reward engagement (Roblox trending rewards active play).
	MaxRedemptionsPerPlayer = 1,
}

return Config

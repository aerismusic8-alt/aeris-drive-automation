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
	SchemaVersion = 2,
	MinSupportedVersion = 1,
	SaveIntervalSeconds = 90,
}

-- Ordered list keeps iteration deterministic across server restarts.
Config.UpgradeOrder = { "Damage", "Health", "Speed", "CritChance" }

return Config

--!strict
-- AX Arena - shared game configuration.
-- Pure Luau: no Roblox globals so it can be unit tested outside Studio.

local Config = {}

Config.Version = "1.0.1"
Config.GameName = "AX Arena"

Config.Tick = {
	Rate = 30,
	MaxDeltaTime = 0.25,
	-- HUD snapshots ride a slower clock than the simulation. A phone cannot
	-- absorb sixty events a second, and nothing on the screen changes that fast.
	BroadcastInterval = 1 / 10,
	FarmBroadcastInterval = 1,
}

Config.Wave = {
	-- Wave 1 is three monsters, not four: the first fight is where a new
	-- player learns the buttons, so it has to be survivable.
	BaseEnemyCount = 3,
	EnemiesPerWave = 2,
	MaxEnemiesPerWave = 40,
	BaseEnemyHealth = 70,
	HealthGrowth = 1.18,
	BaseEnemyDamage = 5,
	DamageGrowth = 1.09,
	BaseReward = 25,
	RewardGrowth = 1.08,
	IntermissionSeconds = 12,
	EnemyAttackInterval = 1.5,
	-- An enemy only lands a hit when it is close enough to touch the player.
	-- Without this gate every enemy on the map hits from any distance, which
	-- killed a new player before they could read the screen.
	EnemyMeleeRange = 9,
	-- Studs per second while chasing. Slower than a walking player, so running
	-- away is always an option.
	EnemyMoveSpeed = 13,
	-- Grace period after spawning, so an enemy cannot hit on arrival.
	SpawnGraceSeconds = 2.5,
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
	-- v5 adds the character build: attributes, class, job level, skills,
	-- equipment. v4 and older migrate forward with defaults.
	SchemaVersion = 5,
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
-- The Ragnarok layer: attributes, classes, skills, items and equipment.
-- This is what turns "walk up and auto-attack" into a character you build.
--------------------------------------------------------------------------

Config.Attributes = {
	-- Every stat starts here and can be raised to MaxValue. A point costs
	-- more every ten levels of that stat, so specialising is a trade-off.
	BaseValue = 1,
	MaxValue = 99,
	-- Stat points granted per level, plus one more every PointsPerLevelStep
	-- levels. Level 99 therefore banks far more than level 10 did.
	PointsPerLevelBase = 3,
	PointsPerLevelStep = 5,

	-- Attack: STR is the melee stat, DEX adds a little to everything.
	BaseAttack = 8,
	AttackPerStr = 2,
	AttackPerDex = 0.5,
	BaseMagicAttack = 6,
	MagicAttackPerInt = 2.2,

	-- Health and SP.
	BaseHealth = 60,
	HealthPerVit = 6,
	HealthPerLevel = 8,
	BaseSp = 20,
	SpPerInt = 4,
	SpPerLevel = 2,

	-- Defense and evasion.
	BaseDefense = 2,
	DefensePerVit = 0.8,
	BaseMagicDefense = 1,
	MagicDefensePerInt = 0.7,
	-- Defense reduces damage as defense/(defense+cap): never immunity.
	DefenseSoftCap = 60,

	-- Accuracy and dodging. Both grow with level, so level matters even
	-- with the points banked.
	BaseHit = 10,
	HitPerDex = 1.2,
	BaseFlee = 5,
	FleePerAgi = 1.4,
	-- Chance to hit = base + (hit - flee) * perPoint, clamped.
	HitBaseChance = 0.75,
	HitChancePerPoint = 0.01,
	MinHitChance = 0.35,
	MaxHitChance = 0.98,

	-- Crits come from LUK.
	BaseCrit = 0.02,
	CritPerLuk = 0.003,
	MaxCrit = 0.5,
	CritMultiplier = 1.8,

	-- Attack speed. AGI shortens the interval; DEX helps a little.
	BaseAttackInterval = 1.1,
	AgilityPerAgi = 0.006,
	AgilityPerDex = 0.002,
	MinAttackInterval = 0.35,

	-- Stats the player may assign points to. Everything else is derived.
	Raisable = { STR = true, AGI = true, VIT = true, INT = true, DEX = true, LUK = true },
}

Config.Classes = {
	-- Novice is the starting class and cannot be chosen; the five first
	-- jobs are the branches, and each has one second job.
	StartingClass = "Novice",
	-- Job level is earned alongside base level and is what buys skills.
	MaxJobLevel = 50,
	-- A first job needs this base level; the second job needs more.
	FirstJobLevel = 10,
	SecondJobLevel = 30,
	-- Job level needed to advance, so a player cannot rush the branch.
	FirstJobJobLevel = 10,
	SecondJobJobLevel = 30,
	-- Job levels needed per job level gained, at base level 1.
	JobXpBase = 30,
	JobXpGrowth = 1.12,
	-- Job XP granted per point of base XP from a kill. Below 1 so the job
	-- track is slower than the base track, which is what makes a second job
	-- feel earned rather than automatic.
	JobXpPerBaseXp = 0.6,
	-- One skill point per job level.
	SkillPointsPerJobLevel = 1,
	-- Class bonuses are flat attribute additions, applied on top of the
	-- points the player assigned.
	RespecCostCoins = 5000,
}

Config.Skills = {
	-- SP regeneration: this much per second, plus a slice of max SP.
	SpRegenPerSecond = 2,
	SpRegenPercent = 0.02,
	-- A skill cannot be cast more often than this, whatever the skill says.
	MinGlobalCooldown = 0.3,
}

Config.Items = {
	-- Backpack slots. Equipment does not consume a slot.
	DefaultCapacity = 30,
	MaxCapacity = 200,
	-- How close a player must stand to pick a dropped item up.
	PickupRange = 14,
	-- A drop that nobody collects disappears, so a long session does not
	-- fill the world with parts.
	DropLifetimeSeconds = 90,
	-- Auto-pickup collects anything this close, which is what makes the
	-- auto mode feel automatic rather than approximate.
	AutoPickupRange = 18,
}

Config.Equipment = {
	-- One item per slot. Order is the order the panel shows them in.
	Slots = { "Weapon", "Shield", "Head", "Body", "Garment", "Shoes", "Accessory1", "Accessory2" },
	-- A two-handed weapon occupies both the weapon and the shield slot.
	TwoHandedSlots = { "Weapon", "Shield" },
}

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

--------------------------------------------------------------------------
-- The world: a safe town hub and five monster fields, the shape a classic
-- Korean MMO is built on. The town is where you shop, hatch and respawn;
-- each field is its own map with its own monsters, boss and reward tier.
--------------------------------------------------------------------------

Config.Town = {
	-- The town is safe. No enemy spawns there and no field monster reaches it.
	Safe = true,
	Radius = 70,
	-- Where a player lands when they return from a field.
	ArrivalOffsetZ = 40,
	GroundColor = { 168, 148, 116 },
}

Config.Fields = {
	-- Fields sit on a ring around the town, so the world reads as a place you
	-- travel across rather than a list you click. Distance is in studs.
	RingRadius = 520,
	ArenaRadius = 110,
	-- Monsters spawn inside this radius of the field centre and never on the
	-- arrival point, so walking in is not immediately a fight.
	SpawnRadius = 85,
	PortalRadius = 12,
	-- Protection after entering a field. Without it, arriving at a high level
	-- field is a death sentence before the map has finished drawing.
	ArrivalGraceSeconds = 4,
}

Config.Enemies = {
	-- Archetypes multiply the wave base. A boss is one big spawn that closes
	-- the field out with a reward spike worth staying for.
	BossHealthMul = 12,
	BossDamageMul = 1.6,
	BossRewardMul = 20,
	BossSizeMul = 2.6,
	BossXpMul = 8,
	-- A wave mixes at most this many monster types, so it still reads as a
	-- wave rather than noise.
	MaxTypesPerWave = 2,
	-- Every fifth wave in a field is a boss wave.
	BossEveryWaves = 5,
}

-- Kill streak: rewards not stopping. A player who keeps killing in
-- quick succession earns a rising coin bonus that resets when they pause.
Config.Streak = {
	WindowSeconds = 8,
	BonusPerKill = 0.02,
	MaxBonus = 1.0,
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

--------------------------------------------------------------------------
-- The farm loop: plant, wait, harvest. This is the "farm" half of farm and
-- fight, and it is what gives a session a reason to stay longer than one wave.
--------------------------------------------------------------------------

Config.Farm = {
	-- Plots sit in a ring around the spawn, so farming happens inside the fight
	-- rather than in a menu.
	PlotCount = 6,
	PlotRingRadius = 26,
	-- Crops differ in patience and payout, which gives the player a choice.
	Crops = {
		{ id = "Wheat", growSeconds = 8, coins = 60, xp = 10, color = { 236, 200, 96 } },
		{ id = "Carrot", growSeconds = 18, coins = 190, xp = 26, color = { 240, 140, 70 } },
		{ id = "Star", growSeconds = 34, coins = 520, xp = 70, color = { 150, 220, 255 } },
	},
	-- Harvesting charges the axe. A full swing spends every charge at once.
	AxeChargePerHarvest = 1,
	AxeMaxCharges = 5,
	-- Each charge multiplies the next axe hit, and the hit strikes everything
	-- close to the player.
	AxeDamagePerCharge = 6,
	AxeRadius = 26,
}


return Config

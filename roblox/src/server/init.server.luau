--!strict
-- Server entry point: owns the authoritative game loop.
--
-- Every number that matters (health, coins, XP, pets, zones, purchases) lives
-- here. The client only renders and sends intent, which is validated against
-- the pure modules in src/shared.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ClassLook = require(Shared:WaitForChild("ClassLook"))
local Random = require(Shared.Random)
local Stats = require(Shared.Stats)
local Combat = require(Shared.Combat)
local WaveDirector = require(Shared.WaveDirector)
local SaveSchema = require(Shared.SaveSchema)
local RateLimiter = require(Shared.RateLimiter)
local Leveling = require(Shared.Leveling)
local Pets = require(Shared.Pets)
local Rebirth = require(Shared.Rebirth)
local Zones = require(Shared.Zones)
local Monetization = require(Shared.Monetization)
local DailyRewards = require(Shared.DailyRewards)
local World = require(script.World)
local Codes = require(Shared.Codes)
local Farm = require(Shared.Farm)
local Axe = require(Shared.Axe)
local Fields = require(Shared.Fields)
local Enemies = require(Shared.Enemies)
local Attributes = require(Shared.Attributes)
local Classes = require(Shared.Classes)
local Skills = require(Shared.Skills)
local Items = require(Shared.Items)
local Inventory = require(Shared.Inventory)
local Text = require(Shared.Text)

-- Remotes are created here so the client can rely on WaitForChild alone.
local function ensureRemote(container: Instance, className: "RemoteEvent" | "RemoteFunction", name: string): Instance
	local existing = container:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = container
	return remote
end

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local RequestUpgrade = ensureRemote(Remotes, "RemoteFunction", "RequestUpgrade") :: RemoteFunction
local RequestShop = ensureRemote(Remotes, "RemoteFunction", "RequestShop") :: RemoteFunction
local HatchEgg = ensureRemote(Remotes, "RemoteFunction", "HatchEgg") :: RemoteFunction
local EquipPet = ensureRemote(Remotes, "RemoteFunction", "EquipPet") :: RemoteFunction
local UnequipPet = ensureRemote(Remotes, "RemoteFunction", "UnequipPet") :: RemoteFunction
local DoRebirth = ensureRemote(Remotes, "RemoteFunction", "Rebirth") :: RemoteFunction
local TravelZone = ensureRemote(Remotes, "RemoteFunction", "TravelZone") :: RemoteFunction
local ClaimDaily = ensureRemote(Remotes, "RemoteFunction", "ClaimDaily") :: RemoteFunction
local RedeemCode = ensureRemote(Remotes, "RemoteFunction", "RedeemCode") :: RemoteFunction
local PlantCrop = ensureRemote(Remotes, "RemoteFunction", "PlantCrop") :: RemoteFunction
local HarvestCrop = ensureRemote(Remotes, "RemoteFunction", "HarvestCrop") :: RemoteFunction
local UseAxe = ensureRemote(Remotes, "RemoteFunction", "UseAxe") :: RemoteFunction
local RaiseAttribute = ensureRemote(Remotes, "RemoteFunction", "RaiseAttribute") :: RemoteFunction
local LearnSkill = ensureRemote(Remotes, "RemoteFunction", "LearnSkill") :: RemoteFunction
local AdvanceJob = ensureRemote(Remotes, "RemoteFunction", "AdvanceJob") :: RemoteFunction
local CastSkill = ensureRemote(Remotes, "RemoteFunction", "CastSkill") :: RemoteFunction
local EquipItem = ensureRemote(Remotes, "RemoteFunction", "EquipItem") :: RemoteFunction
local UnequipItem = ensureRemote(Remotes, "RemoteFunction", "UnequipItem") :: RemoteFunction
local UseItem = ensureRemote(Remotes, "RemoteFunction", "UseItem") :: RemoteFunction
local PickUpDrop = ensureRemote(Remotes, "RemoteFunction", "PickUpDrop") :: RemoteFunction
local ManualAttack = ensureRemote(Remotes, "RemoteFunction", "ManualAttack") :: RemoteFunction
local SetAuto = ensureRemote(Remotes, "RemoteFunction", "SetAuto") :: RemoteFunction
local DropState = ensureRemote(Remotes, "RemoteEvent", "DropState") :: RemoteEvent
local FarmState = ensureRemote(Remotes, "RemoteEvent", "FarmState") :: RemoteEvent
local WaveState = ensureRemote(Remotes, "RemoteEvent", "WaveState") :: RemoteEvent
local PlayerState = ensureRemote(Remotes, "RemoteEvent", "PlayerState") :: RemoteEvent
local Notify = ensureRemote(Remotes, "RemoteEvent", "Notify") :: RemoteEvent
local CombatFx = ensureRemote(Remotes, "RemoteEvent", "CombatFx") :: RemoteEvent
local AttackFx = ensureRemote(Remotes, "RemoteEvent", "AttackFx") :: RemoteEvent

local store = DataStoreService:GetDataStore("AXArena_v3")
local rateLimiter = RateLimiter.new()
local rng = Random.new(os.time())

type PlayerRecord = {
	-- The record is the one place that knows both the saved data and the live
	-- player, so reward paths can notify without extra plumbing.
	player: Player,
	userId: number,
	coins: number,
	upgrades: { [string]: number },
	stats: { kills: number, wavesCleared: number, deaths: number },
	level: number,
	xp: number,
	rebirth: any,
	zone: string,
	pets: any,
	entitlements: any,
	daily: any,
	redeemed: any,
	combatant: any,
	lastAttackAt: number,
	lastZoneChange: number,
	-- The field the player is standing in, or nil in town. Monsters belong to a
	-- field, so this is what decides who can hit whom.
	field: string?,
	killStreak: number,
	lastKillAt: number,
	farm: any,
	axe: any,
	-- Character build: the stat sheet, the class, the skills learned, what is
	-- worn, and the bag. All authoritative here.
	attributes: { [string]: number },
	attributePoints: number,
	class: string,
	jobLevel: number,
	jobXp: number,
	skills: { [string]: number },
	equipment: { [string]: string? },
	inventory: any,
	-- Current SP, so a skill can be paid for.
	sp: number,
	maxSp: number,
	-- Seconds remaining per skill id, and the buffs currently running.
	cooldowns: { [string]: number },
	buffs: { [string]: any },
	-- Auto modes. The player can switch either off and play by hand.
	autoAttack: boolean,
	autoPickup: boolean,
	dirty: boolean,
}

local records: { [number]: PlayerRecord } = {}

-- One wave director per field. A single shared director would put the
-- Volcano and the Meadow on the same wave forever, which is the sameness
-- this world was rebuilt to remove. A field nobody is standing in is never
-- ticked, so five maps cost almost nothing while empty.
local directors: { [string]: any } = {}

local function directorFor(fieldId: string)
	local existing = directors[fieldId]
	if existing then
		return existing
	end
	local created = WaveDirector.new(rng)
	directors[fieldId] = created
	return created
end

local function fieldOfPlayer(player: Player): string?
	local record = records[player.UserId]
	return record and record.field or nil
end

local function notify(player: Player, message: string)
	Notify:FireClient(player, message)
end

-- The full multiplier chain, in one place so every reward path agrees.
local function coinMultiplier(record: PlayerRecord, now: number): number
	local petCoin = select(1, Pets.equippedMultipliers(record.pets))
	local rebirthCoin = select(1, Rebirth.multipliers(record.rebirth.count))
	return Zones.coinMultiplier(record.zone)
		* petCoin
		* Leveling.coinMultiplier(record.level)
		* rebirthCoin
		* Monetization.coinMultiplier(record.entitlements, now)
end

-- Skill points are derived, never stored: the player earns one per job level
-- and spends one per skill level, so the balance cannot drift.
local function spentSkillPoints(record: PlayerRecord): number
	local total = 0
	for _, level in pairs(record.skills) do
		total += math.max(0, math.floor(level))
	end
	return total
end

local function skillPointsLeft(record: PlayerRecord): number
	return math.max(0, Classes.skillPointsForJobLevel(record.jobLevel) - spentSkillPoints(record))
end

-- Buffs still running, with the seconds left rather than an absolute time.
local function activeBuffs(record: PlayerRecord, now: number): { any }
	local out: { any } = {}
	for id, buff in pairs(record.buffs) do
		if now < buff.until_ then
			table.insert(out, {
				id = id,
				name = Text.skillName(id),
				secondsLeft = buff.until_ - now,
			})
		else
			record.buffs[id] = nil
		end
	end
	return out
end

local function pushPlayerState(player: Player, record: PlayerRecord)
	local now = os.time()
	local derived = Stats.derive(record.upgrades)
	local petCoin, petDamage = Pets.equippedMultipliers(record.pets)
	local rebirthCoin, rebirthDamage = Rebirth.multipliers(record.rebirth.count)

	PlayerState:FireClient(player, {
		coins = record.coins,
		upgrades = record.upgrades,
		stats = record.stats,
		derived = derived,
		health = record.combatant.health,
		maxHealth = derived.maxHealth,

		level = record.level,
		xp = record.xp,
		xpForNext = Leveling.xpForNext(record.level),
		rebirths = record.rebirth.count,
		rebirthRequirement = Rebirth.levelRequirement(record.rebirth.count),
		zone = record.zone,
		field = record.field,
		-- False only in the first field, which is the safe practice map. The HUD
		-- uses this to tell the player they cannot die here.
		fieldLethal = record.field == nil or Zones.isLethal(record.field),
		fields = Fields.snapshot(record.level, Monetization.hasZonePass(record.entitlements)),
		killStreak = record.killStreak,

		pets = Pets.snapshot(record.pets),
		petCoin = petCoin,
		petDamage = petDamage,
		maxEquipped = Pets.maxEquipped(Monetization.owns(record.entitlements, "Vip")),

		entitlements = record.entitlements,
		dailyStreak = record.daily.streak,
		dailyReady = select(1, DailyRewards.canClaim(record.daily, now)),
		dailySecondsLeft = DailyRewards.timeUntilClaim(record.daily, now),
		dailyNextReward = DailyRewards.rewardForDay(record.daily.streak + 1),
		redeemed = record.redeemed,
		coinMultiplier = coinMultiplier(record, now),
		rebirthCoin = rebirthCoin,
		rebirthDamage = rebirthDamage,
		farm = Farm.snapshot(record.farm, broadcastNow),
		axe = Axe.snapshot(record.axe),
		crops = Farm.list(),
	})
end

local function buildRecord(player: Player, saved: any): PlayerRecord
	local data = SaveSchema.new()
	if saved then
		local loaded = SaveSchema.load(saved)
		if loaded then
			data = loaded
		end
	end

	-- The attribute sheet decides the health bar, so the combatant is built
	-- after the build fields are known rather than from the old upgrade maths.
	local attributes = Attributes.copy(data.attributes)
	local startingHealth = Attributes.derive(
		Attributes.effective(attributes, Classes.bonus(data.class)),
		data.level
	).maxHealth

	local record: PlayerRecord = {
		player = player,
		coins = data.coins,
		upgrades = data.upgrades,
		stats = data.stats,
		level = data.level,
		xp = data.xp,
		rebirth = Rebirth.fromSnapshot({ count = data.rebirths }),
		zone = data.zone,
		pets = Pets.fromSnapshot(data.pets),
		entitlements = Monetization.fromSnapshot(data.entitlements),
		daily = DailyRewards.fromSnapshot(data.daily),
		redeemed = Codes.fromSnapshot(data.redeemed),
		combatant = Combat.createCombatant(math.max(1, startingHealth)),
		farm = Farm.new(),
		axe = Axe.new(),
		attributes = attributes,
		attributePoints = data.attributePoints,
		class = data.class,
		jobLevel = data.jobLevel,
		jobXp = data.jobXp,
		skills = data.skills,
		equipment = data.equipment,
		inventory = Inventory.fromSnapshot(data.inventory, Config.Items.DefaultCapacity),
		sp = 0,
		maxSp = 0,
		cooldowns = {},
		buffs = {},
		autoAttack = Config.Combat.AutoAttack,
		autoPickup = true,
		lastZoneChange = 0,
		lastAttackAt = 0,
		field = nil,
		killStreak = 0,
		lastKillAt = 0,
		dirty = false,
	}
	return record
end

local function loadRecord(player: Player): PlayerRecord
	local userId = player.UserId
	local ok, saved = pcall(function()
		return store:GetAsync("player_" .. userId)
	end)
	if not ok then
		warn("[AX Arena] load failed for " .. userId .. ": " .. tostring(saved))
		saved = nil
	end
	return buildRecord(player, saved)
end

local function saveRecord(record: PlayerRecord): boolean
	local payload = {
		version = Config.Persistence.SchemaVersion,
		coins = record.coins,
		upgrades = record.upgrades,
		inventory = record.inventory:snapshot(),
		attributes = record.attributes,
		attributePoints = record.attributePoints,
		class = record.class,
		jobLevel = record.jobLevel,
		jobXp = record.jobXp,
		skills = record.skills,
		equipment = record.equipment,
		stats = record.stats,
		level = record.level,
		xp = record.xp,
		rebirths = record.rebirth.count,
		zone = record.zone,
		pets = Pets.snapshot(record.pets),
		entitlements = record.entitlements,
		daily = DailyRewards.snapshot(record.daily),
		redeemed = Codes.snapshot(record.redeemed),
		updatedAt = os.time(),
	}
	local ok, err = pcall(function()
		store:SetAsync("player_" .. record.userId, payload)
	end)
	if not ok then
		warn("[AX Arena] save failed for " .. record.userId .. ": " .. tostring(err))
		return false
	end
	record.dirty = false
	return true
end

-- Award XP and, on level up, tell the player. Returns the levels gained.
-- Defined before rewardKill: a local function is only visible below its own
-- line, so calling it from above silently resolved to a nil global.
local function awardXp(record: PlayerRecord, amount: number): number
	local progress, gained = Leveling.addXp({ level = record.level, xp = record.xp }, amount)
	record.level = progress.level
	record.xp = progress.xp
	if gained > 0 then
		record.dirty = true
	end
	return gained
end

-- One place for "an enemy died": the kill credit goes to the player who
-- landed the last hit, and every reward scales with their multipliers.
-- Returns the coin and XP the kill actually paid, so the client can show it.
local function rewardKill(record: PlayerRecord, wave: number, reward: number, boss: boolean?): (number, number)
	local now = os.time()

	-- A kill streak pays a rising bonus and resets when the player pauses. This
	-- is what turns "clear a wave" into "do not break the run".
	if now - record.lastKillAt <= Config.Streak.WindowSeconds then
		record.killStreak += 1
	else
		record.killStreak = 1
	end
	record.lastKillAt = now
	local streakBonus = 1 + math.min(Config.Streak.MaxBonus, record.killStreak * Config.Streak.BonusPerKill)

	local scaled = math.floor(reward * coinMultiplier(record, now) * streakBonus + 0.5)
	record.coins = math.min(Config.Economy.MaxCoins, record.coins + scaled)
	record.stats.kills += 1
	if boss then
		record.stats.bossKills = (record.stats.bossKills or 0) + 1
	end

	local xp = Leveling.xpFromKill(wave) * Monetization.xpMultiplier(record.entitlements)
	if boss then
		xp *= Config.Enemies.BossXpMul
	end
	local granted = math.floor(xp + 0.5)
	awardXp(record, granted)

	-- Job XP runs on its own track, so a class levels from playing that class.
	local jobXpGain = math.max(1, math.floor(granted * Config.Classes.JobXpPerBaseXp + 0.5))
	local newJobLevel, newJobXp, jobLevels = Classes.addJobXp(record.jobLevel, record.jobXp, jobXpGain)
	record.jobLevel = newJobLevel
	record.jobXp = newJobXp
	if jobLevels > 0 then
		notify(record.player, Text.get("jobLevelUp", newJobLevel))
	end

	record.dirty = true
	return scaled, granted
end

-- The character sheet, in one place.
--
-- Three layers stack here: the attributes the player assigned, the class
-- bonus, and the equipment bonus. The upgrade levels from the original game
-- still apply on top, so an old save keeps every coin it ever spent.
local function deriveCombat(record: PlayerRecord)
	local base = Attributes.effective(record.attributes, Classes.bonus(record.class))
	base = Attributes.effective(base, Items.equipmentBonus(record.equipment))

	local sheet = Attributes.derive(base, record.level)
	local upgrades = Stats.derive(record.upgrades)
	local equipment = Items.equipmentCombat(record.equipment)
	local passive = Skills.passiveBonus(record.skills)

	local _, rebirthDamage = Rebirth.multipliers(record.rebirth.count)
	local _, petDamage = Pets.equippedMultipliers(record.pets)

	local damageMul = rebirthDamage * petDamage * passive.damageMul
	local critMul = rebirthDamage * petDamage

	local attack = math.floor((sheet.attack + equipment.attack + upgrades.damage) * damageMul + 0.5)

	return {
		attributes = base,
		maxHealth = math.floor(sheet.maxHealth * rebirthDamage + 0.5),
		maxSp = sheet.maxSp,
		attack = math.max(1, attack),
		magicAttack = math.max(1, math.floor(sheet.magicAttack * damageMul + 0.5)),
		defense = sheet.defense + equipment.defense,
		magicDefense = sheet.magicDefense,
		hit = sheet.hit + passive.hitBonus,
		flee = sheet.flee,
		critChance = math.min(1, sheet.critChance + upgrades.critChance),
		critMultiplier = Config.Attributes.CritMultiplier,
		attackInterval = sheet.attackInterval,
		walkSpeed = upgrades.walkSpeed,
		damageMul = damageMul,
		critMul = critMul,
	}
end

-- The player's own sheet, with any running buffs folded in. Combat reads this
-- rather than deriveCombat directly, so a Blessing actually changes the numbers.
local function combatSheet(record: PlayerRecord, now: number)
	local sheet = deriveCombat(record)
	for id, buff in pairs(record.buffs) do
		if now >= buff.until_ then
			record.buffs[id] = nil
		else
			sheet.attack = math.floor(sheet.attack * buff.attackMul + 0.5)
			sheet.magicAttack = math.floor(sheet.magicAttack * buff.attackMul + 0.5)
			sheet.defense = math.floor(sheet.defense * buff.defenseMul + 0.5)
			sheet.hit += buff.hitBonus
		end
	end
	return sheet
end

-- One place for "this player killed that monster". Both the axe and the
-- auto-attack path call it, so a kill pays the same and drops the same loot
-- whichever way it died.
local function onEnemyKilled(player: Player, record: PlayerRecord, enemy: any, reward: number)
	directorFor(enemy.fieldId):notifyEnemyRemoved()
	local coins, xp = rewardKill(record, enemy.wave, reward, enemy.boss)

	-- Loot on the ground. The monster's own table decides what, so a rare
	-- monster is worth hunting rather than being a recoloured common one.
	local model = World.getEnemyModel(enemy.id)
	local body = model and model.PrimaryPart
	local position = body and body.Position
	if position then
		local luck = coinMultiplier(record, os.time())
		for _, drop in ipairs(Items.rollDrops(enemy.archetype or enemy.name, rng, luck)) do
			World.spawnDrop(drop.itemId, drop.count, position, enemy.fieldId, os.clock())
		end
	end

	CombatFx:FireClient(player, {
		kind = "kill",
		name = enemy.name,
		boss = enemy.boss,
		coins = coins,
		xp = xp,
		streak = record.killStreak,
	})
	return coins, xp
end

local function applySpawnStats(record: PlayerRecord)
	local sheet = deriveCombat(record)
	record.combatant.maxHealth = sheet.maxHealth
	record.combatant.health = sheet.maxHealth
	record.maxSp = sheet.maxSp
	record.sp = sheet.maxSp
	-- Death clears this flag and nothing else sets it, so without this line a
	-- player could never attack again after their first death.
	record.combatant.alive = true
	return { walkSpeed = sheet.walkSpeed, maxHealth = sheet.maxHealth }
end

-- Spawn one monster for a field. The archetype and the field difficulty both
-- come from pure modules; this only wires them into the world layer.
local function spawnForField(fieldId: string, plan: any, spawnIndex: number, now: number)
	local archetype = Enemies.pick(fieldId, plan.wave, rng, spawnIndex == 1)
	local scaled = Enemies.scale(archetype, plan, Zones.difficultyMultiplier(fieldId))
	World.spawnEnemy(fieldId, scaled, plan.wave, spawnIndex, plan.enemyCount, now)
	return scaled
end

local function onPlayerAdded(player: Player)
	local record = loadRecord(player)
	records[player.UserId] = record

	player.CharacterAdded:Connect(function(character)
		-- Place the character on the arena spawn. The part in Workspace is only a
		-- marker; this call is what actually decides where they stand.
		-- A respawn lands where the player belongs: their field if they are
		-- still in one, otherwise town.
		World.attachPlayer(player, character, record.field or "Town")
		World.applyLook(record.field or "Town")
		-- The job decides what the character wears, so it is applied on
		-- every spawn rather than only when the job changes.
		World.applyClassLook(character, record.class)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		-- Recompute per spawn so purchases and rebirths apply on the next life.
		local derived = applySpawnStats(record)
		humanoid.MaxHealth = record.combatant.maxHealth
		humanoid.Health = record.combatant.health
		humanoid.WalkSpeed = derived.walkSpeed + Monetization.walkSpeedBonus(record.entitlements)

		-- Keep the avatar in one piece on death. Roblox breaks the joints by
		-- default, which sends the head rolling; that reads far more violent
		-- than a farm-and-fight game wants.
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Connect(function()
			record.stats.deaths += 1
			-- Dying sends the player home, the way a town-based game should. The
			-- streak breaks too, so the bonus is genuinely at risk.
			record.field = nil
			record.killStreak = 0
			record.dirty = true
			-- Death clears the combatant flag and only the spawn path sets it back, so
			-- revive before respawning or the player can never fight again.
			task.delay(Config.Player.RespawnDelay, function()
				if player.Parent then
					applySpawnStats(record)
					player:LoadCharacter()
				end
			end)
		end)
	end)

	pushPlayerState(player, record)
	FarmState:FireClient(player, { plots = Farm.snapshot(record.farm, os.clock()), axe = Axe.snapshot(record.axe) })
end

local function onPlayerRemoving(player: Player)
	local record = records[player.UserId]
	if record and record.dirty then
		saveRecord(record)
	end
	rateLimiter:forget(player.UserId)
	records[player.UserId] = nil
end

-- Every remote is rate limited and validated. The client cannot set its own
-- level, coins, pets or entitlements.
local function guard(player: Player): (PlayerRecord?, string?)
	local allowed = rateLimiter:consume(player.UserId, os.clock())
	if not allowed then
		return nil, "RATE_LIMITED"
	end
	local record = records[player.UserId]
	if not record then
		return nil, "NOT_LOADED"
	end
	return record, nil
end

RequestUpgrade.OnServerInvoke = function(player: Player, upgradeId: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(upgradeId) ~= "string" then
		return false, "BAD_REQUEST"
	end

	local ok, result, remaining = Stats.applyUpgrade(record.upgrades, upgradeId, record.coins)
	if not ok then
		return false, result
	end

	record.upgrades = result
	record.coins = remaining
	record.dirty = true

	local derived = applySpawnStats(record)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = record.combatant.maxHealth
		humanoid.WalkSpeed = derived.walkSpeed + Monetization.walkSpeedBonus(record.entitlements)
	end

	pushPlayerState(player, record)
	return true, nil
end

RequestShop.OnServerInvoke = function(player: Player)
	local record = records[player.UserId]
	local owned: { [string]: boolean } = {}
	if record then
		for id, v in pairs(record.entitlements.owned) do
			owned[id] = v
		end
	end
	return {
		products = Monetization.list(),
		eggs = Pets.listEggs(),
		zones = Zones.list(),
		owned = owned,
		level = record and record.level or 1,
	}
end

HatchEgg.OnServerInvoke = function(player: Player, eggId: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	if type(eggId) ~= "string" then
		return false, nil, "BAD_REQUEST"
	end

	-- A lucky charge improves the roll before the egg is opened.
	local luck = Monetization.takeLuck(record.entitlements)
	local def, remaining, reason = Pets.hatch(record.pets, rng, eggId, record.coins, record.level)
	if not def then
		return false, nil, reason
	end

	record.coins = remaining
	record.dirty = true
	pushPlayerState(player, record)
	return true, def, luck > 1 and "LUCKY" or nil
end

EquipPet.OnServerInvoke = function(player: Player, uid: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(uid) ~= "number" then
		return false, "BAD_REQUEST"
	end

	local vip = Monetization.owns(record.entitlements, "Vip")
	local ok, reason = Pets.equip(record.pets, math.floor(uid), vip)
	if not ok then
		return false, reason
	end

	record.dirty = true
	applySpawnStats(record)
	pushPlayerState(player, record)
	return true, nil
end

UnequipPet.OnServerInvoke = function(player: Player, uid: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(uid) ~= "number" then
		return false, "BAD_REQUEST"
	end

	if not Pets.unequip(record.pets, math.floor(uid)) then
		return false, "NOT_EQUIPPED"
	end

	record.dirty = true
	pushPlayerState(player, record)
	return true, nil
end

DoRebirth.OnServerInvoke = function(player: Player): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end

	local outcome, reason = Rebirth.perform(record.rebirth, record.level)
	if not outcome then
		return false, reason
	end

	record.rebirth = outcome.state
	record.coins = outcome.coins
	if Config.Rebirth.ResetLevel then
		record.level = outcome.level
		record.xp = outcome.xp
	end
	if outcome.resetUpgrades then
		record.upgrades = Stats.newUpgrades()
	end

	record.dirty = true
	applySpawnStats(record)
	pushPlayerState(player, record)
	notify(player, Text.get("rebirthDone", record.rebirth.count))
	return true, nil
end

-- Travel between town and the five fields. The client asks to go somewhere;
-- the server decides whether that is allowed and moves the character itself.
TravelZone.OnServerInvoke = function(player: Player, placeId: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(placeId) ~= "string" then
		return false, "BAD_REQUEST"
	end

	local now = os.time()
	if now - record.lastZoneChange < Config.Zones.SwitchCooldownSeconds then
		return false, "COOLDOWN"
	end

	local allowed, reason = Fields.canEnter(placeId, record.level, Monetization.hasZonePass(record.entitlements))
	if not allowed then
		return false, reason
	end

	local destination = Fields.isTown(placeId) and "Town" or placeId
	if Fields.isTown(destination) then
		record.field = nil
	else
		record.field = destination
		-- Coin rewards follow the field, so a richer map pays better without any
		-- change to the reward code.
		record.zone = destination
		-- A field is a place you fight in, so start the first wave on arrival
		-- instead of leaving the player standing alone for the intermission.
		directorFor(destination):skipIntermission()
	end
	record.lastZoneChange = now
	record.dirty = true

	-- Arriving somewhere new is a fresh start. Without this, a player who grinds
	-- the safe first field down to its 1 HP floor and then travels to a real
	-- field dies to the first hit before they can react. The safe field's whole
	-- purpose is to be left, so leaving it must not be a trap.
	applySpawnStats(record)
	World.placePlayer(player, destination)
	World.applyLook(destination)
	pushPlayerState(player, record)
	notify(player, Fields.isTown(destination) and Text.get("returnedToTown")
            or Text.get("entered", Text.placeName(destination)))
	return true, nil
end

-- Daily login reward. The server owns the clock and the streak; the client only
-- asks. A rejected claim returns a stable reason the UI can translate.
ClaimDaily.OnServerInvoke = function(player: Player): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end

	local now = os.time()
	local next, reward, reason = DailyRewards.claim(record.daily, now)
	if not next or not reward then
		return false, nil, reason
	end

	record.daily = next
	record.coins = math.min(Config.Economy.MaxCoins, record.coins + reward.coins)
	if reward.luckCharges > 0 then
		record.entitlements = Monetization.addLuckCharges(record.entitlements, reward.luckCharges)
	end
	record.dirty = true
	awardXp(record, reward.xp)
	pushPlayerState(player, record)
	notify(player, Text.get("dailyGain", reward.day, reward.coins))
	return true, reward, nil
end

-- Promo code redemption. The attempt is rate limited by guard, so a player
-- cannot brute force codes, and each code is single use per player.
RedeemCode.OnServerInvoke = function(player: Player, code: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	if type(code) ~= "string" then
		return false, nil, "BAD_REQUEST"
	end
	-- Codes are short; a long string is either a mistake or an attack.
	if #code > 32 then
		return false, nil, "BAD_REQUEST"
	end

	local now = os.time()
	local next, def, reason = Codes.redeem(record.redeemed, code, now)
	if not next or not def then
		return false, nil, reason
	end

	record.redeemed = next
	record.coins = math.min(Config.Economy.MaxCoins, record.coins + def.coins)
	if def.luckCharges > 0 then
		record.entitlements = Monetization.addLuckCharges(record.entitlements, def.luckCharges)
	end
	record.dirty = true
	awardXp(record, def.xp)
	pushPlayerState(player, record)
	notify(player, Text.get("codeGain", def.code, def.coins))
	return true, { code = def.code, coins = def.coins, xp = def.xp, luckCharges = def.luckCharges }, nil
end

-- Farm remotes. The server owns crop timers, so a client cannot speed
-- growth up or harvest early. Every call is rate limited by guard.
PlantCrop.OnServerInvoke = function(player: Player, plotIndex: any, cropId: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	local ok, reason = Farm.plant(record.farm, plotIndex, cropId, os.clock())
	if not ok then
		return false, reason
	end
	record.dirty = true
	pushPlayerState(player, record)
	return true, nil
end

HarvestCrop.OnServerInvoke = function(player: Player, plotIndex: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	local reward, reason = Farm.harvest(record.farm, plotIndex, os.clock())
	if not reward then
		return false, nil, reason
	end
	-- Harvest pays coins and XP, and it is what charges the axe.
	local now = os.time()
	record.coins = math.min(Config.Economy.MaxCoins, record.coins + math.floor(reward.coins * coinMultiplier(record, now) + 0.5))
	awardXp(record, reward.xp)
	Axe.addCharges(record.axe, Config.Farm.AxeChargePerHarvest)
	record.dirty = true
	pushPlayerState(player, record)
	notify(player, Text.get("harvestGain", Text.cropName(reward.cropId), reward.coins))
	return true, reward, nil
end

-- The axe spends every charge at once and hits everything near the player.
-- Farming is therefore not a side activity: it is how you charge the weapon.
UseAxe.OnServerInvoke = function(player: Player): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	if not Axe.isReady(record.axe) then
		return false, nil, "NO_CHARGES"
	end
	
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, nil, "NO_CHARACTER"
	end
	
	-- The swing scales off the player's real attack, the same sheet the
	-- auto-attack uses. It used to read Stats.derive(upgrades).damage, which
	-- ignores attributes, equipment, pets and rebirth, so a full five-charge
	-- swing was weaker than one ordinary hit: charging crops cost you damage.
	local sheet = combatSheet(record, os.clock())
	local charges, damage = Axe.swing(record.axe, sheet.attack)
	
	-- Hit every enemy inside the axe radius, not just the nearest one. Only
	-- the player's own field is searched, so a swing in town can never reach a
	-- monster standing in the Volcano.
	local hits, kills = 0, 0
	for _, enemy in ipairs(World.snapshot(record.field)) do
		local model = World.getEnemyModel(enemy.id)
		local body = model and model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			if (body.Position - root.Position).Magnitude <= Config.Farm.AxeRadius then
				hits += 1
				local killed, reward = World.damageEnemy(enemy.id, damage)
				if killed then
					kills += 1
					onEnemyKilled(player, record, enemy, reward)
				end
			end
		end
	end
	
	record.dirty = true
	pushPlayerState(player, record)
	return true, { charges = charges, damage = damage, hits = hits, kills = kills }, nil
end

-- Robux purchases. MarketplaceService is the only authority on whether money
-- changed hands; we only decide what the player is owed.
local function grantPurchase(player: Player, productId: string): boolean
	local record = records[player.UserId]
	if not record then
		return false
	end
	local result, reason = Monetization.grant(record.entitlements, productId, os.time())
	if not result then
		warn("[AX Arena] grant refused for " .. player.Name .. ": " .. tostring(reason))
		return reason == "ALREADY_OWNED"
	end

	record.entitlements = result.entitlements
	record.dirty = true
	applySpawnStats(record)
	pushPlayerState(player, record)
	notify(player, Text.get("purchaseApplied", productId))
	return true
end

--------------------------------------------------------------------------
-- The character build: attributes, job, skills, equipment, bag.
-- Every one of these validates on the server and pushes fresh state back, so
-- the client can never grant itself a point, a skill or an item.
--------------------------------------------------------------------------

-- Find the nearest living enemy to a player, within `range`. Returns the enemy
-- and its distance, or nil. Used by both attack paths and by skills.
local function nearestEnemy(record: PlayerRecord, root: BasePart, range: number)
	local best, bestDistance = nil, math.huge
	for _, enemy in ipairs(World.snapshot(record.field)) do
		local model = World.getEnemyModel(enemy.id)
		local body = model and model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			local distance = (body.Position - root.Position).Magnitude
			if distance <= range and distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best, bestDistance
end

-- Resolve one attack: hit chance, then crit, then damage. Returns the amount
-- dealt (0 on a miss) and whether it was a crit.
local function resolveHit(record: PlayerRecord, sheet: any, enemy: any, power: number): (number, boolean)
	local chance = Attributes.hitChance(sheet.hit, 10 + enemy.wave * 2)
	if rng:nextNumber() >= chance then
		return 0, false
	end

	local base = sheet.attack * power
	local isCrit = rng:nextNumber() < sheet.critChance
	if isCrit then
		base *= sheet.critMultiplier
	end

	-- The monster's defense softens the blow the same way the player's does.
	local dealt = Attributes.mitigate(base, 2 + enemy.wave * 1.5)
	return dealt, isCrit
end

-- Tell everyone else that somebody swung, so a swing is visible to the
-- whole field and not only to the player who tapped.
local function broadcastAttack(player: Player, record: PlayerRecord)
	local look = ClassLook.get(record.class)
	AttackFx:FireAllClients({
		kind = "attack",
		userId = player.UserId,
		style = look.swing,
	})
end

-- Damage one enemy and, on a kill, run the shared reward path. Returns
-- (killed, coins, xp).
local function strike(player: Player, record: PlayerRecord, enemy: any, amount: number, isCrit: boolean)
	local model = World.getEnemyModel(enemy.id)
	local body = model and model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		World.showDamage(body.Position, amount, isCrit and "crit" or nil)
	end

	local killed, reward = World.damageEnemy(enemy.id, amount)
	if not killed then
		return false, 0, 0
	end

	local coins, xp = onEnemyKilled(player, record, enemy, reward)
	return true, coins, xp
end

-- One swing, used by both the tap and the auto loop, so they cannot disagree
-- about range, damage or rewards.
local function performAttack(player: Player, record: PlayerRecord): (boolean, string?)
	if not record.combatant.alive then
		return false, "DEAD"
	end
	if not record.field then
		return false, "NOT_IN_FIELD"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "NO_CHARACTER"
	end

	local target = nearestEnemy(record, root, Config.Combat.AttackRange)
	if not target then
		return false, "NO_TARGET"
	end

	local now = os.clock()
	local sheet = combatSheet(record, now)
	if now - record.lastAttackAt < sheet.attackInterval then
		return false, "COOLDOWN"
	end
	record.lastAttackAt = now

	local amount, isCrit = resolveHit(record, sheet, target, 1)
	if amount <= 0 then
		local model = World.getEnemyModel(target.id)
		local body = model and model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			World.showDamage(body.Position, 0, "miss")
		end
		return true, nil
	end

	broadcastAttack(player, record)
	strike(player, record, target, amount, isCrit)
	record.dirty = true
	return true, nil
end

-- Manual attack. The button calls this; the auto loop calls performAttack too.
ManualAttack.OnServerInvoke = function(player: Player): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	local ok, reason = performAttack(player, record)
	if ok then
		pushPlayerState(player, record)
	end
	return ok, reason
end

-- Auto mode is a server-side flag, so switching it off genuinely stops the
-- swings rather than only hiding them from the client.
SetAuto.OnServerInvoke = function(player: Player, mode: any, value: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if mode == "attack" then
		record.autoAttack = value == true
	elseif mode == "pickup" then
		record.autoPickup = value == true
	else
		return false, "BAD_REQUEST"
	end
	record.dirty = true
	pushPlayerState(player, record)
	return true, nil
end

-- Spend a stat point. The client sends only which stat and how many.
RaiseAttribute.OnServerInvoke = function(player: Player, stat: any, times: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	if type(stat) ~= "string" then
		return false, nil, "BAD_REQUEST"
	end
	local count = math.clamp(math.floor(tonumber(times) or 1), 1, 10)

	-- Recompute the bank rather than trusting a stored count, so a stale client
	-- cannot spend points it does not have.
	record.attributePoints = Attributes.available(record.attributes, record.level)
	local ok, next, left, reason = Attributes.raise(record.attributes, record.attributePoints, stat, count)
	if not ok then
		return false, nil, reason
	end

	record.attributes = next
	record.attributePoints = left
	record.dirty = true
	applySpawnStats(record)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = record.combatant.maxHealth
		humanoid.Health = math.min(humanoid.Health, humanoid.MaxHealth)
	end
	pushPlayerState(player, record)
	notify(player, Text.get("attributeUp", Text.statName(stat), left))
	return true, { stat = stat, value = next[stat], pointsLeft = left }, nil
end

-- Learn a skill. One point, one level.
LearnSkill.OnServerInvoke = function(player: Player, skillId: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	if type(skillId) ~= "string" then
		return false, nil, "BAD_REQUEST"
	end

	local ok, next, left, reason = Skills.learn(record.skills, record.class, skillId, skillPointsLeft(record))
	if not ok then
		return false, nil, reason
	end

	record.skills = next
	record.dirty = true
	pushPlayerState(player, record)
	notify(player, Text.get("skillLearned", Text.skillName(skillId), next[skillId]))
	return true, { skillId = skillId, level = next[skillId], pointsLeft = left }, nil
end

-- Advance a job. Both the base level and the job level gates are checked here,
-- not on the client.
AdvanceJob.OnServerInvoke = function(player: Player, target: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(target) ~= "string" then
		return false, "BAD_REQUEST"
	end

	local ok, reason = Classes.canAdvance(record.class, target, record.level, record.jobLevel)
	if not ok then
		return false, reason
	end

	local advanced = Classes.advance(target)
	record.class = advanced.class
	record.jobLevel = advanced.jobLevel
	record.jobXp = advanced.jobXp
	-- Skills are kept: a Novice's First Aid is still useful as a Knight, and the
	-- class bonus changes what the same skill scales off.
	record.dirty = true
	applySpawnStats(record)
	local character = player.Character
	if character then
		World.applyClassLook(character, record.class)
	end
	pushPlayerState(player, record)
	notify(player, Text.get("jobAdvanceOk", Text.className(target)))
	return true, nil
end

-- Cast a skill. The server owns SP, cooldowns and the buff list.
CastSkill.OnServerInvoke = function(player: Player, skillId: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	if type(skillId) ~= "string" then
		return false, nil, "BAD_REQUEST"
	end

	local def = Skills.getDef(skillId)
	local level = def and math.floor(record.skills[skillId] or 0) or 0
	if not def or level <= 0 or def.kind == "passive" then
		return false, nil, "NOT_LEARNED"
	end
	if def.class ~= record.class and not Skills.isUniversal(skillId) then
		return false, nil, "WRONG_CLASS"
	end
	if not record.combatant.alive then
		return false, nil, "DEAD"
	end

	local now = os.clock()
	if (record.cooldowns[skillId] or 0) > now then
		return false, nil, "COOLDOWN"
	end

	local sheet = combatSheet(record, now)
	local cast = Skills.resolve(def, level, sheet)
	if record.sp < cast.spCost then
		return false, nil, "NO_SP"
	end
	record.sp -= cast.spCost
	record.cooldowns[skillId] = now + Skills.cooldown(def, level)

	if def.kind == "heal" then
		local before = record.combatant.health
		Combat.healCombatant(record.combatant, cast.heal)
		local gained = record.combatant.health - before
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			World.showDamage(root.Position, gained, "heal")
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = record.combatant.health
		end
		record.dirty = true
		pushPlayerState(player, record)
		return true, { kind = "heal", healed = gained }, nil
	end

	if def.kind == "buff" then
		record.buffs[skillId] = {
			until_ = now + cast.duration,
			attackMul = cast.buff.attackMul,
			defenseMul = cast.buff.defenseMul,
			hitBonus = cast.buff.hitBonus,
		}
		record.dirty = true
		pushPlayerState(player, record)
		return true, { kind = "buff", duration = cast.duration }, nil
	end

	-- Attack skills hit the nearest few enemies, up to the skill's target cap.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, nil, "NO_CHARACTER"
	end

	local candidates = {}
	for _, enemy in ipairs(World.snapshot(record.field)) do
		local model = World.getEnemyModel(enemy.id)
		local body = model and model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			local distance = (body.Position - root.Position).Magnitude
			if distance <= Config.Combat.AttackRange + 14 then
				table.insert(candidates, { enemy = enemy, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	local hitCount, killCount = 0, 0
	for index, entry in ipairs(candidates) do
		if index > cast.targets then
			break
		end
		-- The skill's damage is already absolute, so the power factor is the
		-- ratio of skill damage to a plain swing.
		local power = cast.damage / math.max(1, sheet.attack)
		local amount, isCrit = resolveHit(record, sheet, entry.enemy, power)
		if amount > 0 then
			hitCount += 1
			local killed = strike(player, record, entry.enemy, amount, isCrit)
			if killed then
				killCount += 1
			end
		end
	end

	record.dirty = true
	pushPlayerState(player, record)
	return true, { kind = "attack", hits = hitCount, kills = killCount, damage = cast.damage }, nil
end

-- Wear an item from the bag.
EquipItem.OnServerInvoke = function(player: Player, itemId: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(itemId) ~= "string" then
		return false, "BAD_REQUEST"
	end

	local ok, reason = Items.canEquip(itemId, record.level, record.equipment)
	if not ok then
		return false, reason
	end
	if record.inventory:count(itemId) <= 0 then
		return false, "NOT_IN_BAG"
	end

	local next = Items.equipTo(record.equipment, itemId)
	-- Anything displaced goes back to the bag. If the bag is full the swap is
	-- refused rather than silently destroying the old item.
	local displaced = {}
	for slot, id in pairs(record.equipment) do
		if id and next[slot] ~= id then
			table.insert(displaced, id)
		end
	end

	record.inventory:remove(itemId, 1)
	for _, id in ipairs(displaced) do
		if record.inventory:add(id, 1) > 0 then
			record.inventory:add(itemId, 1)
			return false, "BAG_FULL"
		end
	end

	record.equipment = next
	record.dirty = true
	applySpawnStats(record)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = record.combatant.maxHealth
		humanoid.Health = math.min(humanoid.Health, humanoid.MaxHealth)
	end
	pushPlayerState(player, record)
	notify(player, Text.get("equipped", Text.itemName(itemId)))
	return true, nil
end

-- Take an item off.
UnequipItem.OnServerInvoke = function(player: Player, slot: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(slot) ~= "string" then
		return false, "BAD_REQUEST"
	end
	local itemId = record.equipment[slot]
	if not itemId then
		return false, "SLOT_EMPTY"
	end
	if record.inventory:add(itemId, 1) > 0 then
		return false, "BAG_FULL"
	end

	record.equipment = Items.unequipFrom(record.equipment, slot)
	record.dirty = true
	applySpawnStats(record)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = record.combatant.maxHealth
		humanoid.Health = math.min(humanoid.Health, humanoid.MaxHealth)
	end
	pushPlayerState(player, record)
	return true, nil
end

-- Use a consumable. Health and SP potions are the two that matter; the rest
-- are small timed boosts.
UseItem.OnServerInvoke = function(player: Player, itemId: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end
	if type(itemId) ~= "string" then
		return false, nil, "BAD_REQUEST"
	end

	local def = Items.getDef(itemId)
	if not def or def.kind ~= "consumable" then
		return false, nil, "NOT_CONSUMABLE"
	end
	if record.inventory:count(itemId) <= 0 then
		return false, nil, "NOT_IN_BAG"
	end
	if not record.combatant.alive then
		return false, nil, "DEAD"
	end

	local now = os.clock()
	local sheet = combatSheet(record, now)
	local result = ""

	if def.effect == "heal" then
		local before = record.combatant.health
		Combat.healCombatant(record.combatant, math.floor(sheet.maxHealth * def.amount + 0.5))
		result = tostring(record.combatant.health - before)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = record.combatant.health
		end
	elseif def.effect == "sp" then
		local before = record.sp
		record.sp = math.min(record.maxSp, record.sp + math.floor(record.maxSp * def.amount + 0.5))
		result = tostring(record.sp - before)
	elseif def.effect == "speed" then
		record.buffs[itemId] = {
			until_ = now + 30,
			attackMul = 1,
			defenseMul = 1,
			hitBonus = 0,
		}
		result = "30"
	elseif def.effect == "luck" then
		record.buffs[itemId] = {
			until_ = now + 60,
			attackMul = 1,
			defenseMul = 1,
			hitBonus = 10,
		}
		result = "60"
	else
		return false, nil, "UNKNOWN_EFFECT"
	end

	record.inventory:remove(itemId, 1)
	record.dirty = true
	pushPlayerState(player, record)
	notify(player, Text.get("usedItem", Text.itemName(itemId)))
	return true, { itemId = itemId, effect = def.effect, result = result }, nil
end

-- Pick up one drop, or every drop in range when `all` is true.
PickUpDrop.OnServerInvoke = function(player: Player, dropId: any, all: any): (boolean, any, string?)
	local record, err = guard(player)
	if not record then
		return false, nil, err
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, nil, "NO_CHARACTER"
	end

	local range = all == true and Config.Items.AutoPickupRange or Config.Items.PickupRange
	local taken = {}
	for _, drop in ipairs(World.dropSnapshot(record.field)) do
		local wanted = all == true or (type(dropId) == "number" and drop.id == dropId)
		if wanted and (drop.position - root.Position).Magnitude <= range then
			local def = Items.getDef(drop.itemId)
			if def and record.inventory:add(drop.itemId, drop.count) == 0 then
				World.removeDrop(drop.id)
				table.insert(taken, { itemId = drop.itemId, count = drop.count })
			end
		end
	end

	if #taken == 0 then
		return false, nil, "NOTHING_IN_RANGE"
	end

	record.dirty = true
	pushPlayerState(player, record)
	return true, taken, nil
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player left; do not consume the receipt so it can be retried.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = Monetization.get(receiptInfo.ProductId)
	local productId = product and product.id
	if not productId then
		-- Unknown product id: grant nothing but stop retrying forever.
		warn("[AX Arena] unknown product id " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if grantPurchase(player, productId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Authoritative tick.
local accumulator = 0
local lastBroadcastAt = 0
local lastFarmBroadcastAt = 0
local TICK_STEP = 1 / Config.Tick.Rate

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	while accumulator >= TICK_STEP do
		accumulator -= TICK_STEP

		-- Only fields with somebody standing in them are advanced. An empty map
		-- therefore costs nothing, which is what makes five maps affordable.
		local occupied: { [string]: boolean } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local record = records[player.UserId]
			if record and record.field then
				occupied[record.field] = true
			end
		end

		for fieldId in pairs(occupied) do
			local fieldDirector = directorFor(fieldId)
			local events, completed = fieldDirector:update(TICK_STEP)

			-- The first spawn of a boss wave is the field boss; the rest of the
			-- wave is drawn from that field's roster.
			local spawnIndex = 0
			for _, plan in ipairs(events) do
				-- Spawn a real, visible enemy. It is damaged by players, not by
				-- this loop, so a kill always means somebody actually fought.
				spawnIndex += 1
				spawnForField(fieldId, plan, spawnIndex, os.clock())
				fieldDirector:notifyEnemySpawned()
			end

			if completed then
				for _, player in ipairs(Players:GetPlayers()) do
					local record = records[player.UserId]
					if record and record.field == fieldId then
						record.stats.wavesCleared += 1
						record.dirty = true
					end
				end
			end
		end
	end

	-- Per-player upkeep: SP regeneration, cooldowns, auto attack and auto
	-- pickup. Auto attack only runs while the player has it switched on, so
	-- playing by hand is a real choice rather than a slower version of the same
	-- thing.
	for _, player in ipairs(Players:GetPlayers()) do
		local record = records[player.UserId]
		if not record then
			continue
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local inField = root and root:IsA("BasePart") and record.field ~= nil

		-- SP comes back on its own, faster with more INT, so a caster is never
		-- permanently out of mana.
		local sheet = deriveCombat(record)
		local regen = Config.Skills.SpRegenPerSecond + sheet.maxSp * Config.Skills.SpRegenPercent
		record.sp = math.min(sheet.maxSp, record.sp + regen * TICK_STEP)
		record.maxSp = sheet.maxSp

		-- A dead player stops attacking, and the buff list is left to expire.
		if record.combatant.alive and inField then
			if record.autoAttack then
				performAttack(player, record)
			end

			-- Auto pickup: anything close enough is collected without a tap.
			if record.autoPickup then
				local taken = false
				for _, drop in ipairs(World.dropSnapshot(record.field)) do
					if (drop.position - root.Position).Magnitude <= Config.Items.AutoPickupRange then
						if record.inventory:add(drop.itemId, drop.count) == 0 then
							World.removeDrop(drop.id)
							taken = true
							notify(player, Text.get("looted", Text.itemName(drop.itemId), drop.count))
						end
					end
				end
				if taken then
					record.dirty = true
				end
			end
		end
	end

	-- Old drops expire, so a long session does not fill the world with parts.
	World.pruneDrops(os.clock())

	-- Enemies chase and hit players. Keeping the damage and reward rules
	-- here keeps all combat maths in one place.
	World.updateEnemies(TICK_STEP, os.clock(), fieldOfPlayer, function(target, damage)
		local record = records[target.UserId]
		if not record then
			return
		end
		-- The first field cannot kill. A monster still lands its hit and the
		-- health bar still drops, but the last point is floored, so a new
		-- character can grind there for as long as they like. Every later field
		-- passes nothing here and is lethal.
		local safeField = not Zones.isLethal(record.field or "")
		local died = Combat.damageCombatant(record.combatant, damage, safeField)
		if died then
			local character = target.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
			record.stats.deaths += 1
			record.dirty = true
		end
	end)

	-- These snapshots feed the HUD, not the simulation. They used to be sent
	-- once per frame, which is a flood of events for a phone and for bars that
	-- only move a few times a second. Both now ride a slower clock.
	local broadcastNow = os.clock()
	if broadcastNow - lastBroadcastAt >= Config.Tick.BroadcastInterval then
		lastBroadcastAt = broadcastNow

		-- Each player sees the wave of the field they are standing in. In town
		-- there is no wave at all, so the banner reads as a rest rather than a
		-- blank or, worse, somebody else's fight.
		local waveSnapshots: { [string]: any } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local record = records[player.UserId]
			if record then
				local fieldId = record.field
				local snapshot
				if fieldId then
					snapshot = waveSnapshots[fieldId]
					if not snapshot then
						snapshot = directorFor(fieldId):snapshot()
						snapshot.aliveEnemies = World.aliveCount(fieldId)
						snapshot.field = fieldId
						snapshot.boss = World.bossInfo(fieldId)
						waveSnapshots[fieldId] = snapshot
					end
				else
					snapshot = { phase = "TOWN", wave = 0, timeRemaining = 0, aliveEnemies = 0, field = nil }
				end
				WaveState:FireClient(player, snapshot)
			end
		end
	end

	-- Crops ripen over minutes, so the farm rows do not need the HUD cadence.
	if broadcastNow - lastFarmBroadcastAt >= Config.Tick.FarmBroadcastInterval then
		lastFarmBroadcastAt = broadcastNow

		-- Draw the plots from the first player's farm: the beds are shared world
		-- parts, so drawing them once per tick is enough for everybody.
		for _, player in ipairs(Players:GetPlayers()) do
			local record = records[player.UserId]
			if record then
				for _, plot in ipairs(Farm.snapshot(record.farm, broadcastNow)) do
					World.updatePlot(plot.index, plot.cropId, plot.ready, plot.secondsLeft)
				end
			end
			break
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local record = records[player.UserId]
			if record then
				FarmState:FireClient(player, { plots = Farm.snapshot(record.farm, broadcastNow), axe = Axe.snapshot(record.axe) })
			end
		end
	end
end)

-- Build the playable world before anyone can join.
World.buildWorld()

-- A portal touch goes through the same travel path as the map button, so the
-- level lock and the cooldown are enforced in one place.
World.setPortalHandler(function(player: Player, placeId: string)
	local record = records[player.UserId]
	if not record then
		return
	end
	-- Reuse the remote's own rules by calling the same handler, so a walk-in and
	-- a button press cannot diverge.
	if TravelZone.OnServerInvoke then
		TravelZone.OnServerInvoke(player, placeId)
	end
end)

-- Periodic persistence.
task.spawn(function()
	while true do
		task.wait(Config.Persistence.SaveIntervalSeconds)
		for _, record in pairs(records) do
			if record.dirty then
				saveRecord(record)
			end
		end
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	for _, record in pairs(records) do
		if record.dirty then
			saveRecord(record)
		end
	end
end)

print(string.format("[AX Arena] server ready (schema v%d)", Config.Persistence.SchemaVersion))

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
local FarmState = ensureRemote(Remotes, "RemoteEvent", "FarmState") :: RemoteEvent
local WaveState = ensureRemote(Remotes, "RemoteEvent", "WaveState") :: RemoteEvent
local PlayerState = ensureRemote(Remotes, "RemoteEvent", "PlayerState") :: RemoteEvent
local Notify = ensureRemote(Remotes, "RemoteEvent", "Notify") :: RemoteEvent
local CombatFx = ensureRemote(Remotes, "RemoteEvent", "CombatFx") :: RemoteEvent

local store = DataStoreService:GetDataStore("AXArena_v3")
local rateLimiter = RateLimiter.new()
local rng = Random.new(os.time())

type PlayerRecord = {
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

local function buildRecord(userId: number, saved: any): PlayerRecord
	local data = SaveSchema.new()
	if saved then
		local loaded = SaveSchema.load(saved)
		if loaded then
			data = loaded
		end
	end

	local record: PlayerRecord = {
		userId = userId,
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
		combatant = Combat.createCombatant(Stats.derive(data.upgrades).maxHealth),
		farm = Farm.new(),
		axe = Axe.new(),
		lastZoneChange = 0,
		lastAttackAt = 0,
		field = nil,
		killStreak = 0,
		lastKillAt = 0,
		dirty = false,
	}
	return record
end

local function loadRecord(userId: number): PlayerRecord
	local ok, saved = pcall(function()
		return store:GetAsync("player_" .. userId)
	end)
	if not ok then
		warn("[AX Arena] load failed for " .. userId .. ": " .. tostring(saved))
		saved = nil
	end
	return buildRecord(userId, saved)
end

local function saveRecord(record: PlayerRecord): boolean
	local payload = {
		version = Config.Persistence.SchemaVersion,
		coins = record.coins,
		upgrades = record.upgrades,
		inventory = {},
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
	record.dirty = true
	return scaled, granted
end

local function applySpawnStats(record: PlayerRecord)
	local derived = Stats.derive(record.upgrades)
	local _, rebirthDamage = Rebirth.multipliers(record.rebirth.count)
	local _, petDamage = Pets.equippedMultipliers(record.pets)
	record.combatant.maxHealth = math.floor(derived.maxHealth * rebirthDamage)
	record.combatant.health = record.combatant.maxHealth
	-- Death clears this flag and nothing else sets it, so without this line a
	-- player could never attack again after their first death.
	record.combatant.alive = true
	return derived, rebirthDamage * petDamage
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
	local record = loadRecord(player.UserId)
	records[player.UserId] = record

	player.CharacterAdded:Connect(function(character)
		-- Place the character on the arena spawn. The part in Workspace is only a
		-- marker; this call is what actually decides where they stand.
		-- A respawn lands where the player belongs: their field if they are
		-- still in one, otherwise town.
		World.attachPlayer(player, character, record.field or "Town")
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
	notify(player, string.format("Rebirth %d complete!", record.rebirth.count))
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

	World.placePlayer(player, destination)
	pushPlayerState(player, record)
	notify(player, Fields.isTown(destination) and "Returned to town" or ("Entered " .. destination))
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
	notify(player, string.format("Daily day %d: +%d coins", reward.day, reward.coins))
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
	notify(player, string.format("Code %s: +%d coins", def.code, def.coins))
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
	notify(player, string.format("Harvested %s: +%d coins", reward.cropId, reward.coins))
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
	
	local baseDamage = Stats.derive(record.upgrades).damage
	local charges, damage = Axe.swing(record.axe, baseDamage)
	
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
					directorFor(enemy.fieldId):notifyEnemyRemoved()
					local coins = rewardKill(record, enemy.wave, reward, enemy.boss)
					CombatFx:FireClient(player, {
						kind = "kill",
						name = enemy.name,
						boss = enemy.boss,
						coins = coins,
						streak = record.killStreak,
					})
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
	notify(player, "Purchase applied: " .. productId)
	return true
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

	-- Mobile-first auto attack: the nearest enemy in range takes a hit on a
	-- fixed cadence. The server picks the target and rolls the damage.
	for _, player in ipairs(Players:GetPlayers()) do
		local record = records[player.UserId]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- Auto attack only works inside a field. In town there is nothing to
		-- fight, and that safety is the point of a town.
		if record and root and root:IsA("BasePart") and record.combatant.alive and record.field then
			local now = os.clock()
			if now - record.lastAttackAt >= Config.Combat.AttackInterval then
				local target, targetDistance = nil, math.huge
				for _, enemy in ipairs(World.snapshot(record.field)) do
					local model = World.getEnemyModel(enemy.id)
					local body = model and model:FindFirstChild("Body")
					if body and body:IsA("BasePart") then
						local distance = (body.Position - root.Position).Magnitude
						if distance <= Config.Combat.AttackRange and distance < targetDistance then
							target, targetDistance = enemy, distance
						end
					end
				end
				if target then
					record.lastAttackAt = now
					local damage = Stats.rollDamage(Stats.derive(record.upgrades), rng)
					local killed, reward = World.damageEnemy(target.id, damage)
					if killed then
						directorFor(target.fieldId):notifyEnemyRemoved()
						local coins = rewardKill(record, target.wave, reward, target.boss)
						CombatFx:FireClient(player, {
							kind = "kill",
							name = target.name,
							boss = target.boss,
							coins = coins,
							streak = record.killStreak,
						})
					end
				end
			end
		end
	end

	-- Enemies chase and hit players. Keeping the damage and reward rules
	-- here keeps all combat maths in one place.
	World.updateEnemies(TICK_STEP, os.clock(), fieldOfPlayer, function(target, damage)
		local record = records[target.UserId]
		if not record then
			return
		end
		local died = Combat.damageCombatant(record.combatant, damage)
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

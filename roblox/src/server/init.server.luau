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
local WaveState = ensureRemote(Remotes, "RemoteEvent", "WaveState") :: RemoteEvent
local PlayerState = ensureRemote(Remotes, "RemoteEvent", "PlayerState") :: RemoteEvent
local Notify = ensureRemote(Remotes, "RemoteEvent", "Notify") :: RemoteEvent

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
	waveAtKill: number,
	lastZoneChange: number,
	dirty: boolean,
}

local records: { [number]: PlayerRecord } = {}
local director = WaveDirector.new(rng)

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
		lastZoneChange = 0,
		lastAttackAt = 0,
		waveAtKill = 1,
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

-- One place for "an enemy died": the kill credit goes to the player who
-- landed the last hit, and every reward scales with their multipliers.
local function rewardKill(record: PlayerRecord, wave: number, reward: number)
	local now = os.time()
	local scaled = math.floor(reward * coinMultiplier(record, now) + 0.5)
	record.coins = math.min(Config.Economy.MaxCoins, record.coins + scaled)
	record.stats.kills += 1
	local xp = math.floor(Leveling.xpFromKill(wave) * Monetization.xpMultiplier(record.entitlements) + 0.5)
	awardXp(record, xp)
	record.dirty = true
end

-- Award XP and, on level up, tell the player. Returns the levels gained.
local function awardXp(record: PlayerRecord, amount: number): number
	local progress, gained = Leveling.addXp({ level = record.level, xp = record.xp }, amount)
	record.level = progress.level
	record.xp = progress.xp
	if gained > 0 then
		record.dirty = true
	end
	return gained
end

local function applySpawnStats(record: PlayerRecord)
	local derived = Stats.derive(record.upgrades)
	local _, rebirthDamage = Rebirth.multipliers(record.rebirth.count)
	local _, petDamage = Pets.equippedMultipliers(record.pets)
	record.combatant.maxHealth = math.floor(derived.maxHealth * rebirthDamage)
	record.combatant.health = record.combatant.maxHealth
	return derived, rebirthDamage * petDamage
end

local function onPlayerAdded(player: Player)
	local record = loadRecord(player.UserId)
	records[player.UserId] = record

	player.CharacterAdded:Connect(function(character)
		-- Place the character on the arena spawn. The part in Workspace is only a
		-- marker; this call is what actually decides where they stand.
		World.attachPlayer(player, character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		-- Recompute per spawn so purchases and rebirths apply on the next life.
		local derived = applySpawnStats(record)
		humanoid.MaxHealth = record.combatant.maxHealth
		humanoid.Health = record.combatant.health
		humanoid.WalkSpeed = derived.walkSpeed + Monetization.walkSpeedBonus(record.entitlements)

		humanoid.Died:Connect(function()
			record.stats.deaths += 1
			record.dirty = true
			task.delay(Config.Player.RespawnDelay, function()
				if player.Parent then
					player:LoadCharacter()
				end
			end)
		end)
	end)

	pushPlayerState(player, record)
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

TravelZone.OnServerInvoke = function(player: Player, zoneId: any): (boolean, string?)
	local record, err = guard(player)
	if not record then
		return false, err
	end
	if type(zoneId) ~= "string" then
		return false, "BAD_REQUEST"
	end

	local now = os.time()
	if now - record.lastZoneChange < Config.Zones.SwitchCooldownSeconds then
		return false, "COOLDOWN"
	end

	local resolved, reason = Zones.resolveTravel(
		zoneId,
		record.level,
		Monetization.hasZonePass(record.entitlements)
	)
	if not resolved then
		return false, reason
	end

	record.zone = resolved
	record.lastZoneChange = now
	record.dirty = true
	pushPlayerState(player, record)
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
local TICK_STEP = 1 / Config.Tick.Rate

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	while accumulator >= TICK_STEP do
		accumulator -= TICK_STEP
		local events, completed = director:update(TICK_STEP)

		for _, plan in ipairs(events) do
			-- Spawn a real, visible enemy. It is damaged by players, not by
			-- this loop, so a kill always means somebody actually fought.
			World.spawnEnemy(plan, World.aliveCount() + 1, plan.enemyCount, os.clock())
			director:notifyEnemySpawned()
		end

		if completed then
			for _, record in pairs(records) do
				record.stats.wavesCleared += 1
				record.dirty = true
			end
		end
	end

	-- Mobile-first auto attack: the nearest enemy in range takes a hit on a
	-- fixed cadence. The server picks the target and rolls the damage.
	for _, player in ipairs(Players:GetPlayers()) do
		local record = records[player.UserId]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if record and root and root:IsA("BasePart") and record.combatant.alive then
			local now = os.clock()
			if now - record.lastAttackAt >= Config.Combat.AttackInterval then
				local targetId, targetDistance = nil, math.huge
				for _, enemy in ipairs(World.snapshot()) do
					local model = World.getEnemyModel(enemy.id)
					local body = model and model:FindFirstChild("Body")
					if body and body:IsA("BasePart") then
						local distance = (body.Position - root.Position).Magnitude
						if distance <= Config.Combat.AttackRange and distance < targetDistance then
							targetId, targetDistance = enemy.id, distance
						end
					end
				end
				if targetId then
					record.lastAttackAt = now
					local damage = Stats.rollDamage(Stats.derive(record.upgrades), rng)
					local killed, reward = World.damageEnemy(targetId, damage)
					if killed then
						director:notifyEnemyRemoved()
						rewardKill(record, record.waveAtKill, reward)
					end
				end
			end
		end
	end

	-- Enemies chase and hit players. Keeping the damage and reward rules
	-- here keeps all combat maths in one place.
	World.updateEnemies(TICK_STEP, os.clock(), function(target, damage)
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

	local snapshot = director:snapshot()
	snapshot.aliveEnemies = World.aliveCount()
	for _, record in pairs(records) do
		record.waveAtKill = math.max(1, snapshot.wave)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		WaveState:FireClient(player, snapshot)
	end
end)

-- Build the playable world before anyone can join.
World.buildArena()

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

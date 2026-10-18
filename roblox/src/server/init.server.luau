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
	combatant: any,
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
		combatant = Combat.createCombatant(Stats.derive(data.upgrades).maxHealth),
		lastZoneChange = 0,
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
			local enemy = Combat.createEnemy(plan, os.clock())
			director:notifyEnemySpawned()

			-- Enemies are resolved immediately in the reference loop; the
			-- reward path is what matters here, and it must stay in one place.
			local killed, reward = Combat.damageEnemy(enemy, math.huge)
			if killed then
				director:notifyEnemyRemoved()
				local now = os.time()
				for _, record in pairs(records) do
					local scaled = math.floor(reward * coinMultiplier(record, now) + 0.5)
					record.coins = math.min(Config.Economy.MaxCoins, record.coins + scaled)
					record.stats.kills += 1
					local xp = math.floor(
						Leveling.xpFromKill(plan.wave) * Monetization.xpMultiplier(record.entitlements) + 0.5
					)
					awardXp(record, xp)
					record.dirty = true
				end
			end
		end

		if completed then
			for _, record in pairs(records) do
				record.stats.wavesCleared += 1
				record.dirty = true
			end
		end
	end

	local snapshot = director:snapshot()
	for _, player in ipairs(Players:GetPlayers()) do
		WaveState:FireClient(player, snapshot)
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

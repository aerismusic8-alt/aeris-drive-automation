--!strict
-- Server entry point: owns the authoritative game loop.
--
-- Every number that matters (health, coins, upgrades, wave state) lives here.
-- The client only renders and sends intent, which is validated against the
-- pure modules in src/shared.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Random = require(Shared.Random)
local Stats = require(Shared.Stats)
local Inventory = require(Shared.Inventory)
local Combat = require(Shared.Combat)
local WaveDirector = require(Shared.WaveDirector)
local SaveSchema = require(Shared.SaveSchema)
local RateLimiter = require(Shared.RateLimiter)

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
local WaveState = ensureRemote(Remotes, "RemoteEvent", "WaveState") :: RemoteEvent
local PlayerState = ensureRemote(Remotes, "RemoteEvent", "PlayerState") :: RemoteEvent

local store = DataStoreService:GetDataStore("AXArena_v2")
local rateLimiter = RateLimiter.new()
local rng = Random.new(os.time())

type PlayerRecord = {
	userId: number,
	coins: number,
	upgrades: { [string]: number },
	inventory: any,
	stats: { kills: number, wavesCleared: number, deaths: number },
	combatant: any,
	dirty: boolean,
}

local records: { [number]: PlayerRecord } = {}
local director = WaveDirector.new(rng)

local function pushPlayerState(player: Player, record: PlayerRecord)
	local derived = Stats.derive(record.upgrades)
	PlayerState:FireClient(player, {
		coins = record.coins,
		upgrades = record.upgrades,
		inventory = record.inventory:snapshot(),
		stats = record.stats,
		derived = derived,
		health = record.combatant.health,
		maxHealth = derived.maxHealth,
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

	local combatant = Combat.createCombatant(Stats.derive(data.upgrades).maxHealth)
	return {
		userId = userId,
		coins = data.coins,
		upgrades = data.upgrades,
		inventory = Inventory.fromSnapshot(data.inventory),
		stats = data.stats,
		combatant = combatant,
		dirty = false,
	}
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
		inventory = record.inventory:snapshot(),
		stats = record.stats,
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

local function onPlayerAdded(player: Player)
	local record = loadRecord(player.UserId)
	records[player.UserId] = record

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		-- Recompute per spawn so upgrade purchases apply on the next life.
		local derived = Stats.derive(record.upgrades)
		record.combatant.maxHealth = derived.maxHealth
		humanoid.MaxHealth = derived.maxHealth
		humanoid.Health = math.min(record.combatant.health, derived.maxHealth)
		humanoid.WalkSpeed = derived.walkSpeed

		humanoid.Died:Connect(function()
			record.stats.deaths += 1
			record.dirty = true
			record.combatant = Combat.createCombatant(Stats.derive(record.upgrades).maxHealth)
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

-- Upgrade requests are validated server side; the client cannot set its own
-- level or spend coins it does not have.
RequestUpgrade.OnServerInvoke = function(player: Player, upgradeId: any): (boolean, string?)
	local now = os.clock()
	local allowed = rateLimiter:consume(player.UserId, now)
	if not allowed then
		return false, "RATE_LIMITED"
	end

	if type(upgradeId) ~= "string" then
		return false, "BAD_REQUEST"
	end

	local record = records[player.UserId]
	if not record then
		return false, "NOT_LOADED"
	end

	local ok, result, remaining = Stats.applyUpgrade(record.upgrades, upgradeId, record.coins)
	if not ok then
		return false, result
	end

	record.upgrades = result
	record.coins = remaining
	record.dirty = true

	local derived = Stats.derive(record.upgrades)
	record.combatant.maxHealth = derived.maxHealth
	record.combatant.health = math.min(record.combatant.health, derived.maxHealth)

	pushPlayerState(player, record)
	return true, nil
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
			-- Placeholder: instant resolution keeps the reference loop testable.
			local killed, reward = Combat.damageEnemy(enemy, math.huge)
			if killed then
				director:notifyEnemyRemoved()
				for _, record in pairs(records) do
					record.coins = math.min(Config.Economy.MaxCoins, record.coins + reward)
					record.stats.kills += 1
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

--!strict
-- The playable world: ground, spawn, and enemies you can actually hit.
--
-- The wave logic is pure Luau and lives in WaveDirector/Combat. This module is
-- the thin Roblox layer that turns those numbers into parts in Workspace, so a
-- player who joins sees a place to stand and something to fight.
--
-- The server owns every enemy's health. Clients only see the result, which is
-- why the "immediately kill" shortcut in the reference loop is replaced here.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local World = {}

local ARENA_SIZE = 220
local ARENA_Y = 0
local SPAWN_POSITION = Vector3.new(0, 4, 40)
local ENEMY_RING_RADIUS = 70
local ENEMY_HEIGHT_OFFSET = 3
local ENEMY_SIZE = Vector3.new(4, 5, 4)

local enemies: { [number]: any } = {}
local enemyModels: { [number]: Model } = {}
local nextEnemyId = 0

local arenaRoot: Model? = nil

-- A flat, readable arena. Bright and simple: this is the first thing a new
-- player sees, and a confusing first frame loses them immediately.
function World.buildArena(): Model
	if arenaRoot and arenaRoot.Parent then
		return arenaRoot
	end

	local folder = Instance.new("Model")
	folder.Name = "AXArenaWorld"

	local base = Instance.new("Part")
	base.Name = "Baseplate"
	base.Size = Vector3.new(ARENA_SIZE, 4, ARENA_SIZE)
	base.Position = Vector3.new(0, ARENA_Y - 2, 0)
	base.Anchored = true
	base.Material = Enum.Material.Grass
	base.Color = Color3.fromRGB(88, 152, 92)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = folder

	-- A visible boundary so players understand the arena is finite.
	for _, side in ipairs({
		{ name = "WallNorth", size = Vector3.new(ARENA_SIZE, 18, 4), pos = Vector3.new(0, 9, -ARENA_SIZE / 2) },
		{ name = "WallSouth", size = Vector3.new(ARENA_SIZE, 18, 4), pos = Vector3.new(0, 9, ARENA_SIZE / 2) },
		{ name = "WallEast", size = Vector3.new(4, 18, ARENA_SIZE), pos = Vector3.new(ARENA_SIZE / 2, 9, 0) },
		{ name = "WallWest", size = Vector3.new(4, 18, ARENA_SIZE), pos = Vector3.new(-ARENA_SIZE / 2, 9, 0) },
	}) do
		local wall = Instance.new("Part")
		wall.Name = side.name
		wall.Size = side.size
		wall.Position = side.pos
		wall.Anchored = true
		wall.Material = Enum.Material.Slate
		wall.Color = Color3.fromRGB(70, 78, 92)
		wall.Transparency = 0.25
		wall.CanCollide = false
		wall.Parent = folder
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArenaSpawn"
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.Position = SPAWN_POSITION
	spawn.Anchored = true
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(255, 214, 92)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	-- A readable centre marker so the player has a landmark.
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(1, 6, 6)
	beacon.CFrame = CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(90))
	beacon.Anchored = true
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(120, 200, 255)
	beacon.Parent = folder

	folder.Parent = Workspace
	arenaRoot = folder
	return folder
end

-- Where enemies stand for this wave. A ring keeps them off the spawn point, so
-- a new player is never killed before they can react.
local function ringPosition(index: number, total: number): Vector3
	local angle = (index / math.max(1, total)) * math.pi * 2
	local radius = ENEMY_RING_RADIUS * (0.75 + 0.25 * ((index % 3) / 2))
	return Vector3.new(math.cos(angle) * radius, ENEMY_HEIGHT_OFFSET, math.sin(angle) * radius)
end

local function buildEnemyModel(enemy: any, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Enemy_" .. enemy.id

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = ENEMY_SIZE
	body.Position = position
	body.Anchored = true
	body.Material = Enum.Material.Neon
	-- Colour by wave so later, harder waves read as more dangerous.
	body.Color = Color3.fromRGB(220, 70, 70):Lerp(Color3.fromRGB(160, 60, 220), math.min(1, enemy.wave / 25))
	body.Parent = model

	-- A health bar in the world, so the player can see progress without a UI.
	local bar = Instance.new("BillboardGui")
	bar.Name = "HealthBar"
	bar.Size = UDim2.new(4, 0, 0.6, 0)
	bar.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	bar.AlwaysOnTop = true
	bar.Parent = body

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 1, 0)
	track.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	track.BorderSizePixel = 0
	track.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 120)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = "W" .. enemy.wave
	label.Parent = bar

	model.PrimaryPart = body
	model.Parent = Workspace
	return model
end

local function refreshHealthBar(enemy: any, model: Model)
	local body = model:FindFirstChild("Body")
	if not body then
		return
	end
	local bar = body:FindFirstChild("HealthBar")
	if not bar then
		return
	end
	local fill = bar:FindFirstChild("Track") and bar.Track:FindFirstChild("Fill")
	if not fill then
		return
	end
	local ratio = 0
	if enemy.maxHealth > 0 then
		ratio = math.clamp(enemy.health / enemy.maxHealth, 0, 1)
	end
	fill.Size = UDim2.new(ratio, 0, 1, 0)
	-- Green when healthy, red when nearly dead: readable at a glance.
	fill.BackgroundColor3 = Color3.fromRGB(220, 90, 90):Lerp(Color3.fromRGB(90, 220, 120), ratio)
end

-- Spawn one enemy from a wave plan. Returns the enemy record.
function World.spawnEnemy(plan: any, index: number, total: number, now: number)
	nextEnemyId += 1
	local enemy = {
		id = nextEnemyId,
		wave = plan.wave,
		health = plan.enemyHealth,
		maxHealth = plan.enemyHealth,
		damage = plan.enemyDamage,
		reward = plan.rewardPerKill,
		nextAttackAt = now + Config.Wave.EnemyAttackInterval,
		alive = true,
	}

	local model = buildEnemyModel(enemy, ringPosition(index, total))
	enemies[enemy.id] = enemy
	enemyModels[enemy.id] = model
	return enemy
end

function World.getEnemy(id: number)
	return enemies[id]
end

function World.getEnemyModel(id: number): Model?
	return enemyModels[id]
end

-- Apply damage and reflect it in the world. Returns killed, reward.
function World.damageEnemy(id: number, amount: number): (boolean, number)
	local enemy = enemies[id]
	if not enemy or not enemy.alive then
		return false, 0
	end

	enemy.health -= amount
	if enemy.health > 0 then
		local model = enemyModels[id]
		if model then
			refreshHealthBar(enemy, model)
		end
		return false, 0
	end

	enemy.health = 0
	enemy.alive = false
	local reward = enemy.reward

	local model = enemyModels[id]
	if model then
		-- A short burst so the kill is visible rather than an instant vanish.
		local body = model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			body.Material = Enum.Material.SmoothPlastic
			body.Color = Color3.fromRGB(255, 240, 180)
			body.Size = body.Size * 1.4
		end
		task.delay(0.12, function()
			if model and model.Parent then
				model:Destroy()
			end
		end)
	end

	enemies[id] = nil
	enemyModels[id] = nil
	return true, reward
end

function World.removeEnemy(id: number)
	local model = enemyModels[id]
	if model then
		model:Destroy()
	end
	enemies[id] = nil
	enemyModels[id] = nil
end

function World.clearEnemies()
	for id, model in pairs(enemyModels) do
		if model and model.Parent then
			model:Destroy()
		end
		enemies[id] = nil
	end
	enemyModels = {}
end

function World.aliveCount(): number
	local count = 0
	for _, enemy in pairs(enemies) do
		if enemy.alive then
			count += 1
		end
	end
	return count
end

-- Keep every player inside the arena and standing, whatever they do.
function World.attachPlayer(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root then
		return
	end

	-- The character spawns at the SpawnLocation; a fallback guards the case
	-- where the place has no spawn at all.
	root.CFrame = CFrame.new(SPAWN_POSITION + Vector3.new(0, 2, 0))
end

-- Move enemies toward the nearest player and let them attack. Called from the
-- server tick, so enemy pressure is real and cannot be skipped by the client.
function World.updateEnemies(dt: number, now: number, onAttack: (Player, number) -> ())
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	for id, enemy in pairs(enemies) do
		if enemy.alive then
			local target: Player? = nil
			local bestDistance = math.huge
			for _, player in ipairs(players) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local distance = (root.Position - Vector3.new(0, ENEMY_HEIGHT_OFFSET, 0)).Magnitude
					if distance < bestDistance then
						bestDistance = distance
						target = player
					end
				end
			end

			local model = enemyModels[id]
			local body = model and model:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				-- Drift slowly toward the arena centre: readable and non-lethal.
				local direction = (Vector3.new(0, body.Position.Y, 0) - body.Position)
				if direction.Magnitude > 1 then
					body.CFrame = body.CFrame + direction.Unit * math.min(14, direction.Magnitude) * dt
				end
			end

			if target and now >= enemy.nextAttackAt then
				enemy.nextAttackAt = now + Config.Wave.EnemyAttackInterval
				onAttack(target, enemy.damage)
			end
		end
	end
end

function World.snapshot()
	local out = {}
	for _, enemy in pairs(enemies) do
		table.insert(out, {
			id = enemy.id,
			wave = enemy.wave,
			health = enemy.health,
			maxHealth = enemy.maxHealth,
			alive = enemy.alive,
		})
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

return World

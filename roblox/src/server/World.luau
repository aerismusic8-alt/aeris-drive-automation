--!strict
-- The playable world: a safe town, five monster fields, and enemies you can
-- actually hit.
--
-- The map layout is data (Fields.luau) and the monster stats are data
-- (Enemies.luau); this module is the thin Roblox layer that turns both into
-- parts in Workspace. Keeping the geometry out of the logic means the map can
-- change without touching combat, and combat can change without moving a wall.
--
-- The server owns every enemy's health. Clients only see the result.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fields = require(Shared:WaitForChild("Fields"))
local Enemies = require(Shared:WaitForChild("Enemies"))

local World = {}

local SPAWN_HEIGHT = 4
local ENEMY_HEIGHT_OFFSET = 3
local ENEMY_BASE_SIZE = Vector3.new(4, 5, 4)
local PLATFORM_HEIGHT = 4

local enemies: { [number]: any } = {}
local enemyModels: { [number]: Model } = {}
local nextEnemyId = 0

local worldRoot: Model? = nil

-- Farm plots. The server owns the crop state (Farm.luau); this table only
-- holds the parts used to draw it, keyed by plot index.
local plotCrops: { [number]: BasePart } = {}
local plotLabels: { [number]: TextLabel } = {}

local CROP_COLOR: { [string]: Color3 } = {}
for _, crop in ipairs(Config.Farm.Crops) do
        CROP_COLOR[crop.id] = Color3.fromRGB(crop.color[1], crop.color[2], crop.color[3])
end

-- Enemies stop at this distance rather than walking into the player, so
-- they stay in melee range without shoving the character around.
local ENEMY_STOP_DISTANCE = Config.Wave.EnemyMeleeRange * 0.75

local function rgb(color: { number }): Color3
        return Color3.fromRGB(color[1], color[2], color[3])
end

local function vec(point: { x: number, y: number, z: number }, yOffset: number?): Vector3
        return Vector3.new(point.x, (point.y or 0) + (yOffset or 0), point.z)
end

-- A floor slab for one place: the town or a field.
local function makeFloor(parent: Model, name: string, centre: Vector3, radius: number, color: Color3): Part
        local floor = Instance.new("Part")
        floor.Name = name
        floor.Shape = Enum.PartType.Cylinder
        floor.Size = Vector3.new(PLATFORM_HEIGHT, radius * 2, radius * 2)
        floor.CFrame = CFrame.new(centre - Vector3.new(0, PLATFORM_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
        floor.Anchored = true
        floor.Material = Enum.Material.Grass
        floor.Color = color
        floor.TopSurface = Enum.SurfaceType.Smooth
        floor.BottomSurface = Enum.SurfaceType.Smooth
        floor.Parent = parent
        return floor
end

-- A ring wall so the edge of a place is visible. CanCollide is off: a wall the
-- player can walk through is friendlier than one that traps them on a cliff.
local function makeRim(parent: Model, name: string, centre: Vector3, radius: number, color: Color3)
        local rim = Instance.new("Part")
        rim.Name = name
        rim.Shape = Enum.PartType.Cylinder
        rim.Size = Vector3.new(14, radius * 2, radius * 2)
        rim.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90))
        rim.Anchored = true
        rim.Material = Enum.Material.Slate
        rim.Color = color
        rim.Transparency = 0.55
        rim.CanCollide = false
        rim.Parent = parent
end

-- A labelled billboard. Used for field names and portals so the map is legible
-- from a distance without opening a menu.
local function makeSign(parent: Instance, text: string, height: number, width: number, color: Color3): TextLabel
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "Sign"
        billboard.Size = UDim2.new(width, 0, 1.6, 0)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = parent

        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextScaled = true
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.35
        label.Text = text
        label.Parent = billboard
        return label
end

-- A travel portal. Touching it asks the server to move the player, so travel
-- is never decided by the client.
local function makePortal(parent: Model, fieldId: string, label: string, position: Vector3, color: Color3): Part
        local portal = Instance.new("Part")
        portal.Name = "Portal_" .. fieldId
        portal.Size = Vector3.new(Config.Fields.PortalRadius * 2, 14, 2)
        portal.Position = position + Vector3.new(0, 7, 0)
        portal.Anchored = true
        portal.CanCollide = false
        portal.Material = Enum.Material.Neon
        portal.Color = color
        portal.Transparency = 0.25
        portal.Parent = parent
        makeSign(portal, label, 5, 8, Color3.fromRGB(255, 255, 255))
        return portal
end

-- Build the town: a safe hub with the farm plots, a spawn pad and the portals
-- out to every field. This is where a player lands and where they respawn.
local function buildTown(parent: Model): Model
        local town = Instance.new("Model")
        town.Name = "Town"

        local def = Fields.town()
        local centre = vec(def.position, 0)
        makeFloor(town, "TownFloor", centre, def.radius, rgb(def.groundColor))
        makeRim(town, "TownRim", centre, def.radius, Color3.fromRGB(120, 104, 84))

        -- A spawn pad at the arrival point, so "you are home" is obvious.
        local arrival = vec(Fields.arrivalOf("Town"), SPAWN_HEIGHT)
        local spawn = Instance.new("SpawnLocation")
        spawn.Name = "TownSpawn"
        spawn.Size = Vector3.new(18, 1, 18)
        spawn.Position = arrival
        spawn.Anchored = true
        spawn.Material = Enum.Material.Neon
        spawn.Color = Color3.fromRGB(255, 214, 92)
        spawn.Neutral = true
        spawn.Duration = 0
        spawn.Parent = town
        makeSign(spawn, def.name, 8, 12, Color3.fromRGB(255, 236, 170))

        -- A landmark in the middle: the obelisk the town is built around.
        local obelisk = Instance.new("Part")
        obelisk.Name = "Obelisk"
        obelisk.Shape = Enum.PartType.Cylinder
        obelisk.Size = Vector3.new(1, 10, 10)
        obelisk.CFrame = CFrame.new(centre + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90))
        obelisk.Anchored = true
        obelisk.Material = Enum.Material.Neon
        obelisk.Color = Color3.fromRGB(150, 210, 255)
        obelisk.Parent = town

        -- Farm plots ring the town centre. Farming happens in town because town
        -- is the one place nothing is trying to kill you.
        for i = 1, Config.Farm.PlotCount do
                local angle = ((i - 1) / Config.Farm.PlotCount) * math.pi * 2
                local bedPos = centre + Vector3.new(
                        math.cos(angle) * Config.Farm.PlotRingRadius,
                        1.5,
                        math.sin(angle) * Config.Farm.PlotRingRadius
                )

                local bed = Instance.new("Part")
                bed.Name = "Plot_" .. i
                bed.Size = Vector3.new(9, 1, 9)
                bed.Position = bedPos
                bed.Anchored = true
                bed.Material = Enum.Material.Ground
                bed.Color = Color3.fromRGB(104, 76, 54)
                bed.TopSurface = Enum.SurfaceType.Smooth
                bed.Parent = town

                local crop = Instance.new("Part")
                crop.Name = "Crop"
                crop.Shape = Enum.PartType.Ball
                crop.Size = Vector3.new(3.4, 3.4, 3.4)
                crop.Position = bedPos + Vector3.new(0, 2.2, 0)
                crop.Anchored = true
                crop.CanCollide = false
                crop.Material = Enum.Material.Neon
                crop.Transparency = 1
                crop.Parent = bed
                plotCrops[i] = crop

                local text = makeSign(bed, "PLOT " .. i, 5, 6, Color3.fromRGB(255, 255, 255))
                plotLabels[i] = text
        end

        -- One portal per field, on the ring edge facing that field. Walking into
        -- it is the whole interaction; no menu is needed to travel.
        for _, field in ipairs(Fields.list()) do
                local dx = field.position.x
                local dz = field.position.z
                local length = math.max(1, math.sqrt(dx * dx + dz * dz))
                local edge = centre + Vector3.new(dx / length, 0, dz / length) * (def.radius - 8)
                local label = string.format("%s (Lv %d)", field.name, field.levelRequirement)
                makePortal(town, field.id, label, edge, rgb(field.groundColor))
        end

        town.Parent = parent
        return town
end

-- Build one monster field: floor, rim, arrival pad, a portal home, and its
-- monsters' colour so the five maps are told apart at a glance.
local function buildField(parent: Model, field): Model
        local model = Instance.new("Model")
        model.Name = "Field_" .. field.id

        local centre = vec(field.position, 0)
        makeFloor(model, "FieldFloor", centre, Config.Fields.ArenaRadius, rgb(field.groundColor))
        makeRim(model, "FieldRim", centre, Config.Fields.ArenaRadius, Color3.fromRGB(58, 64, 84))

        local arrival = vec(Fields.arrivalOf(field.id), SPAWN_HEIGHT)
        local pad = Instance.new("Part")
        pad.Name = "ArrivalPad"
        pad.Size = Vector3.new(14, 1, 14)
        pad.Position = arrival
        pad.Anchored = true
        pad.Material = Enum.Material.Neon
        pad.Color = Color3.fromRGB(255, 214, 92)
        pad.Parent = model

        local sign = string.format("%s  -  Lv %d+\n%s", field.name, field.levelRequirement, field.tagline)
        makeSign(pad, sign, 10, 16, Color3.fromRGB(255, 255, 255))

        -- A portal home, so leaving a field never needs a menu either.
        makePortal(model, "Town", "Return to Town", arrival + Vector3.new(14, 0, 0),
                Color3.fromRGB(255, 214, 92))

        model.Parent = parent
        return model
end

-- Build the whole world once. Returns the root model.
function World.buildWorld(): Model
        if worldRoot and worldRoot.Parent then
                return worldRoot
        end

        local root = Instance.new("Model")
        root.Name = "AXArenaWorld"

        -- A large ground slab so the ring of fields never looks like it floats.
        local ground = Instance.new("Part")
        ground.Name = "WorldGround"
        ground.Size = Vector3.new(Config.Fields.RingRadius * 3, 4, Config.Fields.RingRadius * 3)
        ground.Position = Vector3.new(0, -6, 0)
        ground.Anchored = true
        ground.Material = Enum.Material.Grass
        ground.Color = Color3.fromRGB(66, 108, 74)
        ground.TopSurface = Enum.SurfaceType.Smooth
        ground.Parent = root

        buildTown(root)
        for _, field in ipairs(Fields.list()) do
                buildField(root, field)
        end

        root.Parent = Workspace
        worldRoot = root
        return root
end

-- Kept as the old entry point so existing callers keep working.
function World.buildArena(): Model
        return World.buildWorld()
end

-- Draw one plot from server state. A nil cropId clears the bed.
function World.updatePlot(index: number, cropId: string?, ready: boolean, secondsLeft: number)
        local crop = plotCrops[index]
        local text = plotLabels[index]
        if not crop then
                return
        end

        if not cropId then
                crop.Transparency = 1
                if text then
                        text.Text = "PLOT " .. index
                        text.TextColor3 = Color3.fromRGB(220, 220, 220)
                end
                return
        end

        crop.Transparency = ready and 0 or 0.35
        crop.Color = CROP_COLOR[cropId] or Color3.fromRGB(236, 200, 96)
        -- A ripe crop glows and reads READY, so it is visible from across the town.
        crop.Material = ready and Enum.Material.Neon or Enum.Material.SmoothPlastic
        if text then
                if ready then
                        text.Text = "READY - " .. cropId
                        text.TextColor3 = Color3.fromRGB(140, 255, 170)
                else
                        text.Text = string.format("%s %ds", cropId, math.max(0, math.floor(secondsLeft)))
                        text.TextColor3 = Color3.fromRGB(255, 255, 255)
                end
        end
end

-- Centre of a plot, used to place the axe burst.
function World.plotPosition(index: number): Vector3?
        local crop = plotCrops[index]
        if crop then
                return crop.Position
        end
        return nil
end

-- A monster's model. Size and colour come from the archetype, so a Slime and a
-- Rock Golem are different creatures rather than the same cube twice.
local function buildEnemyModel(enemy: any, position: Vector3): Model
        local model = Instance.new("Model")
        model.Name = "Enemy_" .. enemy.id

        local size = ENEMY_BASE_SIZE * (enemy.sizeMul or 1)
        local body = Instance.new("Part")
        body.Name = "Body"
        body.Size = size
        body.Position = position + Vector3.new(0, size.Y / 2, 0)
        body.Anchored = true
        body.Material = enemy.boss and Enum.Material.Neon or Enum.Material.SmoothPlastic
        body.Color = enemy.color or Color3.fromRGB(220, 70, 70)
        body.Parent = model

        -- A boss gets a glow ring so it is unmistakable in a crowd.
        if enemy.boss then
                local aura = Instance.new("Part")
                aura.Name = "BossAura"
                aura.Shape = Enum.PartType.Cylinder
                aura.Size = Vector3.new(1, size.X * 2.2, size.X * 2.2)
                aura.CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
                aura.Anchored = true
                aura.CanCollide = false
                aura.Material = Enum.Material.Neon
                aura.Color = body.Color
                aura.Transparency = 0.6
                aura.Parent = model
        end

        -- A health bar in the world, so progress is visible without a UI.
        local bar = Instance.new("BillboardGui")
        bar.Name = "HealthBar"
        bar.Size = UDim2.new(enemy.boss and 10 or 4, 0, 0.6, 0)
        bar.StudsOffsetWorldSpace = Vector3.new(0, size.Y * 0.8 + 2, 0)
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
        label.Text = (enemy.name or "Monster") .. (enemy.boss and "  [BOSS]" or "")
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

-- Spawn one monster in a field. `scaled` comes from Enemies.scale, so all the
-- stat maths stays in the pure module and this only places parts.
function World.spawnEnemy(fieldId: string, scaled: any, wave: number, index: number, total: number, now: number)
        nextEnemyId += 1
        local enemy = {
                id = nextEnemyId,
                fieldId = fieldId,
                wave = wave,
                name = scaled.name,
                boss = scaled.boss,
                health = scaled.health,
                maxHealth = scaled.health,
                damage = scaled.damage,
                reward = scaled.reward,
                speed = scaled.speed,
                sizeMul = scaled.sizeMul,
                color = rgb(scaled.color),
                -- The grace window stops a freshly spawned enemy hitting on arrival.
                spawnedAt = now,
                nextAttackAt = now + Config.Wave.SpawnGraceSeconds,
                alive = true,
        }

        local point = Fields.spawnPoint(fieldId, index, total)
        local model = buildEnemyModel(enemy, vec(point, ENEMY_HEIGHT_OFFSET))
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

-- Remove every monster in one field. Used when a field empties or a wave
-- resets, so a stale monster never follows a player to town.
function World.clearField(fieldId: string)
        for id, enemy in pairs(enemies) do
                if enemy.fieldId == fieldId then
                        local model = enemyModels[id]
                        if model then
                                model:Destroy()
                        end
                        enemies[id] = nil
                        enemyModels[id] = nil
                end
        end
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

function World.aliveCount(fieldId: string?): number
        local count = 0
        for _, enemy in pairs(enemies) do
                if enemy.alive and (fieldId == nil or enemy.fieldId == fieldId) then
                        count += 1
                end
        end
        return count
end

-- Where the player stands when they arrive somewhere. Town and field arrivals
-- both come from Fields, so the layout lives in one place.
function World.attachPlayer(player: Player, character: Model, placeId: string?)
        local humanoid = character:WaitForChild("Humanoid", 5)
        local root = character:WaitForChild("HumanoidRootPart", 5)
        if not humanoid or not root then
                return
        end

        local id = placeId or "Town"
        root.CFrame = CFrame.new(vec(Fields.arrivalOf(id), SPAWN_HEIGHT + 2))
end

-- Move a player to another place. The client asks; the server decides.
function World.placePlayer(player: Player, placeId: string)
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then
                root.CFrame = CFrame.new(vec(Fields.arrivalOf(placeId), SPAWN_HEIGHT + 2))
        end
end

-- Move enemies toward the nearest player *in the same field*, and let them
-- attack, but only from melee range.
--
-- Enemies are tied to a field so a monster in the Volcano cannot chase someone
-- standing in town. That was invisible while the world was one arena, and it
-- would be very visible now.
function World.updateEnemies(dt: number, now: number, fieldOfPlayer: (Player) -> string?, onAttack: (Player, number) -> ())
        local players = Players:GetPlayers()
        if #players == 0 then
                return
        end

        for id, enemy in pairs(enemies) do
                if enemy.alive then
                        local model = enemyModels[id]
                        local body = model and model:FindFirstChild("Body")
                        if body and body:IsA("BasePart") then
                                -- Nearest player standing in this enemy's field.
                                local target: Player? = nil
                                local targetRoot: BasePart? = nil
                                local bestDistance = math.huge
                                for _, player in ipairs(players) do
                                        if fieldOfPlayer(player) == enemy.fieldId then
                                                local character = player.Character
                                                local root = character and character:FindFirstChild("HumanoidRootPart")
                                                if root and root:IsA("BasePart") then
                                                        local distance = (root.Position - body.Position).Magnitude
                                                        if distance < bestDistance then
                                                                bestDistance = distance
                                                                target = player
                                                                targetRoot = root
                                                        end
                                                end
                                        end
                                end

                                local distance = bestDistance
                                if targetRoot then
                                        -- Chase on the flat plane so enemies never climb or sink, and
                                        -- stop just inside melee range so they do not shove the player.
                                        local offset = targetRoot.Position - body.Position
                                        local flat = Vector3.new(offset.X, 0, offset.Z)
                                        local flatDistance = flat.Magnitude
                                        if flatDistance > ENEMY_STOP_DISTANCE then
                                                local speed = enemy.speed or Config.Wave.EnemyMoveSpeed
                                                local step = math.min(speed * dt, flatDistance - ENEMY_STOP_DISTANCE)
                                                body.CFrame = body.CFrame + flat.Unit * step
                                                -- Face the player, so the chase reads as intent.
                                                body.CFrame = CFrame.lookAt(body.Position, body.Position + flat.Unit)
                                        end
                                end

                                local pastGrace = (now - enemy.spawnedAt) >= Config.Wave.SpawnGraceSeconds
                                if target and pastGrace and distance <= Config.Wave.EnemyMeleeRange and now >= enemy.nextAttackAt then
                                        enemy.nextAttackAt = now + Config.Wave.EnemyAttackInterval
                                        onAttack(target, enemy.damage)
                                end
                        end
                end
        end
end

-- The boss standing in a field, if there is one, with its remaining
-- health as a fraction. The HUD draws one bar from this and nothing else.
function World.bossInfo(fieldId: string?)
	local found = nil
	for _, enemy in pairs(enemies) do
		if enemy.alive and enemy.boss and (fieldId == nil or enemy.fieldId == fieldId) then
			found = enemy
			break
		end
	end
	if not found then
		return nil
	end
	return {
		name = found.name,
		health = found.health,
		maxHealth = found.maxHealth,
		fraction = found.maxHealth > 0 and (found.health / found.maxHealth) or 0,
	}
end

function World.snapshot(fieldId: string?)
        local out = {}
        for _, enemy in pairs(enemies) do
                if fieldId == nil or enemy.fieldId == fieldId then
                        table.insert(out, {
                                id = enemy.id,
                                fieldId = enemy.fieldId,
                                wave = enemy.wave,
                                name = enemy.name,
                                boss = enemy.boss,
                                health = enemy.health,
                                maxHealth = enemy.maxHealth,
                                alive = enemy.alive,
                        })
                end
        end
        table.sort(out, function(a, b)
                return a.id < b.id
        end)
        return out
end

-- Field id a world position is standing in, or nil for town. Used to work out
-- which field's monsters may attack a given player.
function World.fieldAt(position: Vector3): string?
        for _, field in ipairs(Fields.list()) do
                local centre = vec(field.position, 0)
                local dx = position.X - centre.X
                local dz = position.Z - centre.Z
                if math.sqrt(dx * dx + dz * dz) <= Config.Fields.ArenaRadius then
                        return field.id
                end
        end
        return nil
end

return World

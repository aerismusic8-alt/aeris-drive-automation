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
local Items = require(Shared:WaitForChild("Items"))
local MonsterShapes = require(Shared:WaitForChild("MonsterShapes"))
local ClassLook = require(Shared:WaitForChild("ClassLook"))
local Scenery = require(Shared:WaitForChild("Scenery"))
local Atmosphere = require(Shared:WaitForChild("Atmosphere"))
local Text = require(Shared:WaitForChild("Text"))

local World = {}

local SPAWN_HEIGHT = 4
local ENEMY_HEIGHT_OFFSET = 3
-- How far above a grounded monster a flying one drifts, in studs. Enough to
-- clear a hedge, not so much that a melee swing cannot reach it.
local HOVER_LIFT = 4
local PLATFORM_HEIGHT = 4

local enemies: { [number]: any } = {}
local enemyModels: { [number]: Model } = {}
local nextEnemyId = 0

local worldRoot: Model? = nil

-- Farm plots. The server owns the crop state (Farm.luau); this table only
-- holds the parts used to draw it, keyed by plot index.
local plotCrops: { [number]: BasePart } = {}
local plotLabels: { [number]: TextLabel } = {}

-- Dropped items on the ground, keyed by drop id. Each is a small glowing part
-- with a billboard, so loot is visible without opening the bag.
type Drop = {
        id: number,
        itemId: string,
        count: number,
        fieldId: string?,
        position: Vector3,
        expiresAt: number,
        model: Model,
}
local drops: { [number]: Drop } = {}
local nextDropId = 0

-- Set by the server: the function a portal touch calls to move a player. Kept
-- as a callback so World never has to know how travel is validated.
local portalTravel: ((Player, string) -> ())? = nil

function World.setPortalHandler(handler: (Player, string) -> ())
        portalTravel = handler
end

-- Floating damage numbers, keyed by player. Each player only sees their own,
-- which keeps the screen readable in a crowded field.
local damageGuis: { [number]: BillboardGui } = {}

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

        -- Walking into a portal is the travel interaction. The touch only *asks*;
        -- the server still validates the level lock and applies the cooldown.
        portal.Touched:Connect(function(other)
                if not portalTravel then
                        return
                end
                local character = other and other.Parent
                local player = character and Players:GetPlayerFromCharacter(character)
                if player then
                        portalTravel(player, fieldId)
                end
        end)

        return portal
end

-- Apply a place's look to the world. Roblox has one global Lighting service,
-- so the look follows the player: entering a field re-lights the world for
-- that field. This is what makes the maps feel like different places.
local applyAtmosphere: (string) -> ()

local function applyLook(placeId: string)
        local look = Fields.look(placeId)
        local Lighting = game:GetService("Lighting")

        Lighting.Ambient = rgb(look.ambient)
        Lighting.OutdoorAmbient = rgb(look.outdoorAmbient)
        Lighting.Brightness = look.brightness
        Lighting.FogColor = rgb(look.fog)
        Lighting.FogEnd = look.fogEnd
        Lighting.FogStart = look.fogEnd * 0.25
        Lighting.ClockTime = placeId == "Void" and 0 or (placeId == "Heaven" and 12 or 14)
        Lighting.GlobalShadows = true

        -- The air is part of the look, so it is applied in the same call: a
        -- caller that re-lights a place can never forget to re-grade it.
        applyAtmosphere(placeId)
end

World.applyLook = applyLook

-- The colour a scenery role is drawn in for this place.
local function sceneryColor(role: string, palette: { [string]: { number } }): Color3
        return rgb(palette[role] or { 200, 200, 200 })
end

-- A Roblox material from its name, so a bad name degrades to plastic instead
-- of erroring inside the world build.
local function material(name: string): Enum.Material
        local ok, value = pcall(function()
                return Enum.Material[name]
        end)
        if ok and value then
                return value
        end
        return Enum.Material.SmoothPlastic
end

-- A part from a scenery recipe. Scenery describes a prop in prop space, the
-- same convention as a monster, so the transform here is the same one.
local function sceneryPart(spec: any, palette: { [string]: { number } }): BasePart
        local instance: BasePart
        if spec.shape == "Ball" then
                instance = Instance.new("Part")
                instance.Shape = Enum.PartType.Ball
        elseif spec.shape == "Cylinder" then
                instance = Instance.new("Part")
                instance.Shape = Enum.PartType.Cylinder
        elseif spec.shape == "Wedge" then
                instance = Instance.new("WedgePart")
        elseif spec.shape == "CornerWedge" then
                instance = Instance.new("CornerWedgePart")
        else
                instance = Instance.new("Part")
        end

        instance.Name = spec.name
        local size = spec.size
        instance.Size = Vector3.new(size[1], size[2], size[3])
        instance.Anchored = true
        instance.Material = material(Scenery.materialFor(spec.color))
        instance.Color = sceneryColor(spec.color, palette)
        -- Water and glass are the only see-through props; the default 0 keeps
        -- everything else solid-looking.
        if spec.alpha then
                instance.Transparency = spec.alpha
        end
        instance.TopSurface = Enum.SurfaceType.Smooth
        instance.BottomSurface = Enum.SurfaceType.Smooth

        local at = spec.at
        local rotation = CFrame.new()
        if spec.rot then
                rotation = CFrame.Angles(math.rad(spec.rot[1]), math.rad(spec.rot[2]), math.rad(spec.rot[3]))
        end
        instance.CFrame = rotation * CFrame.new(Vector3.new(at[1], at[2], at[3]))
        return instance
end

-- Scatter one place's scenery into the world.
--
-- keepOut is what stops a tree growing through the spawn pad, a portal or a
-- farm plot: the caller names the circles to protect and the scatter respects
-- them. Solid props collide so a forest is something you walk around, but the
-- model's parts are CanQuery off so they never block the axe or a tap.
local function buildScenery(parent: Model, placeId: string, centre: Vector3, radius: number, keepOut: { any })
        local palette = Scenery.palette(placeId)
        local placements = Scenery.scatter(placeId, { x = centre.X, y = centre.Y, z = centre.Z }, radius,
                Scenery.seedFor(placeId), keepOut)

        local group = Instance.new("Model")
        group.Name = "Scenery"

        for index, spot in ipairs(placements) do
                local prop = Scenery.build(spot.kind, spot.size)
                if prop then
                        local model = Instance.new("Model")
                        model.Name = string.format("%s_%d", spot.kind, index)
                        for _, spec in ipairs(prop.parts) do
                                local piece = sceneryPart(spec, palette)
                                piece.CanCollide = spot.solid
                                piece.CanQuery = false
                                piece.CanTouch = false
                                piece.Parent = model
                        end
                        model:PivotTo(CFrame.new(spot.x, spot.y, spot.z) * CFrame.Angles(0, math.rad(spot.yaw), 0))
                        model.Parent = group
                end
        end

        group.Parent = parent
        return group
end

-- Turn a place's landmarks into keep-out circles, so the scatter leaves room
-- for them. A landmark's own footprint is the radius, trimmed slightly so the
-- scatter is not starved; props that are a floor rather than an obstacle (the
-- paving) reserve nothing, so props may stand on them.
-- Scenery is pure Luau, so it takes plain { x, y, z } tables, never a Vector3.
-- The world works in Vector3, so the arrival point is converted once here
-- rather than at each call. Passing the Vector3 straight through read as
-- arrival.x == nil and threw inside Scenery, which killed the server script
-- before it could serve a single player.
local function landmarkOpts(opts: any): any
        if not opts then
                return nil
        end
        local out = {}
        for key, value in pairs(opts) do
                out[key] = value
        end
        if opts.arrival then
                out.arrival = { x = opts.arrival.X, y = opts.arrival.Y, z = opts.arrival.Z }
        end
        return out
end

local function reserveLandmarks(
        keepOut: { any },
        placeId: string,
        centre: Vector3,
        radius: number,
        opts: any
)
        for _, spot in ipairs(Scenery.landmarks(placeId, { x = centre.X, y = centre.Y, z = centre.Z }, radius, landmarkOpts(opts))) do
                local def = Scenery.kindDef(spot.kind)
                if not def or def.reserve ~= false then
                        local prop = Scenery.build(spot.kind, spot.size)
                        local footprint = prop and prop.footprint or 12
                        table.insert(keepOut, { x = spot.x, z = spot.z, radius = footprint * 0.6 })
                end
        end
end

-- Build the structural props for a place: the fountain, the walls and gates,
-- the church, the shrines and the paved approaches.
--
-- These are placed on purpose by Scenery.landmarks rather than scattered, and
-- they are built after the scatter so the scatter can be told to keep clear of
-- them. Returns the circles they occupy, so the caller can add them to the
-- scatter's keep-out list on the next build.
local function buildLandmarks(parent: Model, placeId: string, centre: Vector3, radius: number, opts: any)
        local palette = Scenery.palette(placeId)
        local placements = Scenery.landmarks(placeId, { x = centre.X, y = centre.Y, z = centre.Z }, radius, landmarkOpts(opts))

        local group = Instance.new("Model")
        group.Name = "Landmarks"

        for index, spot in ipairs(placements) do
                local prop = Scenery.build(spot.kind, spot.size)
                if prop then
                        local model = Instance.new("Model")
                        model.Name = string.format("%s_%d", spot.kind, index)
                        for _, spec in ipairs(prop.parts) do
                                local piece = sceneryPart(spec, palette)
                                piece.CanCollide = spot.solid
                                piece.CanQuery = false
                                piece.CanTouch = false
                                piece.Parent = model
                        end
                        model:PivotTo(CFrame.new(spot.x, spot.y, spot.z) * CFrame.Angles(0, math.rad(spot.yaw), 0))
                        model.Parent = group
                end
        end

        group.Parent = parent
        return group
end

-- The atmosphere effects. Roblox keeps one Lighting, so these are rebuilt per
-- place rather than per map, exactly like applyLook.
function applyAtmosphere(placeId: string)
        local profile = Atmosphere.profileFor(placeId)
        local Lighting = game:GetService("Lighting")

        local atmosphere = Lighting:FindFirstChild("AXAtmosphere")
        if not atmosphere then
                atmosphere = Instance.new("Atmosphere")
                atmosphere.Name = "AXAtmosphere"
                atmosphere.Parent = Lighting
        end
        atmosphere.Density = profile.density
        atmosphere.Offset = profile.offset
        atmosphere.Color = rgb(profile.color)
        atmosphere.Decay = rgb(profile.decay)
        atmosphere.Glare = profile.glare
        atmosphere.Haze = profile.haze

        local clouds = Lighting:FindFirstChild("AXClouds")
        if not clouds then
                clouds = Instance.new("Clouds")
                clouds.Name = "AXClouds"
                clouds.Parent = Lighting
        end
        clouds.Cover = profile.cloudCover
        clouds.Density = profile.cloudDensity
        clouds.Color = rgb(profile.cloudColor)

        local bloom = Lighting:FindFirstChild("AXBloom")
        if not bloom then
                bloom = Instance.new("BloomEffect")
                bloom.Name = "AXBloom"
                bloom.Parent = Lighting
        end
        bloom.Intensity = profile.bloomIntensity
        bloom.Size = profile.bloomSize
        bloom.Threshold = profile.bloomThreshold

        local grade = Lighting:FindFirstChild("AXGrade")
        if not grade then
                grade = Instance.new("ColorCorrectionEffect")
                grade.Name = "AXGrade"
                grade.Parent = Lighting
        end
        grade.Brightness = profile.brightness - 1
        grade.Contrast = profile.contrast
        grade.Saturation = profile.saturation
        grade.TintColor = rgb(profile.tint)

        local rays = Lighting:FindFirstChild("AXSunRays")
        if profile.sunRays > 0 then
                if not rays then
                        rays = Instance.new("SunRaysEffect")
                        rays.Name = "AXSunRays"
                        rays.Parent = Lighting
                end
                rays.Intensity = profile.sunRays
                rays.Spread = 0.9
        elseif rays then
                rays:Destroy()
        end
end

World.applyAtmosphere = applyAtmosphere

-- A ring of floating light motes around a place. Purely visual, but it is what
-- makes a map read as "somewhere" instead of a lit disc.
local function makeMotes(parent: Instance, centre: Vector3, radius: number, accent: Color3, count: number)
        -- The emitter lives on an invisible box covering the place, so the
        -- motes stay inside it instead of drifting across the whole world.
        local volume = Instance.new("Part")
        volume.Name = "MoteVolume"
        volume.Size = Vector3.new(radius * 1.6, 40, radius * 1.6)
        volume.Position = centre + Vector3.new(0, 18, 0)
        volume.Anchored = true
        volume.CanCollide = false
        volume.Transparency = 1
        volume.Parent = parent

        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "Motes"
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Rate = count
        emitter.Lifetime = NumberRange.new(4, 7)
        emitter.Speed = NumberRange.new(1, 3)
        emitter.SpreadAngle = Vector2.new(180, 180)
        emitter.Color = ColorSequence.new(accent)
        emitter.LightEmission = 1
        emitter.LightInfluence = 0
        emitter.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.5, 1.1),
                NumberSequenceKeypoint.new(1, 0),
        })
        emitter.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0.35),
                NumberSequenceKeypoint.new(1, 1),
        })
        -- Motes drift upward and fade, which reads as magic rather than debris.
        emitter.Acceleration = Vector3.new(0, 1.2, 0)
        emitter.Parent = volume
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
        makeSign(spawn, Text.placeName("Town"), 8, 12, Color3.fromRGB(255, 236, 170))

        -- The town centre is the market fountain, built by buildLandmarks from
        -- the Scenery catalogue. It used to be a bare neon obelisk, which read
        -- as a marker rather than as a town square.

        local townLook = Fields.look("Town")
        if townLook.motes then
                makeMotes(town, centre, def.radius, rgb(townLook.accent), 30)
        end

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

                local text = makeSign(bed, Text.get("plot", i), 5, 6, Color3.fromRGB(255, 255, 255))
                plotLabels[i] = text
        end

        -- One portal per field, on the ring edge facing that field. Walking into
        -- it is the whole interaction; no menu is needed to travel.
        local keepOut: { any } = {
                -- The spawn pad and the obelisk, so nothing grows on the arrival.
                { x = centre.X, z = centre.Z, radius = 16 },
                { x = arrival.X, z = arrival.Z, radius = 22 },
        }
        for _, field in ipairs(Fields.list()) do
                local dx = field.position.x
                local dz = field.position.z
                local length = math.max(1, math.sqrt(dx * dx + dz * dz))
                local edge = centre + Vector3.new(dx / length, 0, dz / length) * (def.radius - 8)
                local label = string.format("%s (%s %d)", Text.placeName(field.id), Text.get("level"),
                        field.levelRequirement)
                makePortal(town, field.id, label, edge, rgb(Fields.look(field.id).accent))
                -- Every portal keeps a clear approach, so a tree never stands
                -- between the player and the map they are trying to enter.
                table.insert(keepOut, { x = edge.X, z = edge.Z, radius = 20 })
        end

        -- The farm plots are gameplay, so nothing may stand on one.
        for i = 1, Config.Farm.PlotCount do
                local angle = ((i - 1) / Config.Farm.PlotCount) * math.pi * 2
                table.insert(keepOut, {
                        x = centre.X + math.cos(angle) * Config.Farm.PlotRingRadius,
                        z = centre.Z + math.sin(angle) * Config.Farm.PlotRingRadius,
                        radius = 12,
                })
        end

        -- The structural props are placed on purpose, and the scatter must not
        -- grow through them. They are reserved here, before the scatter runs,
        -- so a tree never ends up inside the church or on the fountain.
        local gateAngles: { number } = {}
        for _, field in ipairs(Fields.list()) do
                table.insert(gateAngles, math.atan2(field.position.z, field.position.x))
        end
        reserveLandmarks(keepOut, "Town", centre, def.radius, { gates = gateAngles })

        buildScenery(town, "Town", centre, def.radius, keepOut)
        buildLandmarks(town, "Town", centre, def.radius, { gates = gateAngles })

        town.Parent = parent
        return town
end

-- Build one monster field: floor, rim, arrival pad, a portal home, and its
-- monsters' colour so the five maps are told apart at a glance.
local function buildField(parent: Model, field): Model
        local model = Instance.new("Model")
        model.Name = "Field_" .. field.id

        local centre = vec(field.position, 0)
        local look = Fields.look(field.id)
        makeFloor(model, "FieldFloor", centre, Config.Fields.ArenaRadius, rgb(field.groundColor))
        -- The rim glows in the field's accent colour, so each map has its own
        -- signature light even from a distance.
        makeRim(model, "FieldRim", centre, Config.Fields.ArenaRadius, rgb(look.accent))
        if look.motes then
                makeMotes(model, centre, Config.Fields.ArenaRadius, rgb(look.accent), 40)
        end

        local arrival = vec(Fields.arrivalOf(field.id), SPAWN_HEIGHT)
        local pad = Instance.new("Part")
        pad.Name = "ArrivalPad"
        pad.Size = Vector3.new(14, 1, 14)
        pad.Position = arrival
        pad.Anchored = true
        pad.Material = Enum.Material.Neon
        pad.Color = Color3.fromRGB(255, 214, 92)
        pad.Parent = model

        local sign = string.format("%s  -  %s %d+\n%s", Text.placeName(field.id), Text.get("level"),
                        field.levelRequirement, Text.tagline(field.id))
        makeSign(pad, sign, 10, 16, Color3.fromRGB(255, 255, 255))

        -- A portal home, so leaving a field never needs a menu either. It sits
        -- far enough to the side to clear the gate arch the player arrives under.
        local home = arrival + Vector3.new(26, 0, 0)
        makePortal(model, "Town", Text.get("returnToTown"), home, Color3.fromRGB(255, 214, 92))

        -- The arrival pad and the portal home stay clear, so a monster field
        -- never drops a tree on the spot the player lands on.
        local keepOut: { any } = {
                { x = arrival.X, z = arrival.Z, radius = 18 },
                { x = home.X, z = home.Z, radius = 16 },
        }

        -- Monsters spawn on a ring, so the ring itself is protected. They are
        -- anchored and moved by CFrame, which means a prop cannot trap one, but
        -- a monster standing inside a tree still looks broken. Sixteen points
        -- per ring covers any wave size without carving the map hollow.
        local ringRadius = Config.Fields.SpawnRadius
        for _, factor in ipairs({ 0.7, 1.0 }) do
                local radius = ringRadius * factor
                for step = 1, 16 do
                        local angle = (step - 1) / 16 * math.pi * 2
                        table.insert(keepOut, {
                                x = centre.X + math.cos(angle) * radius,
                                z = centre.Z + math.sin(angle) * radius,
                                radius = 8,
                        })
                end
        end

        -- The field's own landmarks (its gate, landmark and paved approach) are
        -- reserved before the scatter, so a tree never grows through the arch
        -- the player walks in under.
        reserveLandmarks(keepOut, field.id, centre, Config.Fields.ArenaRadius, { arrival = arrival })

        buildScenery(model, field.id, centre, Config.Fields.ArenaRadius, keepOut)
        buildLandmarks(model, field.id, centre, Config.Fields.ArenaRadius, { arrival = arrival })

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
        -- The world starts lit as the town. Entering a field re-lights it.
        applyLook("Town")
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
                        text.Text = Text.get("plot", index)
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
                        text.Text = Text.get("ready") .. " - " .. Text.cropName(cropId)
                        text.TextColor3 = Color3.fromRGB(140, 255, 170)
                else
                        text.Text = string.format("%s %ds", Text.cropName(cropId), math.max(0, math.floor(secondsLeft)))
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

-- A monster's model, built from its archetype's silhouette. A recipe is a list
-- of parts in creature space: the origin is the ground, +Y is up, -Z is the way
-- the creature faces. The whole recipe is scaled by the monster's sizeMul, so
-- one shape serves a normal spawn and a boss without a second drawing.
local function buildPart(spec: any, color: Color3, scale: number): BasePart
        local instance: BasePart
        if spec.shape == "Ball" then
                instance = Instance.new("Part")
                instance.Shape = Enum.PartType.Ball
        elseif spec.shape == "Cylinder" then
                instance = Instance.new("Part")
                instance.Shape = Enum.PartType.Cylinder
        elseif spec.shape == "Wedge" then
                instance = Instance.new("WedgePart")
        else
                instance = Instance.new("Part")
        end

        instance.Name = spec.name
        local size = spec.size
        instance.Size = Vector3.new(size[1], size[2], size[3]) * scale
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanQuery = false
        instance.CanTouch = false
        instance.Material = Enum.Material.SmoothPlastic
        instance.Color = color

        -- Creature space -> world space. The part's own rotation is applied
        -- first so an angled wing stays angled once the model is placed.
        local at = spec.at
        local offset = Vector3.new(at[1], at[2], at[3]) * scale
        local rotation = CFrame.new()
        if spec.rot then
                rotation = CFrame.Angles(math.rad(spec.rot[1]), math.rad(spec.rot[2]), math.rad(spec.rot[3]))
        end
        instance.CFrame = rotation * CFrame.new(offset)
        return instance
end

-- Resolve a colour role against the monster's own colour, so every monster
-- keeps its identity while the parts that should stand out still do.
local function roleColor(role: string, base: Color3): Color3
        if role == "body" then
                return base
        elseif role == "dark" then
                return base:Lerp(Color3.fromRGB(20, 18, 26), 0.45)
        elseif role == "light" then
                return base:Lerp(Color3.fromRGB(255, 255, 255), 0.45)
        elseif role == "accent" then
                return base:Lerp(Color3.fromRGB(255, 210, 90), 0.5)
        elseif role == "metal" then
                return Color3.fromRGB(198, 205, 218)
        end
        return Color3.fromRGB(24, 24, 30)
end

local function buildEnemyModel(enemy: any, position: Vector3): Model
        local model = Instance.new("Model")
        model.Name = "Enemy_" .. enemy.id

        local scale = enemy.sizeMul or 1
        local base = enemy.color or Color3.fromRGB(220, 70, 70)
        local recipe = MonsterShapes.get(enemy.archetype or enemy.name)

        local parts: { [string]: BasePart } = {}
        local tallest = 0
        for _, spec in ipairs(recipe.parts) do
                local instance = buildPart(spec, roleColor(spec.color, base), scale)
                instance.Parent = model
                parts[spec.name] = instance
                local top = spec.at[2] + spec.size[2] / 2
                if top > tallest then
                        tallest = top
                end
        end

        -- Everything is built around the origin, so move the model to put its
        -- feet on the spawn point.
        local root = parts[recipe.primary] or parts.Body or model:FindFirstChildWhichIsA("BasePart")
        model.PrimaryPart = root
        -- A hovering monster's recipe already sits off the ground, so it is
        -- lifted further to clear the props it flies over. A grounded one is
        -- placed at the spawn point as drawn.
        local lift = MonsterShapes.hovers(enemy.archetype or enemy.name) and HOVER_LIFT or 0
        model:PivotTo(CFrame.new(position + Vector3.new(0, lift, 0)))

        -- The chase code and the kill burst both look up a part called "Body",
        -- and the health bar hangs off it. Rename the pivot so neither has to
        -- learn about recipes.
        if root and root.Name ~= "Body" then
                root.Name = "Body"
        end

        -- A boss glows and carries a ring so it is unmistakable in a crowd.
        if enemy.boss then
                for _, instance in pairs(parts) do
                        instance.Material = Enum.Material.Neon
                end
                local aura = Instance.new("Part")
                aura.Name = "BossAura"
                aura.Shape = Enum.PartType.Cylinder
                aura.Size = Vector3.new(1, scale * 12, scale * 12)
                aura.CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
                aura.Anchored = true
                aura.CanCollide = false
                aura.Material = Enum.Material.Neon
                aura.Color = base
                aura.Transparency = 0.6
                aura.Parent = model
        end

        -- A health bar in the world, so progress is visible without a UI.
        local bar = Instance.new("BillboardGui")
        bar.Name = "HealthBar"
        bar.Size = UDim2.new(enemy.boss and 10 or 4, 0, 0.6, 0)
        bar.StudsOffsetWorldSpace = Vector3.new(0, tallest * scale + 2, 0)
        bar.AlwaysOnTop = true
        bar.Parent = root

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
                archetype = scaled.id,
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

--------------------------------------------------------------------------
-- Class appearance. The class already changed the stat sheet; this is what
-- makes a Knight look like a Knight. It works on both the R6 and R15 rigs
-- because it only recolours the parts the rig already has and welds its own
-- accents on, rather than rebuilding the avatar.
--------------------------------------------------------------------------

local BODY_PART_NAMES: { [string]: boolean } = {
        Head = true,
        Torso = true,
        ["Left Arm"] = true,
        ["Right Arm"] = true,
        ["Left Leg"] = true,
        ["Right Leg"] = true,
        UpperTorso = true,
        LowerTorso = true,
        LeftUpperArm = true,
        LeftLowerArm = true,
        LeftHand = true,
        RightUpperArm = true,
        RightLowerArm = true,
        RightHand = true,
        LeftUpperLeg = true,
        LeftLowerLeg = true,
        LeftFoot = true,
        RightUpperLeg = true,
        RightLowerLeg = true,
        RightFoot = true,
}

local ACCENT_PREFIX = "AXAccent_"

-- Names that belong in the character's hand. Everything else rides the root.
local HELD_NAMES = { "Blade", "Staff", "Bow", "Dagger" }

local function isHeld(name: string): boolean
        for _, held in ipairs(HELD_NAMES) do
                if string.find(name, held) then
                        return true
                end
        end
        return false
end

-- Remove a previously applied set so advancing a job does not stack two
-- costumes on one avatar.
local function clearAccents(character: Model)
        for _, child in ipairs(character:GetChildren()) do
                if child.Name:sub(1, #ACCENT_PREFIX) == ACCENT_PREFIX then
                        child:Destroy()
                end
        end
end

local function paintBody(character: Model, look: any)
        -- A worn Shirt or Pants asset is drawn on top of the body part colours,
        -- so the class palette would be invisible on a dressed avatar. Removing
        -- them is what makes the two jobs actually look different in game.
        for _, child in ipairs(character:GetChildren()) do
                if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("Clothing") then
                        child:Destroy()
                end
        end
        for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and BODY_PART_NAMES[part.Name] then
                        if part.Name == "Head" then
                                part.Color = rgb(look.skin)
                        elseif string.find(part.Name, "Leg") or part.Name == "LowerTorso" then
                                part.Color = rgb(look.pants)
                        else
                                part.Color = rgb(look.shirt)
                        end
                end
        end
end

local function newAccentPart(shape: string): BasePart
        if shape == "Ball" then
                local p = Instance.new("Part")
                p.Shape = Enum.PartType.Ball
                return p
        elseif shape == "Cylinder" then
                local p = Instance.new("Part")
                p.Shape = Enum.PartType.Cylinder
                return p
        elseif shape == "Wedge" then
                return Instance.new("WedgePart")
        end
        return Instance.new("Part")
end

-- Wear one class look. `classId` comes from the save record, so a respawn and a
-- job advance both end up here.
--
-- The accents wait for the right hand to exist, because a character is added
-- before it is fully assembled and a weapon welded to a missing part would fall
-- to the ground. A generation counter per character means a respawn during that
-- wait cannot leave the previous costume welded to the new body.
local lookGeneration: { [Model]: number } = {}

function World.applyClassLook(character: Model, classId: string?)
        if not character or not character.Parent then
                return
        end

        local look = ClassLook.get(classId)
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then
                return
        end

        paintBody(character, look)

        -- A slight build difference per class, so a Knight reads heavier than a
        -- Thief even with no accents in view.
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
                local scale = look.bodyScale
                humanoid.BodyWidthScale = scale[1]
                humanoid.BodyHeightScale = scale[2]
                humanoid.BodyDepthScale = scale[3]
        end

        lookGeneration[character] = (lookGeneration[character] or 0) + 1
        local mine = lookGeneration[character]

        task.spawn(function()
                -- The hand is not always present the instant the character is
                -- added, so wait briefly for it before falling back to the root.
                local hand = character:FindFirstChild("RightHand")
                        or character:FindFirstChild("Right Arm")
                        or character:WaitForChild("RightHand", 2)
                        or root

                -- A newer look landed while this one waited, or the character
                -- died; either way this costume is stale and must not be worn.
                if lookGeneration[character] ~= mine or not character.Parent then
                        return
                end

                clearAccents(character)

                for _, spec in ipairs(look.accents) do
                        local part = newAccentPart(spec.shape)
                        part.Name = ACCENT_PREFIX .. spec.name
                        part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
                        part.Color = rgb(spec.color)
                        part.Material = Enum.Material.SmoothPlastic
                        part.CanCollide = false
                        part.CanQuery = false
                        part.CanTouch = false
                        part.Massless = true
                        part.Parent = character

                        -- Place the part where the recipe says, measured from the
                        -- root. The weld then locks that exact relative pose, so a
                        -- hand-welded weapon keeps the designed position and still
                        -- follows the arm.
                        local rotation = CFrame.new()
                        if spec.rot then
                                rotation = CFrame.Angles(math.rad(spec.rot[1]), math.rad(spec.rot[2]), math.rad(spec.rot[3]))
                        end
                        part.CFrame = root.CFrame * rotation * CFrame.new(spec.at[1], spec.at[2], spec.at[3])

                        local weld = Instance.new("WeldConstraint")
                        weld.Part0 = isHeld(spec.name) and hand or root
                        weld.Part1 = part
                        weld.Parent = part
                end
        end)
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

--------------------------------------------------------------------------
-- Dropped items. A kill leaves loot on the ground; the player walks over it or
-- taps PICKUP. The server owns the drop list, so the client cannot invent one.
--------------------------------------------------------------------------

local RARITY_COLOR: { [string]: Color3 } = {
        common = Color3.fromRGB(200, 205, 215),
        uncommon = Color3.fromRGB(120, 220, 140),
        rare = Color3.fromRGB(110, 180, 255),
        epic = Color3.fromRGB(200, 130, 255),
        legendary = Color3.fromRGB(255, 200, 90),
}

-- Leave an item on the ground at a position. Returns the drop id.
function World.spawnDrop(itemId: string, count: number, position: Vector3, fieldId: string?, now: number): number
        nextDropId += 1
        local id = nextDropId

        local model = Instance.new("Model")
        model.Name = "Drop_" .. id

        local def = Items.getDef(itemId)
        local color = RARITY_COLOR[def and def.rarity or "common"] or Color3.fromRGB(220, 220, 220)

        local part = Instance.new("Part")
        part.Name = "Item"
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(1.6, 1.6, 1.6)
        part.Position = position + Vector3.new(0, 2.4, 0)
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Color = color
        part.Parent = model

        -- A light so a rare drop is visible across the field.
        local light = Instance.new("PointLight")
        light.Brightness = 1.6
        light.Range = 14
        light.Color = color
        light.Parent = part

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "Tag"
        billboard.Size = UDim2.new(6, 0, 1.4, 0)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = part

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextScaled = true
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.4
        label.Text = Text.itemName(itemId) .. (count > 1 and (" x" .. count) or "")
        label.Parent = billboard

        model.PrimaryPart = part
        model.Parent = Workspace

        drops[id] = {
                id = id,
                itemId = itemId,
                count = count,
                fieldId = fieldId,
                position = part.Position,
                expiresAt = now + Config.Items.DropLifetimeSeconds,
                model = model,
        }
        return id
end

function World.getDrop(id: number)
        return drops[id]
end

-- Every drop still on the ground, so the client can show or auto-collect them.
function World.dropSnapshot(fieldId: string?): { any }
        local out = {}
        for _, drop in pairs(drops) do
                if fieldId == nil or drop.fieldId == fieldId then
                        table.insert(out, {
                                id = drop.id,
                                itemId = drop.itemId,
                                count = drop.count,
                                position = drop.position,
                        })
                end
        end
        table.sort(out, function(a, b)
                return a.id < b.id
        end)
        return out
end

function World.removeDrop(id: number)
        local drop = drops[id]
        if not drop then
                return nil
        end
        if drop.model and drop.model.Parent then
                drop.model:Destroy()
        end
        drops[id] = nil
        return drop
end

-- Expire old drops. Called from the server tick.
function World.pruneDrops(now: number)
        for id, drop in pairs(drops) do
                if now >= drop.expiresAt then
                        World.removeDrop(id)
                end
        end
end

--------------------------------------------------------------------------
-- Floating damage numbers. A hit that does not move a bar on screen is easy to
-- miss on a phone, so every hit spawns a short-lived number above the target.
--------------------------------------------------------------------------

function World.showDamage(position: Vector3, amount: number, kind: string?, color: Color3?)
        local anchor = Instance.new("Part")
        anchor.Name = "DamageAnchor"
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Position = position + Vector3.new(0, 3.4, 0)
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.Transparency = 1
        anchor.Parent = Workspace

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(5, 0, 1.6, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = anchor

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBlack
        label.TextScaled = true
        label.TextStrokeTransparency = 0.2
        label.TextColor3 = color or Color3.fromRGB(255, 255, 255)

        if kind == "crit" then
                label.Text = tostring(amount) .. "!"
                label.TextColor3 = Color3.fromRGB(255, 210, 90)
        elseif kind == "heal" then
                label.Text = "+" .. tostring(amount)
                label.TextColor3 = Color3.fromRGB(120, 255, 150)
        elseif kind == "miss" then
                label.Text = "MISS"
                label.TextColor3 = Color3.fromRGB(190, 190, 200)
        else
                label.Text = tostring(amount)
        end
        label.Parent = billboard

        -- Rise and fade, then clean up. Short, because several hits land at once.
        local startY = anchor.Position.Y
        task.spawn(function()
                local elapsed = 0
                while elapsed < 0.7 do
                        local dt = task.wait(0.03)
                        elapsed += dt
                        if not anchor.Parent then
                                return
                        end
                        anchor.Position = Vector3.new(anchor.Position.X, startY + elapsed * 6, anchor.Position.Z)
                        label.TextTransparency = math.clamp(elapsed / 0.7, 0, 1)
                        label.TextStrokeTransparency = 0.2 + math.clamp(elapsed / 0.7, 0, 0.8)
                end
                if anchor.Parent then
                        anchor:Destroy()
                end
        end)
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

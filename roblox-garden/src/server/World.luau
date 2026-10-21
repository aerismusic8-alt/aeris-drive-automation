--!strict
-- Builds the world the player stands in: ground, a shop stand, and one part per
-- plot. This is the only place in the game that creates geometry.
--
-- It builds from `Garden`'s own plot count and `Config.Garden`'s own grid, so the
-- number of parts in the world can never disagree with the number of plots the
-- server will accept a plant on. That mismatch was a real bug in the previous
-- game: the world had six farm plots while the logic had a different count, and
-- tapping the extra one did nothing.

-- World is a server module, but its data comes from Shared, which Rojo syncs
-- into ReplicatedStorage rather than next to this script. Requiring "./Config"
-- would work in a flat test tree and fail in the real place, so the shared
-- modules are reached the same way the server script reaches them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local World = {}

export type PlotHandle = {
        index: number,
        model: any,
        soil: any,
        crop: any,
        label: any,
}

-- A part. `collide` defaults to false because most of this world is scenery the
-- player should be able to walk through: a crop, a sign, a label post.
--
-- The floor is the exception and it has to be solid. In the first playable build
-- every part was non-collidable, including the ground, so the character spawned
-- with nothing under it, fell out of the world and died within seconds. That is
-- the "join and die" K hit on the first try.
--
-- `opts` carries the shape work that makes the garden read as organic rather than
-- as boxes: a part can be a ball, a cylinder or a wedge, and it can be tilted.
-- Every one of those defaults to the old block, so a caller that passes nothing
-- still gets exactly what it got before.
local function part(name: string, size: any, position: any, color: any, collide: boolean?, material: any?, opts: any?): any
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Position = position
        p.Color = color
        p.Anchored = true
        p.CanCollide = collide == true
        p.Material = material or Enum.Material.SmoothPlastic
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        if opts then
                if opts.shape then
                        p.Shape = opts.shape
                end
                if opts.rotation then
                        p.CFrame = CFrame.new(position) * CFrame.Angles(opts.rotation[1], opts.rotation[2], opts.rotation[3])
                end
                if opts.transparency then
                        p.Transparency = opts.transparency
                end
        end
        return p
end

-- A colour from the Config palette. The palette stores 0-255 triples because that
-- is how a designer reads a colour, and the conversion to Color3 lives here once
-- rather than at every call site.
local function palette(name: string): any
        local entry = Config.Scenery.Palette[name] or { 200, 200, 200 }
        return Color3.fromRGB(entry[1], entry[2], entry[3])
end

-- A deterministic pseudo-random stream for scenery. Scenery must be in the same
-- place every server boot, or a player's garden looks different each visit and a
-- screenshot cannot be compared to the last one. Seed is fixed for that reason;
-- `math.randomseed` is deliberately not used because it would make the world
-- depend on boot order.
local function sceneryRandom(seed: number): () -> number
        local state = seed
        return function(): number
                state = (state * 1103515245 + 12345) % 2147483648
                return state / 2147483648
        end
end

-- The plot grid: `Columns` across, then wrapping. Row and column are derived
-- from the index in one place so the server, the world and the HUD all agree
-- which plot is where.
function World.plotPosition(index: number): any
        local columns = Config.Garden.Columns
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local spacing = Config.Garden.Spacing
        local x = Config.Garden.Origin.x + (column - (columns - 1) / 2) * spacing
        local z = Config.Garden.Origin.z + row * spacing
        return Vector3.new(x, 0.5, z)
end

-- One plot: soil, an invisible-but-present crop part the server colours in, and
-- a billboard the client writes the countdown onto.
local function buildPlot(index: number, unlocked: boolean): PlotHandle
        local model = Instance.new("Model")
        model.Name = Remotes.PlotPartName .. tostring(index)

        local position = World.plotPosition(index)

        local soil = part("Soil", Vector3.new(10, 1, 10), position, palette("Grass"))
        soil.Color = Color3.fromRGB(92, 64, 44)
        soil.Material = Enum.Material.Ground
        soil.Parent = model

        -- The crop is a ball, not a cube, so a growing plant reads as a plant
        -- rather than as a box rising out of the dirt.
        local crop = part("Crop", Vector3.new(5, 5, 5), position + Vector3.new(0, 3, 0), Color3.fromRGB(120, 120, 120),
                false, Enum.Material.LeafyGrass, { shape = Enum.PartType.Ball })
        crop.Transparency = 1
        crop.Parent = model

        local sign = part("Sign", Vector3.new(2, 2, 0.2), position + Vector3.new(0, 1.2, 5), Color3.fromRGB(240, 240, 240))
        sign.Parent = model

        local label = Instance.new("BillboardGui")
        label.Name = "Label"
        label.Size = UDim2.new(0, 160, 0, 40)
        label.StudsOffset = Vector3.new(0, 5, 0)
        label.AlwaysOnTop = true
        local text = Instance.new("TextLabel")
        text.Name = "Text"
        text.Size = UDim2.new(1, 0, 1, 0)
        text.BackgroundTransparency = 1
        text.TextScaled = true
        text.Text = ""
        text.Parent = label
        label.Parent = model

        -- Locked plots are visibly boarded up, so a player can tell the
        -- difference between "nothing planted" and "not bought yet" at a glance.
        if not unlocked then
                soil.Color = Color3.fromRGB(52, 48, 46)
                soil.Transparency = 0.35
        end

        return { index = index, model = model, soil = soil, crop = crop, label = label }
end

-- Trees, bushes, flowers, a fence and a path. All of it is scenery the player
-- walks through, so nothing here collides except the fence posts, and none of it
-- is load-bearing: delete the whole function and the game still plays.
--
-- Why it exists. The first build was a green slab with grey boxes on it, and K's
-- report was that the game "has no graphics at all". It had geometry, but
-- nothing that reads as a place. This is primitives only, deliberately: every
-- part of it is generated from numbers in Config, so it ships without an asset
-- upload and looks the same on every server.
local function buildScenery(root: any): number
        local cfg = Config.Scenery
        local rand = sceneryRandom(cfg.Seed)
        local count = 0

        local function add(name: string, size: any, position: any, color: any, collide: boolean?, material: any?, opts: any?)
                local p = part(name, size, position, color, collide, material, opts)
                p.Parent = root
                count += 1
                return p
        end

        local function between(spec: any): number
                return spec.MinScale + rand() * (spec.MaxScale - spec.MinScale)
        end

        -- A tree: a tapered trunk and three overlapping leaf balls at different
        -- heights and sizes. The old tree was two balls of the same green; the
        -- third, lighter ball on top is what gives it a lit crown and a
        -- silhouette that reads as a tree rather than as a lump.
        local function tree(x: number, z: number, scale: number)
                local lean = (rand() - 0.5) * 0.12
                add("Trunk", Vector3.new(1.6 * scale, 11 * scale, 1.6 * scale),
                        Vector3.new(x, 5.5 * scale, z), palette("Trunk"), false, Enum.Material.Wood,
                        { shape = Enum.PartType.Cylinder, rotation = { math.pi / 2, 0, lean } })
                local canopy = {
                        { 9.5, 12.5, "CanopyDark" },
                        { 8.0, 15.5, "CanopyMid" },
                        { 5.2, 18.0, "CanopyLight" },
                }
                for _, layer in ipairs(canopy) do
                        add("Leaves", Vector3.new(layer[1] * scale, layer[1] * scale, layer[1] * scale),
                                Vector3.new(x, layer[2] * scale, z), palette(layer[3]), false, Enum.Material.LeafyGrass,
                                { shape = Enum.PartType.Ball })
                end
        end

        -- A bush: three balls of slightly different green, offset so the top is
        -- not a single sphere. Smooth, not a box.
        local function bush(x: number, z: number, scale: number)
                local lobes = {
                        { 0, 2.6, 0, 6.0 },
                        { 1.8, 3.4, 0.9, 4.4 },
                        { -1.6, 3.1, -1.1, 4.0 },
                }
                for _, lobe in ipairs(lobes) do
                        add("Bush", Vector3.new(lobe[4] * scale, lobe[4] * scale, lobe[4] * scale),
                                Vector3.new(x + lobe[1] * scale, lobe[2] * scale, z + lobe[3] * scale),
                                palette("Bush"), false, Enum.Material.LeafyGrass,
                                { shape = Enum.PartType.Ball })
                end
        end

        local function flower(x: number, z: number, scale: number)
                add("Stem", Vector3.new(0.4, 2 * scale, 0.4),
                        Vector3.new(x, 1 * scale, z), palette("GrassTuft"), false, Enum.Material.Grass)
                local warm = rand() > 0.5
                add("Petal", Vector3.new(1.6 * scale, 1.6 * scale, 1.6 * scale),
                        Vector3.new(x, 2.2 * scale, z), palette(warm and "Flower" or "FlowerAlt"), false,
                        Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
        end

        -- A rock: a flattened, tilted ball. Grey, and matte rather than smooth, so
        -- it does not read as a plastic ball dropped on the grass.
        local function rock(x: number, z: number, scale: number)
                add("Rock", Vector3.new(3 * scale, 1.8 * scale, 2.6 * scale),
                        Vector3.new(x, 0.6 * scale, z), palette("Rock"), false, Enum.Material.Slate,
                        { shape = Enum.PartType.Ball, rotation = { rand() * 0.4, rand() * math.pi, rand() * 0.4 } })
        end

        -- A tuft of tall grass: two thin tilted blades. Cheap, and it is what
        -- stops the lawn reading as a flat painted plane between the props.
        local function tuft(x: number, z: number, scale: number)
                for blade = 1, 2 do
                        add("GrassTuft", Vector3.new(0.35, 2.4 * scale, 0.35),
                                Vector3.new(x + (blade - 1) * 0.6, 1.2 * scale, z), palette("GrassTuft"), false,
                                Enum.Material.Grass, { rotation = { 0, 0, (rand() - 0.5) * 0.7 } })
                end
        end

        -- A stone path from the spawn to the shop, so the two places a player
        -- moves between are connected by something rather than by nothing. The
        -- slabs alternate size and colour slightly, so the path is not a ruler.
        local spacing = Config.Garden.Spacing
        local steps = cfg.Path.Steps
        for step = 1, steps do
                local t = step / steps
                local z = spacing - (spacing * 2) * t
                local wobble = 1 + (rand() - 0.5) * 0.25
                add("PathSlab", Vector3.new(cfg.Path.Width * wobble, 0.4, cfg.Path.Depth * wobble),
                        Vector3.new((rand() - 0.5) * 1.2, 0.2, z), palette("Path"), false, Enum.Material.Cobblestone,
                        { rotation = { 0, (rand() - 0.5) * 0.3, 0 } })
        end

        -- A fence around the whole garden. Posts collide, the rails do not: a
        -- solid rail would let a player walk along it, which looks like floating.
        local halfWidth = (Config.Garden.Columns * spacing) / 2 + spacing
        local halfDepth = (Config.Garden.TotalPlots / Config.Garden.Columns) * spacing / 2 + spacing
        local postEvery = cfg.Fence.PostEvery
        local postHeight = cfg.Fence.Height
        local function post(x: number, z: number)
                add("FencePost", Vector3.new(0.8, postHeight, 0.8), Vector3.new(x, postHeight / 2, z),
                        palette("Fence"), true, Enum.Material.WoodPlanks)
        end
        for x = -halfWidth, halfWidth, postEvery do
                post(x, -halfDepth)
                post(x, halfDepth)
        end
        for z = -halfDepth, halfDepth, postEvery do
                post(-halfWidth, z)
                post(halfWidth, z)
        end
        -- Two rails per side, at two heights, so the fence reads as a fence.
        for _, y in ipairs({ 3.0, 4.2 }) do
                add("FenceRail", Vector3.new(halfWidth * 2, 0.35, 0.35), Vector3.new(0, y, -halfDepth), palette("FenceRail"), false, Enum.Material.WoodPlanks)
                add("FenceRail", Vector3.new(halfWidth * 2, 0.35, 0.35), Vector3.new(0, y, halfDepth), palette("FenceRail"), false, Enum.Material.WoodPlanks)
                add("FenceRail", Vector3.new(0.35, 0.35, halfDepth * 2), Vector3.new(-halfWidth, y, 0), palette("FenceRail"), false, Enum.Material.WoodPlanks)
                add("FenceRail", Vector3.new(0.35, 0.35, halfDepth * 2), Vector3.new(halfWidth, y, 0), palette("FenceRail"), false, Enum.Material.WoodPlanks)
        end

        -- A pond outside the fence. A cylinder sunk into the lawn, with a rim of
        -- rocks. The water is transparent so the ground colour reads through it,
        -- which is what sells it as water rather than as a blue disc.
        local pond = cfg.Pond
        local pondX, pondZ = pond.Distance, pond.Distance * 0.4
        add("Pond", Vector3.new(pond.Radius * 2, pond.Depth, pond.Radius * 2),
                Vector3.new(pondX, 0.1, pondZ), palette("Water"), false, Enum.Material.Glass,
                { shape = Enum.PartType.Cylinder, rotation = { math.pi / 2, 0, 0 }, transparency = 0.35 })
        for ring = 1, 10 do
                local angle = (ring / 10) * math.pi * 2
                rock(pondX + math.cos(angle) * pond.Radius, pondZ + math.sin(angle) * pond.Radius, 0.9 + rand() * 0.5)
        end

        -- Scattered greenery outside the fence. Placed from the fixed stream, so
        -- the same tree is at the same coordinate on every boot.
        local trees = cfg.Trees
        for _ = 1, trees.Count do
                local angle = rand() * math.pi * 2
                local radius = halfWidth + trees.MinRadius + rand() * (trees.MaxRadius - trees.MinRadius)
                tree(math.cos(angle) * radius, math.sin(angle) * radius, between(trees))
        end
        local bushes = cfg.Bushes
        for _ = 1, bushes.Count do
                local angle = rand() * math.pi * 2
                local radius = halfWidth + bushes.MinRadius + rand() * (bushes.MaxRadius - bushes.MinRadius)
                bush(math.cos(angle) * radius, math.sin(angle) * radius, between(bushes))
        end
        local rocks = cfg.Rocks
        for _ = 1, rocks.Count do
                local angle = rand() * math.pi * 2
                local radius = halfWidth + rocks.MinRadius + rand() * (rocks.MaxRadius - rocks.MinRadius)
                rock(math.cos(angle) * radius, math.sin(angle) * radius, between(rocks))
        end

        -- Grass tufts all over the lawn, including the bare strips between the
        -- plots, so no part of the ground is an unbroken flat plane.
        local tufts = cfg.GrassTufts
        for _ = 1, tufts.Count do
                local x = (rand() - 0.5) * halfWidth * 2
                local z = (rand() - 0.5) * halfDepth * 2
                local onPlot = math.abs(x) < (Config.Garden.Columns * spacing) / 2 + 6
                        and math.abs(z) < halfDepth - spacing
                if not onPlot then
                        tuft(x, z, between(tufts))
                end
        end

        -- Flowers inside the fence, kept clear of the plot cells so they never
        -- hide a crop.
        local flowers = cfg.Flowers
        for _ = 1, flowers.Count do
                local x = (rand() - 0.5) * halfWidth * 1.8
                local z = (rand() - 0.5) * halfDepth * 1.8
                local onPlot = math.abs(x) < (Config.Garden.Columns * spacing) / 2 + 6
                        and math.abs(z) < halfDepth - spacing
                if not onPlot then
                        flower(x, z, between(flowers))
                end
        end

        -- Lanterns on the fence corners. Each one is a warm PointLight, which is
        -- what lifts the corners out of shadow on a Voxel-lit map where global
        -- shadows are deliberately off.
        local lanterns = cfg.Lanterns
        local corners = {
                { -halfWidth, -halfDepth }, { halfWidth, -halfDepth },
                { -halfWidth, halfDepth }, { halfWidth, halfDepth },
        }
        for index = 1, math.min(lanterns.Count, #corners) do
                local corner = corners[index]
                local head = add("Lantern", Vector3.new(1.2, 1.6, 1.2),
                        Vector3.new(corner[1], lanterns.Height, corner[2]), palette("Lantern"), false,
                        Enum.Material.Neon, { shape = Enum.PartType.Ball })
                local light = Instance.new("PointLight")
                light.Brightness = 1.4
                light.Range = 22
                light.Color = palette("Lantern")
                light.Parent = head
                count += 1
        end

        return count
end

-- Re-light the place from Config.Visuals. This runs on the server so every
-- client sees the same sky, and it is the one place lighting is set: the project
-- file carries the same numbers as the starting point, and this is what keeps
-- them in step when the field changes at run time.
--
-- GlobalShadows stays off. It is the setting that makes this render on the Intel
-- HD adapter and on phones, and scripts/check-low-end-lighting.py fails the build
-- if it is ever turned on here.
function World.applyLook(): ()
        local Lighting = game:GetService("Lighting")
        local visuals = Config.Visuals
        local l = visuals.Lighting

        Lighting.ClockTime = l.ClockTime
        Lighting.GeographicLatitude = l.GeographicLatitude
        Lighting.Brightness = l.Brightness
        Lighting.Ambient = Color3.fromRGB(l.Ambient[1] * 255, l.Ambient[2] * 255, l.Ambient[3] * 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(l.OutdoorAmbient[1] * 255, l.OutdoorAmbient[2] * 255, l.OutdoorAmbient[3] * 255)
        Lighting.ShadowSoftness = l.ShadowSoftness
        Lighting.EnvironmentDiffuseScale = l.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = l.EnvironmentSpecularScale
        Lighting.GlobalShadows = false

        local function ensure(className: string, name: string): any
                local existing = Lighting:FindFirstChild(name)
                if existing then
                        return existing
                end
                local made = Instance.new(className)
                made.Name = name
                made.Parent = Lighting
                return made
        end

        local atmosphere = ensure("Atmosphere", "GardenAtmosphere")
        atmosphere.Density = visuals.Atmosphere.Density
        atmosphere.Offset = visuals.Atmosphere.Offset
        atmosphere.Glare = visuals.Atmosphere.Glare
        atmosphere.Haze = visuals.Atmosphere.Haze
        atmosphere.Color = Color3.fromRGB(
                visuals.Atmosphere.Color[1] * 255, visuals.Atmosphere.Color[2] * 255, visuals.Atmosphere.Color[3] * 255)

        local sky = ensure("Sky", "GardenSky")
        local s = visuals.Sky
        sky.SkyboxBk = s.SkyboxBk
        sky.SkyboxDn = s.SkyboxDn
        sky.SkyboxFt = s.SkyboxFt
        sky.SkyboxLf = s.SkyboxLf
        sky.SkyboxRt = s.SkyboxRt
        sky.SkyboxUp = s.SkyboxUp
        sky.SunAngularSize = s.SunAngularSize
        sky.MoonAngularSize = s.MoonAngularSize
        sky.StarCount = s.StarCount
        sky.CelestialBodiesShown = s.CelestialBodiesShown

        local clouds = ensure("Clouds", "GardenClouds")
        clouds.Cover = visuals.Clouds.Cover
        clouds.Density = visuals.Clouds.Density
        clouds.Color = Color3.fromRGB(
                visuals.Clouds.Color[1] * 255, visuals.Clouds.Color[2] * 255, visuals.Clouds.Color[3] * 255)

        local bloom = ensure("BloomEffect", "GardenBloom")
        bloom.Enabled = visuals.Bloom.Enabled
        bloom.Intensity = visuals.Bloom.Intensity
        bloom.Size = visuals.Bloom.Size
        bloom.Threshold = visuals.Bloom.Threshold

        local colour = ensure("ColorCorrectionEffect", "GardenColour")
        colour.Enabled = visuals.Colour.Enabled
        colour.Brightness = visuals.Colour.Brightness
        colour.Contrast = visuals.Colour.Contrast
        colour.Saturation = visuals.Colour.Saturation
        colour.TintColor = Color3.fromRGB(
                visuals.Colour.TintColor[1] * 255, visuals.Colour.TintColor[2] * 255, visuals.Colour.TintColor[3] * 255)

        local rays = ensure("SunRaysEffect", "GardenSunRays")
        rays.Enabled = visuals.SunRays.Enabled
        rays.Intensity = visuals.SunRays.Intensity
        rays.Spread = visuals.SunRays.Spread
end

-- Build the whole world and return the root plus the plot handles, in index
-- order, so the caller can address plot N without searching.
function World.build(unlocked: number): (any, { PlotHandle })
        local root = Instance.new("Model")
        root.Name = "GardenWorld"

        local ground = part("Ground", Vector3.new(400, 4, 400), Vector3.new(0, -2, 0), palette("Grass"), true, Enum.Material.Grass)
        ground.Parent = root

        -- Re-light the place before the scenery goes in, so the sky and the
        -- atmosphere are the ones the parts are built under.
        World.applyLook()

        buildScenery(root)

        -- The spawn point. Without one the engine has nowhere defined to place a
        -- joining character and drops it at the origin, which on this map is
        -- inside the shop stand. A SpawnLocation also makes the respawn after a
        -- death land on the lawn rather than wherever the last one ended.
        local spawn = Instance.new("SpawnLocation")
        spawn.Name = "GardenSpawn"
        spawn.Size = Vector3.new(12, 1, 12)
        spawn.Position = Vector3.new(0, 0.5, Config.Garden.Spacing)
        spawn.Anchored = true
        spawn.CanCollide = true
        spawn.Neutral = true
        spawn.Duration = 0
        spawn.Transparency = 0.4
        spawn.Color = Color3.fromRGB(150, 200, 120)
        spawn.Material = Enum.Material.SmoothPlastic
        spawn.Parent = root

        -- A shop stand, so the shop is a place rather than only a menu button.
        -- Walls, a pitched roof and a counter, so from the spawn it reads as a
        -- building. The old stand was one tall box with a flat sign on it.
        local shopZ = -Config.Garden.Spacing
        local shop = part("ShopStand", Vector3.new(14, 8, 8), Vector3.new(0, 4, shopZ), palette("ShopWall"), false, Enum.Material.WoodPlanks)
        shop.Parent = root
        -- A pitched roof: two slabs tilted toward each other, overhanging the
        -- walls. This is the single change that stops the stand looking like a crate.
        for side = -1, 1, 2 do
                local roof = part("ShopRoof", Vector3.new(8.4, 0.6, 9),
                        Vector3.new(side * 3.4, 9.2, shopZ), palette("ShopRoof"), false, Enum.Material.Slate,
                        { rotation = { 0, 0, side * 0.62 } })
                roof.Parent = root
        end
        local ridge = part("ShopRidge", Vector3.new(0.8, 0.8, 9.4), Vector3.new(0, 10.6, shopZ), palette("ShopRoof"), false, Enum.Material.Slate)
        ridge.Parent = root
        -- A counter across the front, so the shop has a serving side.
        local counter = part("ShopCounter", Vector3.new(12, 1, 1.6), Vector3.new(0, 3.6, shopZ + 4.4), palette("ShopSign"), false, Enum.Material.WoodPlanks)
        counter.Parent = root
        local shopSign = part("ShopSign", Vector3.new(10, 3, 0.4), Vector3.new(0, 6.4, shopZ + 4.2), palette("ShopSign"), false, Enum.Material.WoodPlanks)
        shopSign.Parent = root

        local plots: { PlotHandle } = {}
        for index = 1, Config.Garden.TotalPlots do
                local handle = buildPlot(index, index <= unlocked)
                handle.model.Parent = root
                table.insert(plots, handle)
        end

        return root, plots
end

-- Repaint one plot from a snapshot entry. The client calls this every state
-- push, so the crop colour, the ripeness and the countdown all come from the
-- server's numbers rather than from a local timer that can drift.
function World.paintPlot(handle: PlotHandle, plotState: any, seedColor: any, locked: boolean, labelText: string): ()
        if locked then
                handle.soil.Color = Color3.fromRGB(52, 48, 46)
                handle.soil.Transparency = 0.35
                handle.crop.Transparency = 1
                handle.label.Enabled = false
                return
        end

        handle.soil.Transparency = 0
        if plotState.seedId == nil then
                handle.crop.Transparency = 1
                handle.soil.Color = Color3.fromRGB(90, 62, 42)
        else
                handle.crop.Transparency = 0
                handle.crop.Color = seedColor or Color3.fromRGB(150, 220, 120)
                -- A ripe crop is brighter and sits higher, which reads at a
                -- glance on a phone screen from across the garden.
                if plotState.ready then
                        handle.crop.Position = handle.soil.Position + Vector3.new(0, 4.5, 0)
                        handle.crop.Color = seedColor or Color3.fromRGB(200, 255, 160)
                else
                        handle.crop.Position = handle.soil.Position + Vector3.new(0, 2 + plotState.progress * 2.5, 0)
                end
        end

        handle.label.Enabled = true
        local text = handle.label:FindFirstChild("Text")
        if text then
                text.Text = labelText
        end
end

return World

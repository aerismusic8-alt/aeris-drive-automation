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
local function part(name: string, size: any, position: any, color: any, collide: boolean?, material: any?): any
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
        return p
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

        local soil = part("Soil", Vector3.new(10, 1, 10), position, Color3.fromRGB(90, 62, 42))
        soil.Parent = model

        local crop = part("Crop", Vector3.new(5, 5, 5), position + Vector3.new(0, 3, 0), Color3.fromRGB(120, 120, 120))
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
        local rand = sceneryRandom(20261018)
        local count = 0

        local function add(name: string, size: any, position: any, color: any, collide: boolean?, material: any?)
                local p = part(name, size, position, color, collide, material)
                p.Parent = root
                count += 1
                return p
        end

        -- A tree: a trunk and two leaf balls. Balls rather than a block so the
        -- silhouette reads as a tree from across the garden.
        local function tree(x: number, z: number, scale: number)
                local trunk = add("Trunk", Vector3.new(2 * scale, 10 * scale, 2 * scale),
                        Vector3.new(x, 5 * scale, z), Color3.fromRGB(104, 71, 45), false, Enum.Material.Wood)
                local lower = add("Leaves", Vector3.new(9 * scale, 9 * scale, 9 * scale),
                        Vector3.new(x, 12 * scale, z), Color3.fromRGB(58, 122, 52), false, Enum.Material.LeafyGrass)
                lower.Shape = Enum.PartType.Ball
                local upper = add("Leaves", Vector3.new(6 * scale, 6 * scale, 6 * scale),
                        Vector3.new(x, 17 * scale, z), Color3.fromRGB(74, 148, 62), false, Enum.Material.LeafyGrass)
                upper.Shape = Enum.PartType.Ball
        end

        local function bush(x: number, z: number, scale: number)
                local b = add("Bush", Vector3.new(6 * scale, 5 * scale, 6 * scale),
                        Vector3.new(x, 2.5 * scale, z), Color3.fromRGB(70, 132, 58), false, Enum.Material.LeafyGrass)
                b.Shape = Enum.PartType.Ball
        end

        local function flower(x: number, z: number)
                local stem = add("Stem", Vector3.new(0.4, 2, 0.4),
                        Vector3.new(x, 1, z), Color3.fromRGB(86, 146, 66), false, Enum.Material.Grass)
                local petal = add("Petal", Vector3.new(1.6, 1.6, 1.6),
                        Vector3.new(x, 2.2, z), Color3.fromRGB(240, 120, 170), false, Enum.Material.SmoothPlastic)
                petal.Shape = Enum.PartType.Ball
        end

        -- A stone path from the spawn to the shop, so the two places a player
        -- moves between are connected by something rather than by nothing.
        local spacing = Config.Garden.Spacing
        local steps = 8
        for step = 1, steps do
                local t = step / steps
                local z = spacing - (spacing * 2) * t
                local slab = add("PathSlab", Vector3.new(7, 0.4, 4),
                        Vector3.new(0, 0.2, z), Color3.fromRGB(178, 172, 160), false, Enum.Material.Cobblestone)
                slab.Transparency = 0.05
        end

        -- A fence around the whole garden. Posts collide, the rails do not: a
        -- solid rail would let a player walk along it, which looks like floating.
        local halfWidth = (Config.Garden.Columns * spacing) / 2 + spacing
        local halfDepth = (Config.Garden.TotalPlots / Config.Garden.Columns) * spacing / 2 + spacing
        local postEvery = 8
        for x = -halfWidth, halfWidth, postEvery do
                add("FencePost", Vector3.new(0.8, 5, 0.8), Vector3.new(x, 2.5, -halfDepth), Color3.fromRGB(196, 168, 130), true, Enum.Material.WoodPlanks)
                add("FencePost", Vector3.new(0.8, 5, 0.8), Vector3.new(x, 2.5, halfDepth), Color3.fromRGB(196, 168, 130), true, Enum.Material.WoodPlanks)
        end
        for z = -halfDepth, halfDepth, postEvery do
                add("FencePost", Vector3.new(0.8, 5, 0.8), Vector3.new(-halfWidth, 2.5, z), Color3.fromRGB(196, 168, 130), true, Enum.Material.WoodPlanks)
                add("FencePost", Vector3.new(0.8, 5, 0.8), Vector3.new(halfWidth, 2.5, z), Color3.fromRGB(196, 168, 130), true, Enum.Material.WoodPlanks)
        end
        add("FenceRail", Vector3.new(halfWidth * 2, 0.6, 0.6), Vector3.new(0, 3.6, -halfDepth), Color3.fromRGB(206, 180, 142), false, Enum.Material.WoodPlanks)
        add("FenceRail", Vector3.new(halfWidth * 2, 0.6, 0.6), Vector3.new(0, 3.6, halfDepth), Color3.fromRGB(206, 180, 142), false, Enum.Material.WoodPlanks)
        add("FenceRail", Vector3.new(0.6, 0.6, halfDepth * 2), Vector3.new(-halfWidth, 3.6, 0), Color3.fromRGB(206, 180, 142), false, Enum.Material.WoodPlanks)
        add("FenceRail", Vector3.new(0.6, 0.6, halfDepth * 2), Vector3.new(halfWidth, 3.6, 0), Color3.fromRGB(206, 180, 142), false, Enum.Material.WoodPlanks)

        -- Scattered greenery outside the fence. Placed from the fixed stream, so
        -- the same tree is at the same coordinate on every boot.
        for _ = 1, 22 do
                local angle = rand() * math.pi * 2
                local radius = halfWidth + 12 + rand() * 60
                local x = math.cos(angle) * radius
                local z = math.sin(angle) * radius
                tree(x, z, 0.8 + rand() * 0.6)
        end
        for _ = 1, 18 do
                local angle = rand() * math.pi * 2
                local radius = halfWidth + 4 + rand() * 20
                bush(math.cos(angle) * radius, math.sin(angle) * radius, 0.7 + rand() * 0.5)
        end
        -- Flowers inside the fence, kept clear of the plot cells so they never
        -- hide a crop.
        for _ = 1, 40 do
                local x = (rand() - 0.5) * halfWidth * 1.8
                local z = (rand() - 0.5) * halfDepth * 1.8
                local onPlot = math.abs(x) < (Config.Garden.Columns * spacing) / 2 + 6
                        and math.abs(z) < halfDepth - spacing
                if not onPlot then
                        flower(x, z)
                end
        end

        return count
end

-- Build the whole world and return the root plus the plot handles, in index
-- order, so the caller can address plot N without searching.
function World.build(unlocked: number): (any, { PlotHandle })
        local root = Instance.new("Model")
        root.Name = "GardenWorld"

        local ground = part("Ground", Vector3.new(400, 4, 400), Vector3.new(0, -2, 0), Color3.fromRGB(96, 132, 72), true, Enum.Material.Grass)
        ground.Parent = root

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
        local shop = part("ShopStand", Vector3.new(14, 10, 8), Vector3.new(0, 5, -Config.Garden.Spacing), Color3.fromRGB(150, 110, 70))
        shop.Parent = root
        local shopSign = part("ShopSign", Vector3.new(10, 3, 0.4), Vector3.new(0, 12, -Config.Garden.Spacing + 4), Color3.fromRGB(250, 230, 180))
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

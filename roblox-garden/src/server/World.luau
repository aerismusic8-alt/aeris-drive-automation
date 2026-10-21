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

local function part(name: string, size: any, position: any, color: any): any
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Position = position
        p.Color = color
        p.Anchored = true
        p.CanCollide = false
        p.Material = Enum.Material.SmoothPlastic
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        return p
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

-- Build the whole world and return the root plus the plot handles, in index
-- order, so the caller can address plot N without searching.
function World.build(unlocked: number): (any, { PlotHandle })
        local root = Instance.new("Model")
        root.Name = "GardenWorld"

        local ground = part("Ground", Vector3.new(400, 4, 400), Vector3.new(0, -2, 0), Color3.fromRGB(96, 132, 72))
        ground.Parent = root

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

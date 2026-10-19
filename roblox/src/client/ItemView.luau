--!strict
-- Draws an item as a small 3D object inside a ViewportFrame.
--
-- The bag used to be text rows, so a sword and a potion were both "a word and
-- a number". A tile now shows the actual shape from ItemIcons, lit and turned
-- slightly, so a player recognises what they picked up without reading it.
--
-- ViewportFrame accepts parts as children directly, so the icon does not need a
-- Model or a rig: the recipe is built in place, the camera is fixed, and the
-- frame is cheap enough to build one per bag slot.

local ItemIcons = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ItemIcons"))

local ItemView = {}

local CAMERA_DISTANCE = 3.4
local FIELD_OF_VIEW = 42

local function rgb(color: { number }): Color3
        return Color3.fromRGB(color[1], color[2], color[3])
end

local function newPart(shape: string): BasePart
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

-- Build the recipe's parts into the viewport, rotated by the icon's own tilt so
-- a sword reads as diagonal rather than as a thin vertical line.
local function buildIcon(viewport: ViewportFrame, itemId: string, def: any)
        local icon = ItemIcons.get(itemId, def)
        local tilt = CFrame.Angles(math.rad(icon.tilt[1]), math.rad(icon.tilt[2]), math.rad(icon.tilt[3]))

        for _, spec in ipairs(icon.parts) do
                local part = newPart(spec.shape)
                part.Name = spec.name
                part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
                part.Color = rgb(spec.color)
                part.Material = Enum.Material.SmoothPlastic
                part.Anchored = true
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false

                local rotation = CFrame.new()
                if spec.rot then
                        rotation = CFrame.Angles(math.rad(spec.rot[1]), math.rad(spec.rot[2]), math.rad(spec.rot[3]))
                end
                local at = spec.at
                part.CFrame = tilt * rotation * CFrame.new(at[1], at[2], at[3])
                part.Parent = viewport
        end
end

-- One tile: a lit viewport with the item in it. `size` is in pixels.
function ItemView.tile(parent: Instance, name: string, position: UDim2, size: number, itemId: string, def: any): ViewportFrame
        local frame = Instance.new("Frame")
        frame.Name = name
        frame.Size = UDim2.new(0, size, 0, size)
        frame.Position = position
        frame.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
        frame.BorderSizePixel = 0
        frame.ZIndex = 22
        frame.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = frame

        local edge = Instance.new("UIStroke")
        edge.Color = Color3.fromRGB(70, 78, 100)
        edge.Thickness = 1.5
        edge.Parent = frame

        local viewport = Instance.new("ViewportFrame")
        viewport.Name = "Icon"
        viewport.Size = UDim2.new(1, -8, 1, -8)
        viewport.Position = UDim2.new(0, 4, 0, 4)
        viewport.BackgroundTransparency = 1
        viewport.ZIndex = 23
        viewport.Ambient = Color3.fromRGB(150, 150, 165)
        viewport.LightColor = Color3.fromRGB(255, 250, 240)
        viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
        viewport.Parent = frame

        local camera = Instance.new("Camera")
        camera.FieldOfView = FIELD_OF_VIEW
        camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.35, -CAMERA_DISTANCE), Vector3.new(0, 0, 0))
        camera.Parent = viewport
        viewport.CurrentCamera = camera

        buildIcon(viewport, itemId, def)
        return viewport
end

-- A tile plus a caption underneath, sized so a grid of them lines up.
function ItemView.cell(
        parent: Instance,
        name: string,
        position: UDim2,
        size: number,
        itemId: string,
        def: any,
        caption: string
): TextButton
        local cell = Instance.new("TextButton")
        cell.Name = name
        cell.Size = UDim2.new(0, size, 0, size + 16)
        cell.Position = position
        cell.BackgroundTransparency = 1
        cell.Text = ""
        cell.AutoButtonColor = false
        cell.ZIndex = 22
        cell.Parent = parent

        ItemView.tile(cell, name .. "Icon", UDim2.new(0, 0, 0, 0), size, itemId, def)

        local label = Instance.new("TextLabel")
        label.Name = "Caption"
        label.Size = UDim2.new(1, 0, 0, 14)
        label.Position = UDim2.new(0, 0, 0, size + 2)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.TextScaled = false
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.TextColor3 = Color3.fromRGB(200, 206, 220)
        label.Text = caption
        label.ZIndex = 23
        label.Parent = cell
        return cell
end

-- An empty tile, for a slot nothing is worn in.
function ItemView.emptyTile(parent: Instance, name: string, position: UDim2, size: number): Frame
        local frame = Instance.new("Frame")
        frame.Name = name
        frame.Size = UDim2.new(0, size, 0, size)
        frame.Position = position
        frame.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
        frame.BackgroundTransparency = 0.35
        frame.BorderSizePixel = 0
        frame.ZIndex = 22
        frame.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = frame

        local edge = Instance.new("UIStroke")
        edge.Color = Color3.fromRGB(58, 64, 84)
        edge.Thickness = 1
        edge.Transparency = 0.4
        edge.Parent = frame
        return frame
end

-- A small count badge in the corner of a tile.
function ItemView.badge(parent: Instance, count: number)
        if count <= 1 then
                return
        end
        local badge = Instance.new("TextLabel")
        badge.Name = "Count"
        badge.Size = UDim2.new(0, 26, 0, 16)
        badge.Position = UDim2.new(1, -28, 0, 2)
        badge.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
        badge.BackgroundTransparency = 0.15
        badge.BorderSizePixel = 0
        badge.Font = Enum.Font.GothamBold
        badge.TextSize = 12
        badge.TextColor3 = Color3.fromRGB(255, 236, 190)
        badge.Text = "x" .. tostring(count)
        badge.ZIndex = 24
        badge.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = badge
end

return ItemView

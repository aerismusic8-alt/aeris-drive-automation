--[[
        UI pass for Breachline, applied to the place at build time.

        The firearm client resolves three ScreenGui templates out of
        ReplicatedStorage/Assets/UI by name and clones them onto the player:

          FirearmCrosshair   ClientCrosshair:Enable  -- needs a child "Holder"
          FirearmAmmo        ClientAmmoHud:Enable    -- needs a TextLabel "AmmoLabel"
          Scope              enableScopeMode         -- needs a Frame "Shroud" and an ImageLabel "Holder"

        The place does not carry any of them, and no script creates them. Each
        module warns and returns when its template is missing, so on the shipped
        place there is no crosshair, no ammo counter, and no scope overlay at all:
        enableScopeMode leaves scopeGui nil, which makes stepScope and
        destroyScopeGui no-ops. That is the "scope does nothing" symptom, and it is
        a missing asset rather than a broken algorithm.

        They are created here rather than shipped as a script because a template is
        an asset, not behaviour: baking it into the place means the client clones a
        real instance at equip time instead of building a GUI from code on every
        weapon equip, which is the expensive path on a phone.

        Sizes are in pixels at a 1280x720 reference and every panel is sized from
        the safe insets, so the same template reads on a phone and on a desktop.

        Usage:
          rbxmk run --allow-insecure-paths breachline/ui.lua <place.rbxl> <out.rbxl>
]]

local inPath, outPath = ...

assert(inPath, "usage: ui.lua <place.rbxl> <out.rbxl>")
assert(outPath, "usage: ui.lua <place.rbxl> <out.rbxl>")

local place = fs.read(inPath)
assert(place and place.ClassName == "DataModel", "place did not decode to a DataModel")

---ReplicatedStorage/Assets/UI, created if the base place does not have it.
local function uiFolder()
        local replicatedStorage = place:FindFirstChild("ReplicatedStorage")
        assert(replicatedStorage, "place has no ReplicatedStorage")

        local assets = replicatedStorage:FindFirstChild("Assets")
        if not assets then
                assets = Instance.new("Folder")
                assets.Name = "Assets"
                assets.Parent = replicatedStorage
        end

        local ui = assets:FindFirstChild("UI")
        if not ui then
                ui = Instance.new("Folder")
                ui.Name = "UI"
                ui.Parent = assets
        end

        return ui
end

---Replace any existing template of this name so a rebuild is idempotent.
local function freshTemplate(parent, name, className)
        local existing = parent:FindFirstChild(name)
        if existing then existing:Destroy() end

        local instance = Instance.new(className)
        instance.Name = name
        instance.Parent = parent
        return instance
end

local function frame(parent, name, properties)
        local f = Instance.new("Frame")
        f.Name = name
        for key, value in pairs(properties or {}) do
                f[key] = value
        end
        f.Parent = parent
        return f
end

local ui = uiFolder()

--------------------------------------------------------------------------
-- Crosshair. One ScreenGui holding a centred Holder Frame; the client sizes
-- Holder from the current spread cone, so it starts at the minimum diameter.
--------------------------------------------------------------------------
local crosshair = freshTemplate(ui, "FirearmCrosshair", "ScreenGui")
crosshair.ResetOnSpawn = false
crosshair.IgnoreGuiInset = true
crosshair.DisplayOrder = 20

frame(crosshair, "Holder", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(8, 8),
        BackgroundTransparency = 1,
})

--------------------------------------------------------------------------
-- Ammo. A single TextLabel, bottom-right and above the safe inset, which is
-- where the weapon's own HUD lives and clear of the thumb cluster.
--------------------------------------------------------------------------
local ammo = freshTemplate(ui, "FirearmAmmo", "ScreenGui")
ammo.ResetOnSpawn = false
ammo.IgnoreGuiInset = false
ammo.DisplayOrder = 12

local ammoLabel = Instance.new("TextLabel")
ammoLabel.Name = "AmmoLabel"
ammoLabel.AnchorPoint = Vector2.new(1, 1)
ammoLabel.Position = UDim2.new(1, -18, 1, -18)
ammoLabel.Size = UDim2.fromOffset(160, 46)
ammoLabel.BackgroundTransparency = 1
ammoLabel.TextColor3 = Color3.fromRGB(246, 239, 216)
ammoLabel.TextScaled = true
ammoLabel.Text = "10/10"
ammoLabel.Parent = ammo

local ammoSize = Instance.new("UITextSizeConstraint")
ammoSize.MaxTextSize = 30
ammoSize.MinTextSize = 14
ammoSize.Parent = ammoLabel

--------------------------------------------------------------------------
-- Scope. A Shroud Frame that blacks out the periphery and a Holder ImageLabel
-- the client reveals at full ADS. Both are looked up by name, so both exist.
--------------------------------------------------------------------------
local scope = freshTemplate(ui, "Scope", "ScreenGui")
scope.ResetOnSpawn = false
scope.IgnoreGuiInset = true
scope.DisplayOrder = 30

local shroud = frame(scope, "Shroud", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
})

-- The aperture. A circle of transparent pixels would need an image, so the
-- hole is made by four black bars around a transparent centre instead: that is
-- resolution-independent, needs no upload, and reads correctly at any zoom.
local HOLE = 0.62
local half = (1 - HOLE) / 2
for _, bar in ipairs({
        { "Top", UDim2.new(1, 0, half, 0), UDim2.new(0, 0, 0, 0) },
        { "Bottom", UDim2.new(1, 0, half, 0), UDim2.new(0, 0, 1 - half, 0) },
        { "Left", UDim2.new(half, 0, HOLE, 0), UDim2.new(0, 0, half, 0) },
        { "Right", UDim2.new(half, 0, HOLE, 0), UDim2.new(1 - half, 0, half, 0) },
}) do
        frame(shroud, bar[1], {
                Size = bar[2],
                Position = bar[3],
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
        })
end

local holder = Instance.new("ImageLabel")
holder.Name = "Holder"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.5)
holder.Size = UDim2.fromScale(HOLE, HOLE)
holder.BackgroundTransparency = 1
holder.ImageTransparency = 1
holder.Visible = false
holder.Parent = scope

-- Crosshair lines inside the aperture, so the scope has a real reticle rather
-- than a bare hole.
for _, line in ipairs({
        { "ReticleH", UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 0.5, 0) },
        { "ReticleV", UDim2.fromOffset(1, 0), UDim2.new(0.5, 0, 0.5, 0) },
}) do
        local l = Instance.new("Frame")
        l.Name = line[1]
        l.Size = line[2]
        l.Position = line[3]
        l.AnchorPoint = Vector2.new(0.5, 0.5)
        l.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        l.BorderSizePixel = 0
        l.Parent = holder
end

fs.write(outPath, place, "rbxl")
print(string.format("UI_OK crosshair=yes ammo=yes scope=yes out=%s", outPath))

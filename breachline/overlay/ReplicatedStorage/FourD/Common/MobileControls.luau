--[[
	File: ReplicatedStorage/FourD/Common/MobileControls.luau

	The touch cluster for a shooter on foot, drawn once and owned by one
	controller.

	Why this exists next to TouchFire: TouchFire reveals a single FIRE face
	that belongs to the vehicle cluster, because a gunner is usually also a
	driver and two overlapping clusters is worse than one. A player on foot
	has no such cluster and needs more than one button -- fire, aim, scope,
	reload, and the movement verbs -- so this module draws its own set and
	keeps them apart by construction.

	The layout is computed from the button sizes rather than written as
	literals, so a button can never land on its neighbour when a size is
	tuned. Everything sits inside the screen's safe insets, and a UIScale
	shrinks the cluster on short screens.
]]--

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local MobileControls = {}
MobileControls.__index = MobileControls

-- Button geometry, in pixels before UIScale. Order within a column is
-- bottom-up; the gap keeps neighbours from touching at any scale.
local GAP = 12
local MARGIN = 20
local COLUMN_GAP = 12

-- Right column: the verbs a thumb reaches without leaving the corner.
local PRIMARY = {
	{ Name = "Fire", Label = "FIRE", Size = 96 },
	{ Name = "Aim", Label = "ADS", Size = 76 },
	{ Name = "Scope", Label = "SCOPE", Size = 64 },
	{ Name = "Switch", Label = "SWAP", Size = 64 },
}

-- Left of it: less frequent, still right-thumb reachable.
local SECONDARY = {
	{ Name = "Reload", Label = "RELOAD", Size = 72 },
	{ Name = "Jump", Label = "JUMP", Size = 68 },
	{ Name = "Crouch", Label = "CROUCH", Size = 68 },
	{ Name = "Interact", Label = "USE", Size = 72 },
}

local SMALL_SCREEN_THRESHOLD = 500
local SHORT_SCREEN_THRESHOLD = 620
local SMALL_SCREEN_SCALE = 0.8
local SHORT_SCREEN_SCALE = 0.85

local STORAGE_PREFIX = "MobileControls_"

local function readSetting(key, default)
	local value = player:GetAttribute(STORAGE_PREFIX .. key)
	if value == nil then return default end
	return value
end

local function writeSetting(key, value)
	player:SetAttribute(STORAGE_PREFIX .. key, value)
end

function MobileControls:IsEnabled(): boolean
	return self._gui ~= nil
end

---Turns the whole cluster on or off, for a menu or a cutscene.
function MobileControls:SetVisible(visible: boolean)
	if self._gui then
		self._gui.Enabled = visible
	end
end

---Restricts which buttons appear, so a weapon without a scope draws none.
function MobileControls:SetAvailable(available: { [string]: boolean })
	if not self._buttons then return end
	for name, button in pairs(self._buttons) do
		local allowed = available[name] ~= false
		button.Visible = allowed
	end
end

function MobileControls:_applySettings()
	local scale = readSetting("Scale", 1)
	local transparency = readSetting("Transparency", 0)

	self._scale.Scale = scale * self._baseScale
	for _, button in pairs(self._buttons) do
		button.BackgroundTransparency = transparency
	end
end

-- Lay a column out from the bottom edge, returning each button's y offset
-- and height so the caller never has to repeat the arithmetic.
local function layoutColumn(specs)
	local placements = {}
	local cursor = MARGIN
	for _, spec in ipairs(specs) do
		placements[spec.Name] = { Offset = cursor, Size = spec.Size, Spec = spec }
		cursor += spec.Size + GAP
	end
	return placements, cursor
end

function MobileControls:_draw()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 8
	gui.Parent = playerGui

	local scale = Instance.new("UIScale")
	scale.Parent = gui

	self._gui = gui
	self._scale = scale
	self._buttons = {}

	local primary, primaryHeight = layoutColumn(PRIMARY)
	local secondary, secondaryHeight = layoutColumn(SECONDARY)

	local primaryWidth = 0
	for _, spec in ipairs(PRIMARY) do
		primaryWidth = math.max(primaryWidth, spec.Size)
	end

	local secondaryWidth = 0
	for _, spec in ipairs(SECONDARY) do
		secondaryWidth = math.max(secondaryWidth, spec.Size)
	end

	-- The secondary column's left edge, measured from the right of the
	-- screen so both columns stay anchored to the corner they share.
	local secondaryX = MARGIN + primaryWidth + COLUMN_GAP

	local function makeButton(placement, fromRight)
		local spec = placement.Spec
		local button = Instance.new("TextButton")
		button.Name = spec.Name
		button.Text = spec.Label
		button.Size = UDim2.fromOffset(spec.Size, spec.Size)
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -(if fromRight then MARGIN else secondaryX), 1, -placement.Offset)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextColor3 = Color3.fromRGB(246, 239, 216)
		button.BackgroundColor3 = Color3.fromRGB(58, 66, 58)
		button.BackgroundTransparency = 0.2
		button.AutoButtonColor = false
		button.Selectable = false
		button.Parent = gui

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 6)
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.Parent = button

		local textSize = Instance.new("UITextSizeConstraint")
		textSize.MaxTextSize = 22
		textSize.MinTextSize = 9
		textSize.Parent = button

		self._buttons[spec.Name] = button
		return button
	end

	for _, placement in pairs(primary) do
		makeButton(placement, true)
	end
	for _, placement in pairs(secondary) do
		makeButton(placement, false)
	end

	self._primaryWidth = primaryWidth
	self._secondaryWidth = secondaryWidth
	self._reservedHeight = math.max(primaryHeight, secondaryHeight)

	return gui
end

function MobileControls:_updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	if not viewport then return end

	local minSide = math.min(viewport.X, viewport.Y)
	local base = 1
	if minSide < SMALL_SCREEN_THRESHOLD then
		base = SMALL_SCREEN_SCALE
	elseif viewport.Y < SHORT_SCREEN_THRESHOLD then
		base = SHORT_SCREEN_SCALE
	end

	self._baseScale = base
	self:_applySettings()
end

function MobileControls:Enable()
	if self._gui then return end

	self:_draw()
	self._baseScale = 1

	local connections = {}
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_updateScale()
		end))
	end

	self._connections = connections
	self:_updateScale()
	self:_applySettings()
end

function MobileControls:Disable()
	if not self._gui then return end

	for _, connection in ipairs(self._connections or {}) do
		connection:Disconnect()
	end
	self._connections = nil

	self._gui:Destroy()
	self._gui = nil
	self._scale = nil
	self._buttons = nil
end

function MobileControls:Destroy()
	self:Disable()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

---The button for a name, or nil if it was never drawn.
function MobileControls:GetButton(name: string): TextButton?
	if not self._buttons then return nil end
	return self._buttons[name]
end

function MobileControls.new()
	local self = setmetatable({}, MobileControls)
	self._gui = nil
	self._scale = nil
	self._buttons = nil
	self._connections = nil
	self._baseScale = 1
	self._reservedHeight = 0
	return self
end

MobileControls.readSetting = readSetting
MobileControls.writeSetting = writeSetting

return MobileControls

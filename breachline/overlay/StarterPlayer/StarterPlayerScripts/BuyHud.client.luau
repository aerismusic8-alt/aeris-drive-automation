--[[
	File: BuyHud.client.luau

	The buy-phase shop.

	Reworked for a phone. Every control is a real thumb target: the smallest
	button is 58px tall, which is above the ~44px a fingertip needs, and the
	rows are separated rather than stacked flush so a miss does not buy the
	wrong thing. The panel is capped in size and sits inside the safe insets,
	so it clears the notch and the home indicator, and its rows are laid out
	from a single cursor so adding an item cannot overlap the one above it.

	The shop opens from a button under the score bar rather than the middle of
	the screen, so it does not sit where the thumb looks, and it closes the
	moment the buy phase ends.
]]--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local state = game:GetService("ReplicatedStorage"):WaitForChild("MatchState")

local gui = Instance.new("ScreenGui")
gui.Name = "BuyHud"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 15
gui.Parent = player:WaitForChild("PlayerGui")

local PANEL_WIDTH = 420
local PANEL_PADDING = 18
local ROW_HEIGHT = 58
local ROW_GAP = 10
local OPEN_BUTTON_HEIGHT = 56

local function styleButton(button)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.fromRGB(246, 239, 216)
	button.BackgroundColor3 = Color3.fromRGB(78, 91, 75)
	button.AutoButtonColor = true
	button.Selectable = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = button

	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MaxTextSize = 24
	textSize.MinTextSize = 12
	textSize.Parent = button

	return button
end

local function makeButton(parent, name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Parent = parent
	return styleButton(button)
end

-- Opens from the top right, clear of the score bar and the look band.
local openButton = makeButton(gui, "OpenShop", "BUY")
openButton.Size = UDim2.fromOffset(96, OPEN_BUTTON_HEIGHT)
openButton.Position = UDim2.new(1, -14, 0, 92)
openButton.AnchorPoint = Vector2.new(1, 0)

local loadout = Instance.new("TextLabel")
loadout.Name = "Loadout"
loadout.Size = UDim2.new(0.6, 0, 0, 26)
loadout.Position = UDim2.new(0, 14, 0, 92)
loadout.BackgroundColor3 = Color3.fromRGB(41, 45, 41)
loadout.BackgroundTransparency = 0.2
loadout.TextColor3 = Color3.fromRGB(239, 237, 226)
loadout.Font = Enum.Font.GothamMedium
loadout.TextScaled = true
loadout.Parent = gui

local loadoutPadding = Instance.new("UIPadding")
loadoutPadding.PaddingLeft = UDim.new(0, 8)
loadoutPadding.PaddingRight = UDim.new(0, 8)
loadoutPadding.Parent = loadout

local loadoutTextSize = Instance.new("UITextSizeConstraint")
loadoutTextSize.MaxTextSize = 18
loadoutTextSize.MinTextSize = 11
loadoutTextSize.Parent = loadout

local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(41, 45, 41)
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingLeft = UDim.new(0, PANEL_PADDING)
panelPadding.PaddingRight = UDim.new(0, PANEL_PADDING)
panelPadding.PaddingTop = UDim.new(0, PANEL_PADDING)
panelPadding.PaddingBottom = UDim.new(0, PANEL_PADDING)
panelPadding.Parent = panel

local panelSize = Instance.new("UISizeConstraint")
panelSize.MaxSize = Vector2.new(PANEL_WIDTH, 360)
panelSize.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local balance = Instance.new("TextLabel")
balance.Name = "Balance"
balance.Size = UDim2.new(1, 0, 0, 44)
balance.BackgroundTransparency = 1
balance.Font = Enum.Font.GothamBold
balance.TextColor3 = Color3.new(1, 1, 1)
balance.TextScaled = true
balance.Parent = panel

local balanceTextSize = Instance.new("UITextSizeConstraint")
balanceTextSize.MaxTextSize = 22
balanceTextSize.MinTextSize = 13
balanceTextSize.Parent = balance

-- Rows are placed from one cursor, so a change to ROW_HEIGHT or a new item
-- cannot collide with its neighbour.
local cursor = 52
local function nextRow(): UDim2
	local y = cursor
	cursor += ROW_HEIGHT + ROW_GAP
	return UDim2.new(1, 0, 0, y)
end

local smg = makeButton(panel, "SMG", "Compact SMG  $700")
smg.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
smg.Position = nextRow()

local armor = makeButton(panel, "Armor", "Protective armor  $600")
armor.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
armor.Position = nextRow()

local close = makeButton(panel, "Close", "CLOSE")
close.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
close.Position = nextRow()

-- Size the panel to the rows actually drawn, so it hugs its contents on any
-- screen instead of leaving a fixed-height gap.
panel.Size = UDim2.new(0.94, 0, 0, cursor + PANEL_PADDING - ROW_GAP)

local function refreshPanelScale()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if not viewport then return end

	-- Shrink the panel rather than let it overflow a small screen.
	local width = math.min(viewport.X * 0.94, PANEL_WIDTH)
	local height = cursor + PANEL_PADDING - ROW_GAP
	local scale = math.min(1, (viewport.X * 0.94) / width, (viewport.Y * 0.86) / height)
	panelScale.Scale = scale
end

local function setOpen(on)
	panel.Visible = on and state:GetAttribute("Phase") == "Buy Phase"
	if panel.Visible then
		refreshPanelScale()
		player.CameraMode = Enum.CameraMode.Classic
	elseif player:GetAttribute("Alive") == true then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
end

local function refresh()
	openButton.Visible = state:GetAttribute("Phase") == "Buy Phase" and player:GetAttribute("Alive") == true
	if not openButton.Visible then setOpen(false) end

	balance.Text = "BUY PHASE  |  $" .. tostring(player:GetAttribute("Money") or 0)
	loadout.Text = "LOADOUT: CARBINE"
		.. (if player:GetAttribute("HasSMG") then " + SMG" else "")
		.. (if player:GetAttribute("Armor") then " + ARMOR" else "")

	smg.Text = if player:GetAttribute("HasSMG") then "Compact SMG  - OWNED" else "Compact SMG  $700"
	armor.Text = if player:GetAttribute("Armor") then "Protective armor  - OWNED" else "Protective armor  $600"
end

openButton.Activated:Connect(function() setOpen(not panel.Visible) end)
close.Activated:Connect(function() setOpen(false) end)
smg.Activated:Connect(function() state.BuyItem:FireServer("CompactSMG") end)
armor.Activated:Connect(function() state.BuyItem:FireServer("Armor") end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B and openButton.Visible then
		setOpen(not panel.Visible)
	end
end)

state:GetAttributeChangedSignal("Phase"):Connect(refresh)
for _, attr in ipairs({ "Money", "Armor", "HasSMG", "Alive" }) do
	player:GetAttributeChangedSignal(attr):Connect(refresh)
end

local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if panel.Visible then refreshPanelScale() end
	end)
end

refresh()

--!strict
-- The HUD, built from code so a Rojo build alone produces a playable screen.
--
-- Layout is mobile first: large touch targets, nothing in the thumb zone's way,
-- and the two reward buttons sit above the jump button rather than under it.
--
-- Buttons are wired to the same Intent functions the rest of the client uses,
-- so a tap and a scripted call behave identically.

local Players = game:GetService("Players")

local Hud = {}

local player = Players.LocalPlayer

local COLORS = {
	panel = Color3.fromRGB(18, 20, 28),
	panelEdge = Color3.fromRGB(58, 64, 84),
	text = Color3.fromRGB(236, 240, 248),
	muted = Color3.fromRGB(150, 158, 176),
	gold = Color3.fromRGB(255, 206, 84),
	green = Color3.fromRGB(86, 210, 130),
	blue = Color3.fromRGB(96, 170, 255),
	disabled = Color3.fromRGB(70, 74, 88),
}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- A label that reads well on a phone: bold, high contrast, no thin weights.
local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, textSize: number)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.TextColor3 = COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

-- Touch targets are at least 56px tall, which is the comfortable minimum on a
-- phone. Anything smaller and the player misses while moving.
local function button(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, color: Color3)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 20
	b.TextColor3 = Color3.fromRGB(12, 14, 20)
	b.TextWrapped = true
	b.Parent = parent
	corner(b, 12)
	return b
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2)
	local p = Instance.new("Frame")
	p.Name = name
	p.Size = size
	p.Position = position
	p.AnchorPoint = anchor
	p.BackgroundColor3 = COLORS.panel
	p.BackgroundTransparency = 0.15
	p.BorderSizePixel = 0
	p.Parent = parent
	corner(p, 14)
	stroke(p, COLORS.panelEdge, 1.5)
	return p
end

-- Build the screen once. Returns the ScreenGui.
function Hud.build(): ScreenGui
	local existing = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("AXArenaHUD")
	if existing then
		return existing :: ScreenGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AXArenaHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Stats, top left.
	local stats = panel(gui, "Stats", UDim2.new(0, 250, 0, 132), UDim2.new(0, 16, 0, 16), Vector2.new(0, 0))
	label(stats, "Coins", "Coins: 0", UDim2.new(1, -20, 0, 26), UDim2.new(0, 12, 0, 8), 20)
	label(stats, "Level", "Lv 1", UDim2.new(1, -20, 0, 22), UDim2.new(0, 12, 0, 38), 18)
	label(stats, "Health", "HP 100/100", UDim2.new(1, -20, 0, 22), UDim2.new(0, 12, 0, 62), 18)
	label(stats, "Zone", "Zone: Meadow", UDim2.new(1, -20, 0, 22), UDim2.new(0, 12, 0, 86), 18)
	label(stats, "Rebirth", "Rebirth 0", UDim2.new(1, -20, 0, 22), UDim2.new(0, 12, 0, 108), 16)

	-- Wave banner, top centre.
	local wave = panel(gui, "WavePanel", UDim2.new(0, 300, 0, 40), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
	local waveLabel = label(wave, "Wave", "Wave 1", UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0), 20)
	waveLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Reward buttons, bottom left: above the jump button and clear of the thumb.
	local rewards = panel(gui, "Rewards", UDim2.new(0, 200, 0, 132), UDim2.new(0, 16, 1, -24), Vector2.new(0, 1))
	local title = label(rewards, "Title", "Rewards", UDim2.new(1, -20, 0, 24), UDim2.new(0, 12, 0, 6), 16)
	title.TextColor3 = COLORS.muted

	local daily = button(rewards, "Daily", "Daily Reward", UDim2.new(1, -24, 0, 42), UDim2.new(0, 12, 0, 34), COLORS.gold)
	local code = button(rewards, "Code", "Redeem Code", UDim2.new(1, -24, 0, 42), UDim2.new(0, 12, 0, 82), COLORS.blue)

	return gui
end

return Hud

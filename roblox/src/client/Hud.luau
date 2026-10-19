--!strict
-- The HUD, built from code so a Rojo build alone produces a playable screen.
--
-- Layout is mobile first: large touch targets, nothing in the thumb zone's way,
-- and the two reward buttons sit above the jump button rather than under it.
--
-- Buttons are wired to the same Intent functions the rest of the client uses,
-- so a tap and a scripted call behave identically.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Every visible word comes from here, so the language lives in one file.
local Text = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Text"))

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

	-- Stats, top right, below the Roblox topbar. It used to sit top left,
	-- which is where the chat window is: the panel covered the chat and
	-- blocked its drag handle, so the chat could not be moved out of the way.
	local stats = panel(gui, "Stats", UDim2.new(0, 216, 0, 168), UDim2.new(1, -12, 0, 58), Vector2.new(1, 0))
	label(stats, "Coins", Text.get("coins") .. ": 0", UDim2.new(1, -20, 0, 30), UDim2.new(0, 12, 0, 8), 20)
	label(stats, "Level", Text.get("level") .. " 1", UDim2.new(1, -20, 0, 28), UDim2.new(0, 12, 0, 42), 18)
	label(stats, "Health", Text.get("health") .. " 100/100", UDim2.new(1, -20, 0, 28), UDim2.new(0, 12, 0, 72), 18)
	label(stats, "Field", Text.get("field") .. ": " .. Text.placeName("Town"), UDim2.new(1, -20, 0, 28), UDim2.new(0, 12, 0, 102), 18)
	label(stats, "Zone", Text.get("zone") .. ": " .. Text.placeName("Meadow"), UDim2.new(1, -20, 0, 26), UDim2.new(0, 12, 0, 132), 16)
	label(stats, "Rebirth", Text.get("rebirth") .. " 0", UDim2.new(1, -20, 0, 26), UDim2.new(0, 12, 0, 160), 16)

	-- Wave banner, top centre.
	local wave = panel(gui, "WavePanel", UDim2.new(0, 320, 0, 48), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
	local waveLabel = label(wave, "Wave", Text.get("wave") .. " 1", UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0), 20)
	waveLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Boss bar, just under the wave banner. Hidden unless a boss is alive, so
	-- it never steals attention from a normal wave.
	local boss = panel(gui, "BossPanel", UDim2.new(0, 320, 0, 54), UDim2.new(0.5, 0, 0, 190), Vector2.new(0.5, 0))
	boss.Visible = false
	local bossLabel = label(boss, "BossName", Text.get("boss"), UDim2.new(1, -16, 0, 28), UDim2.new(0, 8, 0, 4), 18)
	bossLabel.TextXAlignment = Enum.TextXAlignment.Center
	local bossTrack = Instance.new("Frame")
	bossTrack.Name = "BossTrack"
	bossTrack.Size = UDim2.new(1, -16, 0, 10)
	bossTrack.Position = UDim2.new(0, 8, 1, -18)
	bossTrack.BackgroundColor3 = COLORS.disabled
	bossTrack.BorderSizePixel = 0
	bossTrack.Parent = boss
	corner(bossTrack, 5)
	local bossFill = Instance.new("Frame")
	bossFill.Name = "BossFill"
	bossFill.Size = UDim2.new(1, 0, 1, 0)
	bossFill.BackgroundColor3 = COLORS.gold
	bossFill.BorderSizePixel = 0
	bossFill.Parent = bossTrack
	corner(bossFill, 5)

	-- Rewards overlay: the daily and code buttons used to sit bottom left,
	-- which is exactly where the phone's movement stick appears, so they
	-- covered it and stole the drag. They now live behind a button in the
	-- action panel and open in the middle of the screen.
	local rewards = panel(gui, "Rewards", UDim2.new(0, 300, 0, 206), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5))
	rewards.Visible = false
	rewards.ZIndex = 20
	local title = label(rewards, "RewardsTitle", Text.get("rewards"), UDim2.new(1, -80, 0, 30), UDim2.new(0, 12, 0, 8), 18)
	title.TextColor3 = COLORS.muted
	title.ZIndex = 21
	local closeRewards = button(rewards, "CloseRewards", "X", UDim2.new(0, 38, 0, 30), UDim2.new(1, -46, 0, 8), COLORS.disabled)
	closeRewards.ZIndex = 21

	local daily = button(rewards, "Daily", Text.get("dailyReward"), UDim2.new(1, -24, 0, 56), UDim2.new(0, 12, 0, 52), COLORS.gold)
	daily.ZIndex = 21
	local code = button(rewards, "Code", Text.get("redeemCode"), UDim2.new(1, -24, 0, 56), UDim2.new(0, 12, 0, 120), COLORS.blue)
	code.ZIndex = 21

	-- Action panel, bottom right: the two taps the game is built around.
	-- It sits under the thumb rather than in the middle of the screen, and the
	-- axe button carries the charge count so the player knows when to swing.
	local actions = panel(gui, "Actions", UDim2.new(0, 200, 0, 372), UDim2.new(1, -16, 1, -24), Vector2.new(1, 1))
	local axeLabel = label(actions, "AxeCharges", Text.get("axe") .. ": 0/5", UDim2.new(1, -20, 0, 26), UDim2.new(0, 12, 0, 6), 16)
	axeLabel.TextColor3 = COLORS.muted
	local axe = button(actions, "Axe", Text.get("axe"), UDim2.new(1, -24, 0, 56), UDim2.new(0, 12, 0, 34), COLORS.blue)
	local farm = button(actions, "Farm", Text.get("farm"), UDim2.new(1, -24, 0, 56), UDim2.new(0, 12, 0, 96), COLORS.green)
	-- Travel sits behind a button rather than on screen: a permanent map list
	-- would eat the middle of a phone screen, which is where the player looks.
	local map = button(actions, "Map", Text.get("map"), UDim2.new(1, -24, 0, 56), UDim2.new(0, 12, 0, 158), COLORS.gold)
	local crop = button(actions, "Crop", Text.cropName("Wheat"), UDim2.new(1, -24, 0, 24), UDim2.new(0, 12, 0, 220), COLORS.disabled)
	-- Rewards sits behind a button too, so the bottom-left thumb zone stays
	-- clear for the movement stick.
	local rewardsButton = button(actions, "RewardsButton", Text.get("rewards"), UDim2.new(1, -24, 0, 46), UDim2.new(0, 12, 0, 252), COLORS.gold)
	-- The character sheet lives behind this button: stats, skills, job and bag.
	local character = button(actions, "Character", Text.get("character"), UDim2.new(1, -24, 0, 56), UDim2.new(0, 12, 0, 306), COLORS.blue)

	-- Travel overlay: town plus every field. Built here, filled and wired by
	-- the client, which owns the intent calls.
	local travel = panel(gui, "TravelPanel", UDim2.new(0, 320, 0, 320), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5))
	travel.Visible = false
	travel.ZIndex = 10
	local travelTitle = label(travel, "TravelTitle", Text.get("chooseField"), UDim2.new(1, -80, 0, 30), UDim2.new(0, 12, 0, 8), 18)
	travelTitle.ZIndex = 11
	local close = button(travel, "CloseTravel", "X", UDim2.new(0, 38, 0, 30), UDim2.new(1, -46, 0, 8), COLORS.disabled)
	close.ZIndex = 11

	-- Kill flash, under the wave banner. Hidden most of the time; the client
	-- turns it on for a moment after a kill.
	local killFlash = label(gui, "KillFlash", "", UDim2.new(0, 380, 0, 36), UDim2.new(0.5, 0, 0, 246), 22)
	killFlash.AnchorPoint = Vector2.new(0.5, 0)
	killFlash.TextXAlignment = Enum.TextXAlignment.Center
	killFlash.TextColor3 = COLORS.gold
	killFlash.Visible = false
	-- Combat panel, bottom centre: the button the game is actually played
	-- with. Attack is the largest target on screen, because on a phone the
	-- thumb has to find it without looking.
	local combat = panel(gui, "Combat", UDim2.new(0, 190, 0, 244), UDim2.new(0.5, 0, 1, -24), Vector2.new(0.5, 1))
	local combatTitle = label(combat, "CombatTitle", Text.get("attackButton"), UDim2.new(1, -20, 0, 24), UDim2.new(0, 12, 0, 4), 16)
	combatTitle.TextColor3 = COLORS.muted
	local attack = button(combat, "Attack", Text.get("attackButton"), UDim2.new(1, -24, 0, 68), UDim2.new(0, 12, 0, 30), COLORS.gold)
	attack.TextSize = 26
	local autoAttack = button(combat, "AutoAttack", Text.get("auto"), UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 0, 104), COLORS.disabled)
	local autoPickup = button(combat, "AutoPickup", Text.get("pickup"), UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 0, 152), COLORS.disabled)
	local pickup = button(combat, "Pickup", Text.get("pickup"), UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 0, 200), COLORS.green)

	-- Character panel: one overlay, four tabs. Attributes, skills, job and the
	-- bag all live here rather than on the main screen, because a phone screen
	-- has room for one panel at a time and the game needs the rest.
	local charPanel = panel(gui, "CharPanel", UDim2.new(0, 340, 0, 430), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5))
	charPanel.Visible = false
	charPanel.ZIndex = 20
	local charTitle = label(charPanel, "CharTitle", Text.get("character"), UDim2.new(1, -80, 0, 30), UDim2.new(0, 12, 0, 8), 18)
	charTitle.ZIndex = 21
	local charClose = button(charPanel, "CloseChar", "X", UDim2.new(0, 38, 0, 30), UDim2.new(1, -46, 0, 8), COLORS.disabled)
	charClose.ZIndex = 21

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.Size = UDim2.new(1, -24, 0, 44)
	tabs.Position = UDim2.new(0, 12, 0, 44)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = 21
	tabs.Parent = charPanel

	local tabDefs = {
		{ id = "Stats", text = Text.get("stats") },
		{ id = "Skills", text = Text.get("skills") },
		{ id = "Job", text = Text.get("job") },
		{ id = "Bag", text = Text.get("inventory") },
	}
	for index, def in ipairs(tabDefs) do
		local width = 1 / #tabDefs
		local tab = button(tabs, "Tab_" .. def.id, def.text, UDim2.new(width, -6, 1, 0),
			UDim2.new((index - 1) * width, 3, 0, 0), COLORS.disabled)
		tab.TextSize = 16
		tab.ZIndex = 22
	end

	local charList = Instance.new("ScrollingFrame")
	charList.Name = "CharList"
	charList.Size = UDim2.new(1, -24, 1, -104)
	charList.Position = UDim2.new(0, 12, 0, 94)
	charList.BackgroundTransparency = 1
	charList.BorderSizePixel = 0
	charList.ScrollBarThickness = 6
	charList.ScrollingDirection = Enum.ScrollingDirection.Y
	charList.CanvasSize = UDim2.new(0, 0, 0, 0)
	charList.ZIndex = 21
	charList.Parent = charPanel

	local list = Instance.new("ScrollingFrame")
	list.Name = "FieldList"
	list.Size = UDim2.new(1, -24, 1, -54)
	list.Position = UDim2.new(0, 12, 0, 46)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ZIndex = 11
	list.Parent = travel

	return gui
end

-- The client builds the travel rows itself, so the palette and the button
-- factory are exported rather than duplicated.
Hud.COLORS = COLORS
Hud.button = button

return Hud

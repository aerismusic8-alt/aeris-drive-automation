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

-- The status panel sits in the top-right corner, which is where the Roblox
-- topbar keeps its experience controls and where the player list opens. The
-- panel used to clear the topbar by counting pixels down from the physical
-- screen top (IgnoreGuiInset was on), so on a phone with a taller topbar or a
-- notch it slid back under the buttons and could not be read.
--
-- ScreenInsets does that arithmetic for us: CoreUISafeInsets shrinks the whole
-- HUD to the area that is guaranteed to be clear of both the device cutout and
-- every core UI element, and it tracks the topbar when it hides or grows. The
-- offsets below are therefore measured from the safe area, not the screen, and
-- stay small.

-- Every visible word comes from here, so the language lives in one file.
local Text = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Text"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local HudLayout = require(script.Parent.HudLayout)

local Hud = {}

-- The screen the HUD is being built for. Panels are written in offset pixels
-- against a 1280x720 reference, and a phone is shorter than that, so the build
-- has to know which screen it is on before it can fit anything to it.
local function viewportSize(): (number, number)
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize.X, camera.ViewportSize.Y
	end
	return HudLayout.DESIGN_WIDTH, HudLayout.DESIGN_HEIGHT
end

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

-- The action menu, as written for a wide screen: one column, stacked, with the
-- heights and gaps it was designed with. On a phone this column is taller than
-- the screen, so the build reflows it to a grid instead; this table is what the
-- grid replaces, and keeping it explicit is what keeps the desktop layout
-- exactly as it was. `key` is the Text lookup, because the button names and the
-- translation keys do not match for Rewards and Character.
local ACTION_COLUMN = {
	{ id = "Axe", key = "axe", height = 56, color = COLORS.blue },
	{ id = "Farm", key = "farm", height = 56, color = COLORS.green },
	{ id = "Map", key = "map", height = 56, color = COLORS.gold },
	{ id = "Crop", key = "crop", height = 56, color = COLORS.disabled },
	{ id = "RewardsButton", key = "rewards", height = 56, color = COLORS.gold },
	{ id = "Character", key = "character", height = 56, color = COLORS.blue },
}

-- The combat panel. `panelHeight` is part of the form because the panel is a
-- fixed box the buttons sit in; writing the height next to the buttons keeps
-- the two from drifting apart. The wide form is exactly what shipped before,
-- and the compact form is what a phone can hold: the title goes, because it
-- only repeats the word already on the attack button, and the gaps tighten.
local COMBAT_COLUMN = {
	panelHeight = 286,
	rows = {
		{ id = "Attack", key = "attackButton", y = 72, height = 68, size = 26, color = COLORS.gold },
		{ id = "AutoAttack", key = "auto", y = 146, height = 44, size = 20, color = COLORS.disabled },
		{ id = "AutoPickup", key = "pickup", y = 194, height = 44, size = 20, color = COLORS.disabled },
		{ id = "Pickup", key = "pickup", y = 242, height = 40, size = 20, color = COLORS.green },
	},
}
-- On a phone the three utility toggles share a single row. Stacked they were
-- 232px of a 360px screen, which left no room above the attack button for
-- the skill bar -- the bar measured off the top of the screen. One row of
-- three still clears the 44px touch minimum and buys the bar its place.
local COMBAT_COMPACT = {
	panelHeight = 176,
	rows = {
		{ id = "Attack", key = "attackButton", y = 8, height = 68, size = 26, color = COLORS.gold },
		{ id = "AutoAttack", key = "auto", y = 84, height = 44, size = 20, color = COLORS.disabled, third = 1 },
		{ id = "AutoPickup", key = "pickup", y = 84, height = 44, size = 20, color = COLORS.disabled, third = 2 },
		{ id = "Pickup", key = "pickup", y = 84, height = 44, size = 20, color = COLORS.green, third = 3 },
	},
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

-- Every standing panel can fold down to its own title bar. A phone screen is
-- small and the middle of it is where the player is looking, so a panel that is
-- not needed right now shrinks to a bar and gets out of the way. The bar keeps
-- the fold button, so one tap brings the panel back.
--
-- `open` is the panel's full size, remembered so unfolding restores it exactly.
local FOLDS: { any } = {}

local function fold(target: Frame, label: string)
	local open = target.Size
	local b = button(target, "Fold", "\u{25BE}", UDim2.new(0, 34, 0, 30), UDim2.new(1, -40, 0, 4), COLORS.disabled)
	b.TextSize = 18
	b.ZIndex = 40
	table.insert(FOLDS, {
		target = target,
		label = label,
		open = open,
		openWidth = open.X,
		openHeight = open.Y,
	})
	return b
end

-- Fold or unfold every panel that has a fold button. Called from render, so
-- the screen follows the client's state rather than hiding things behind its
-- back. A folded panel keeps only its fold button, and the button says what it
-- will bring back.
function Hud.applyFolds(collapsed: { [string]: boolean })
	for _, entry in ipairs(FOLDS) do
		local target = entry.target
		local folded = collapsed[target.Name] == true
		local b = target:FindFirstChild("Fold")
		if folded then
			-- Fold once. A second pass would find every child already hidden and
			-- record an empty set, so unfolding would restore nothing and the
			-- panel would come back blank.
			if not entry.folded then
				entry.folded = true
				-- Remember exactly which children were on screen, so unfolding does
				-- not force-show a badge or a bar that some other rule had hidden.
				entry.hidden = {}
				for _, child in ipairs(target:GetChildren()) do
					if child ~= b and child.Visible then
						table.insert(entry.hidden, child)
						child.Visible = false
					end
				end
			end
			target.Size = UDim2.new(entry.openWidth.Scale, entry.openWidth.Offset, 0, 44)
			if b and b:IsA("TextButton") then
				b.Text = "\u{25B8}  " .. entry.label
				-- Folded, the button becomes the whole bar: full width, left aligned.
				b.Position = UDim2.new(0, 6, 0, 4)
				b.Size = UDim2.new(1, -12, 0, 36)
				b.TextXAlignment = Enum.TextXAlignment.Left
				b.BackgroundColor3 = COLORS.panelEdge
			end
		else
			for _, child in ipairs(entry.hidden or {}) do
				child.Visible = true
			end
			entry.hidden = nil
			entry.folded = false
			target.Size = entry.open
			if b and b:IsA("TextButton") then
				b.Text = "\u{25BE}"
				b.Position = UDim2.new(1, -40, 0, 4)
				b.Size = UDim2.new(0, 34, 0, 30)
				b.TextXAlignment = Enum.TextXAlignment.Center
				b.BackgroundColor3 = COLORS.disabled
			end
		end
	end
end

-- Whether a panel is folded, so a render step can avoid showing a child of a
-- panel that is currently put away.
function Hud.isFolded(collapsed: { [string]: boolean }, panelName: string): boolean
	return collapsed[panelName] == true
end

Hud.FOLDS = FOLDS

-- Build the screen once. Returns the ScreenGui.
function Hud.build(): ScreenGui
	local existing = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("AXArenaHUD")
	if existing then
		return existing :: ScreenGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AXArenaHUD"
	gui.ResetOnSpawn = false
	-- The HUD is laid out against the safe area, not the raw screen, so no
	-- panel can end up under the topbar or a device cutout.
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- How much screen there is, and therefore how much panel will fit on it.
	local _, viewportH = viewportSize()
	local compact = HudLayout.isShort(viewportH)
	local menuColumns = HudLayout.menuColumns(viewportH)
	local actionCellW = HudLayout.menuCellWidth(HudLayout.ACTION_MENU.panelWidth, menuColumns)
	local actionCellH = HudLayout.ACTION_MENU.cellHeight

	-- Stats, top right. The safe area already excludes the topbar, so the panel
	-- only needs a small margin. The old 58px offset existed to clear the topbar
	-- by hand, and on a phone with a taller topbar it was not enough: the panel
	-- slid back under the buttons. It used to sit top left, which is where the
	-- chat window is, and covered the chat's drag handle.
	local statsHeight = HudLayout.clampHeight("Stats", viewportH)
	local stats = panel(gui, "Stats", UDim2.new(0, HudLayout.PANEL_WIDTH.Stats, 0, statsHeight), UDim2.new(1, -12, 0, 8), Vector2.new(1, 0))
	-- The stats panel is the one panel worth keeping open while playing, so its
	-- fold button is a small caret in the corner rather than a title bar.
	fold(stats, Text.get("stats"))
	label(stats, "Coins", Text.get("coins") .. ": 0", UDim2.new(1, -58, 0, 30), UDim2.new(0, 12, 0, 8), 20)
	label(stats, "Level", Text.get("level") .. " 1", UDim2.new(1, -20, 0, 28), UDim2.new(0, 12, 0, 42), 18)
	label(stats, "Health", Text.get("health") .. " 100/100", UDim2.new(1, -20, 0, 28), UDim2.new(0, 12, 0, 72), 18)
	label(stats, "Field", Text.get("field") .. ": " .. Text.placeName("Town"), UDim2.new(1, -20, 0, 28), UDim2.new(0, 12, 0, 102), 18)
	-- The safe-field badge: only visible in the first field, where the player
	-- cannot die. It is the answer to "why am I not dying here".
	local safeBadge = label(stats, "SafeBadge", Text.get("safeField"), UDim2.new(1, -24, 0, 28), UDim2.new(0, 12, 0, 132), 14)
	safeBadge.TextColor3 = COLORS.green
	safeBadge.TextWrapped = true
	safeBadge.Visible = false
	label(stats, "Zone", Text.get("zone") .. ": " .. Text.placeName("Meadow"), UDim2.new(1, -20, 0, 26), UDim2.new(0, 12, 0, 160), 16)
	label(stats, "Rebirth", Text.get("rebirth") .. " 0", UDim2.new(1, -20, 0, 26), UDim2.new(0, 12, 0, 188), 16)

	-- The build stamp. It exists because there was no way to tell from inside
	-- the game which build was live: a publish can fail, and publishing
	-- identical bytes makes Roblox deduplicate them without a new version, so
	-- the running place looked the same either way. Reading this line answers
	-- that at a glance.
	local versionLabel = label(
		stats,
		"Version",
		Text.get("version") .. " " .. Config.Version,
		UDim2.new(1, -20, 0, 22),
		UDim2.new(0, 12, 0, 214),
		14
	)
	versionLabel.TextColor3 = COLORS.muted

	-- Quest tracker, top left. This is the answer to "I do not know what to do":
	-- one objective, always on screen, in Thai. Top left because the stats live
	-- top right and the travel list is centred, so it covers no control.
	local quest = panel(gui, "QuestPanel", UDim2.new(0, HudLayout.PANEL_WIDTH.QuestPanel, 0, HudLayout.PANEL_HEIGHT.QuestPanel), UDim2.new(0, 12, 0, 96), Vector2.new(0, 0))
	fold(quest, Text.get("quest"))
	local questTitle = label(quest, "QuestTitle", Text.get("quest"), UDim2.new(1, -56, 0, 26),
		UDim2.new(0, 8, 0, 6), 17)
	questTitle.TextColor3 = COLORS.gold
	local questBody = label(quest, "QuestBody", "", UDim2.new(1, -16, 0, 60), UDim2.new(0, 8, 0, 34), 15)
	questBody.TextWrapped = true
	questBody.TextYAlignment = Enum.TextYAlignment.Top

	-- Wave banner, top centre.
	local wave = panel(gui, "WavePanel", UDim2.new(0, HudLayout.PANEL_WIDTH.WavePanel, 0, HudLayout.PANEL_HEIGHT.WavePanel), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
	fold(wave, Text.get("wave"))
	local waveLabel = label(wave, "Wave", Text.get("wave") .. " 1", UDim2.new(1, -56, 1, 0), UDim2.new(0, 8, 0, 0), 20)
	waveLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Boss bar, just under the wave banner. Hidden unless a boss is alive, so
	-- it never steals attention from a normal wave.
	local boss = panel(gui, "BossPanel", UDim2.new(0, HudLayout.PANEL_WIDTH.BossPanel, 0, HudLayout.PANEL_HEIGHT.BossPanel), UDim2.new(0.5, 0, 0, 190), Vector2.new(0.5, 0))
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
	local rewardsHeight = HudLayout.clampHeight("Rewards", viewportH)
	local rewardsTop = HudLayout.centredTop(rewardsHeight, viewportH)
	local rewards = panel(gui, "Rewards", UDim2.new(0, HudLayout.PANEL_WIDTH.Rewards, 0, rewardsHeight),
		UDim2.new(0.5, 0, 0, rewardsTop), Vector2.new(0.5, 0))
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
	--
	-- Six stacked buttons is 412 pixels, which is taller than a phone. Rather
	-- than let the bottom of the menu run off the screen -- which is what put the
	-- character button out of reach -- the menu reflows to a grid when the screen
	-- is short, and keeps its single column when it is not.
	local actionsWidth = HudLayout.ACTION_MENU.panelWidth
	local actionsTop = HudLayout.ACTION_MENU.top
	local actionHeight = HudLayout.actionMenuHeight(viewportH)
	local actionsBottomOffset = compact and -HudLayout.SAFE_BOTTOM or -24
	local actions = panel(gui, "Actions", UDim2.new(0, actionsWidth, 0, actionHeight),
		UDim2.new(1, -16, 1, actionsBottomOffset), Vector2.new(1, 1))
	fold(actions, Text.get("menu"))
	local axeLabel = label(actions, "AxeCharges", Text.get("axe") .. ": 0/5", UDim2.new(1, -20, 0, 26),
		UDim2.new(0, 12, 0, 8), 16)
	axeLabel.TextColor3 = COLORS.muted

	for index, def in ipairs(ACTION_COLUMN) do
		local column = (index - 1) % menuColumns
		local row = math.floor((index - 1) / menuColumns)
		local x = 12 + column * (actionCellW + 8)
		local y = actionsTop + row * (actionCellH + 8)
		local text = def.id == "Crop" and Text.cropName("Wheat") or Text.get(def.key)
		local b = button(actions, def.id, text, UDim2.new(0, actionCellW, 0, actionCellH),
			UDim2.new(0, x, 0, y), def.color)
		if compact then
			b.TextSize = 17
		end
	end

	-- Travel overlay: town plus every field. Built here, filled and wired by
	-- the client, which owns the intent calls.
	local travelHeight = HudLayout.clampHeight("TravelPanel", viewportH)
	local travelTop = HudLayout.centredTop(travelHeight, viewportH)
	local travel = panel(gui, "TravelPanel", UDim2.new(0, HudLayout.PANEL_WIDTH.TravelPanel, 0, travelHeight),
		UDim2.new(0.5, 0, 0, travelTop), Vector2.new(0.5, 0))
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
	local combatForm = compact and COMBAT_COMPACT or COMBAT_COLUMN
	local combatBottomOffset = compact and -HudLayout.SAFE_BOTTOM or -24
	local combat = panel(gui, "Combat", UDim2.new(0, HudLayout.PANEL_WIDTH.Combat, 0, combatForm.panelHeight),
		UDim2.new(0.5, 0, 1, combatBottomOffset), Vector2.new(0.5, 1))
	fold(combat, Text.get("attackButton"))
	if not compact then
		local combatTitle = label(combat, "CombatTitle", Text.get("attackButton"), UDim2.new(1, -56, 0, 24),
			UDim2.new(0, 12, 0, 42), 16)
		combatTitle.TextColor3 = COLORS.muted
	end
	for _, row in ipairs(combatForm.rows) do
		local size = UDim2.new(1, -24, 0, row.height)
		local position = UDim2.new(0, 12, 0, row.y)
		if row.third then
			-- A third of the panel, so the three toggles fit one row.
			size = UDim2.new(1 / 3, -12, 0, row.height)
			position = UDim2.new((row.third - 1) / 3, 8, 0, row.y)
		end
		local b = button(combat, row.id, Text.get(row.key), size, position, row.color)
		b.TextSize = row.size
	end

	-- The skill bar. Skills could only be cast from the character sheet, so
	-- using one mid-fight meant opening a menu while something was hitting
	-- you -- which on a phone means never using one at all. The bar sits
	-- directly above the combat panel, built empty, and the client fills it
	-- with the skills the player has actually learned. It stays hidden until
	-- there is at least one, so a new player sees only the attack button.
	local skillBar = panel(gui, "SkillBar",
		UDim2.new(0, HudLayout.skillBarWidth(1), 0, HudLayout.skillBarHeight()),
		UDim2.new(0.5, 0, 1, -HudLayout.skillBarBottom(viewportH)), Vector2.new(0.5, 1))
	skillBar.BackgroundTransparency = 1
	skillBar.Visible = false
	local skillRow = Instance.new("Frame")
	skillRow.Name = "SkillRow"
	skillRow.Size = UDim2.new(1, 0, 1, 0)
	skillRow.BackgroundTransparency = 1
	skillRow.Parent = skillBar

	-- Character panel: one overlay, four tabs. Attributes, skills, job and the
	-- bag all live here rather than on the main screen, because a phone screen
	-- has room for one panel at a time and the game needs the rest.
	--
	-- This is the panel that made the safe-area arithmetic matter: at 430px it is
	-- taller than a phone viewport, and centring it put its close button above the
	-- top of the screen. It is capped to the room the screen has, and pinned to the
	-- safe area rather than the middle.
	local charHeight = HudLayout.clampHeight("CharPanel", viewportH)
	local charTop = HudLayout.centredTop(charHeight, viewportH)
	local charPanel = panel(gui, "CharPanel", UDim2.new(0, HudLayout.PANEL_WIDTH.CharPanel, 0, charHeight),
		UDim2.new(0.5, 0, 0, charTop), Vector2.new(0.5, 0))
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
-- The client sizes the skill bar as the hotbar changes, so it needs the same
-- arithmetic the HUD built the panel with.
Hud.Layout = HudLayout

return Hud

--[[
	File: MatchHud.client.luau

	Score bar, objective line, and the join menu.

	Reworked for a phone. The bar and the objective line used to be fixed
	heights with text scaled to fill them, which on a narrow screen squeezed
	the score into an unreadable row and pushed the objective under the notch.
	Both now take their height from a minimum plus the safe insets, and the bar
	has a compact form that drops the repeated labels and keeps the numbers, so
	a phone reads "3 | Buy Phase 12s | 2" where a desktop reads the full words.

	The menu card scales to the viewport instead of holding a fixed 430px, and
	its button is a full-width thumb target. The card also sits above the
	button cluster rather than behind it.

	The match logic is unchanged: the same attributes drive the same text, and
	the same camera-mode transitions happen on the same events.
]]--

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local state = game:GetService("ReplicatedStorage"):WaitForChild("MatchState")

-- The control settings are stored on player attributes that MobileControls
-- owns. Reading the names and bounds from that module rather than repeating the
-- literals here is what stops the panel and the cluster drifting apart.
local MobileControls = require(game:GetService("ReplicatedStorage"):WaitForChild("FourD").Common.MobileControls)

local gui = Instance.new("ScreenGui")
gui.Name = "MatchHud"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local BAR_HEIGHT = 38
local OBJECTIVE_HEIGHT = 32
local NARROW_BREAKPOINT = 620

local function label(parent, name, height, yOffset)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = UDim2.new(1, 0, 0, height)
	t.Position = UDim2.new(0.5, 0, 0, yOffset)
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.BackgroundColor3 = Color3.fromRGB(33, 36, 33)
	t.BackgroundTransparency = 0.1
	t.TextColor3 = Color3.fromRGB(243, 239, 226)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = t

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = t

	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MaxTextSize = 20
	textSize.MinTextSize = 11
	textSize.Parent = t

	return t
end

-- A single column, so the bar and the objective cannot overlap when either
-- grows on a small screen.
local column = Instance.new("Frame")
column.Name = "TopColumn"
column.BackgroundTransparency = 1
column.AnchorPoint = Vector2.new(0.5, 0)
column.Position = UDim2.new(0.5, 0, 0, 6)
column.Parent = gui

local columnLayout = Instance.new("UIListLayout")
columnLayout.FillDirection = Enum.FillDirection.Vertical
columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
columnLayout.Padding = UDim.new(0, 6)
columnLayout.Parent = column

local bar = label(column, "ScoreAndTime", BAR_HEIGHT, 0)
bar.LayoutOrder = 1

local objective = label(column, "Objective", OBJECTIVE_HEIGHT, 0)
objective.LayoutOrder = 2

local menu = Instance.new("Frame")
menu.Name = "MainMenu"
menu.Size = UDim2.fromScale(1, 1)
menu.BackgroundColor3 = Color3.fromRGB(25, 28, 25)
menu.BackgroundTransparency = 0.08
menu.Parent = gui

local card = Instance.new("Frame")
card.Size = UDim2.new(0.9, 0, 0, 230)
card.Position = UDim2.fromScale(0.5, 0.5)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.BackgroundColor3 = Color3.fromRGB(53, 58, 52)
card.Parent = menu

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 14)
cardCorner.Parent = card

local cardPadding = Instance.new("UIPadding")
cardPadding.PaddingLeft = UDim.new(0, 18)
cardPadding.PaddingRight = UDim.new(0, 18)
cardPadding.PaddingTop = UDim.new(0, 18)
cardPadding.PaddingBottom = UDim.new(0, 18)
cardPadding.Parent = card

local cardSize = Instance.new("UISizeConstraint")
cardSize.MaxSize = Vector2.new(460, 260)
cardSize.Parent = card

local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Vertical
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Padding = UDim.new(0, 10)
cardLayout.Parent = card

local heading = Instance.new("TextLabel")
heading.Name = "Heading"
heading.Size = UDim2.new(1, 0, 0, 52)
heading.BackgroundTransparency = 1
heading.Font = Enum.Font.GothamBold
heading.TextColor3 = Color3.fromRGB(246, 239, 216)
heading.TextScaled = true
heading.Text = state:GetAttribute("MapName") or "DUST DISTRICT"
heading.LayoutOrder = 1
heading.Parent = card

local headingSize = Instance.new("UITextSizeConstraint")
headingSize.MaxTextSize = 34
headingSize.MinTextSize = 18
headingSize.Parent = heading

local detail = Instance.new("TextLabel")
detail.Name = "Detail"
detail.Size = UDim2.new(1, 0, 0, 34)
detail.BackgroundTransparency = 1
detail.Font = Enum.Font.GothamMedium
detail.TextColor3 = Color3.fromRGB(214, 212, 200)
detail.TextScaled = true
detail.Text = "Join a team. Two players start a match."
detail.LayoutOrder = 2
detail.Parent = card

local detailSize = Instance.new("UITextSizeConstraint")
detailSize.MaxTextSize = 18
detailSize.MinTextSize = 12
detailSize.Parent = detail

local play = Instance.new("TextButton")
play.Name = "Play"
play.Size = UDim2.new(1, 0, 0, 62)
play.BackgroundColor3 = Color3.fromRGB(119, 138, 103)
play.TextColor3 = Color3.new(1, 1, 1)
play.Font = Enum.Font.GothamBold
play.TextScaled = true
play.Text = "PLAY"
play.Selectable = true
play.LayoutOrder = 3
play.Parent = card

local playCorner = Instance.new("UICorner")
playCorner.CornerRadius = UDim.new(0, 10)
playCorner.Parent = play

local playSize = Instance.new("UITextSizeConstraint")
playSize.MaxTextSize = 28
playSize.MinTextSize = 16
playSize.Parent = play

-- The touch cluster is the whole interface on a phone, and its size and
-- opacity are the two things a player wants to change: the default buttons sit
-- under the thumb for one hand size and not another, and an opaque cluster
-- hides the corner of the screen the player is watching. Both are stored as
-- player attributes, which MobileControls reads and follows live, so a change
-- made here applies to a cluster that is already on screen.
local SETTINGS_PREFIX = MobileControls.STORAGE_PREFIX

local settings = Instance.new("TextButton")
settings.Name = "Settings"
settings.Size = UDim2.new(1, 0, 0, 40)
settings.BackgroundColor3 = Color3.fromRGB(72, 80, 72)
settings.TextColor3 = Color3.fromRGB(243, 239, 226)
settings.Font = Enum.Font.GothamMedium
settings.TextScaled = true
settings.Text = "CONTROLS"
settings.Selectable = true
settings.LayoutOrder = 4
settings.Parent = card

local settingsCorner = Instance.new("UICorner")
settingsCorner.CornerRadius = UDim.new(0, 10)
settingsCorner.Parent = settings

local settingsSize = Instance.new("UITextSizeConstraint")
settingsSize.MaxTextSize = 20
settingsSize.MinTextSize = 12
settingsSize.Parent = settings

local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Size = UDim2.new(0.9, 0, 0, 200)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(53, 58, 52)
panel.Visible = false
panel.ZIndex = 4
panel.Parent = menu

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingLeft = UDim.new(0, 18)
panelPadding.PaddingRight = UDim.new(0, 18)
panelPadding.PaddingTop = UDim.new(0, 16)
panelPadding.PaddingBottom = UDim.new(0, 16)
panelPadding.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Vertical
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Padding = UDim.new(0, 10)
panelLayout.Parent = panel

local panelHeading = Instance.new("TextLabel")
panelHeading.Size = UDim2.new(1, 0, 0, 40)
panelHeading.BackgroundTransparency = 1
panelHeading.Font = Enum.Font.GothamBold
panelHeading.TextColor3 = Color3.fromRGB(246, 239, 216)
panelHeading.TextScaled = true
panelHeading.Text = "CONTROL SETTINGS"
panelHeading.LayoutOrder = 1
panelHeading.Parent = panel

local panelHeadingSize = Instance.new("UITextSizeConstraint")
panelHeadingSize.MaxTextSize = 26
panelHeadingSize.MinTextSize = 14
panelHeadingSize.Parent = panelHeading

-- A slider is a track plus a fill; the fill's width is the value and a tap
-- anywhere on the track sets it. That is enough for two settings and avoids a
-- dragging gesture that competes with the look drag on the same thumb.
local function slider(parent, order, caption, minimum, maximum, initial)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 56)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = parent

        local text = Instance.new("TextLabel")
        text.Name = "Caption"
        text.Size = UDim2.new(1, 0, 0, 22)
        text.BackgroundTransparency = 1
        text.Font = Enum.Font.GothamMedium
        text.TextColor3 = Color3.fromRGB(214, 212, 200)
        text.TextScaled = true
        text.TextXAlignment = Enum.TextXAlignment.Left
        text.Text = caption
        text.Parent = row

        local textSize = Instance.new("UITextSizeConstraint")
        textSize.MaxTextSize = 16
        textSize.MinTextSize = 10
        textSize.Parent = text

        local track = Instance.new("TextButton")
        track.Name = "Track"
        track.Size = UDim2.new(1, 0, 0, 26)
        track.Position = UDim2.new(0, 0, 0, 26)
        track.BackgroundColor3 = Color3.fromRGB(33, 36, 33)
        track.Text = ""
        track.AutoButtonColor = false
        track.Selectable = true
        track.Parent = row

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, 8)
        trackCorner.Parent = track

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(119, 138, 103)
        fill.Parent = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 8)
        fillCorner.Parent = fill

        local state = { Minimum = minimum, Maximum = maximum, Value = initial }
        local onChange = nil

        local function draw()
                local span = state.Maximum - state.Minimum
                local fraction = if span > 0 then (state.Value - state.Minimum) / span else 0
                fill.Size = UDim2.new(fraction, 0, 1, 0)
                text.Text = caption .. "  " .. string.format("%d%%", math.floor(state.Value * 100 + 0.5))
                if onChange then onChange(state.Value) end
        end

        state.Set = function(value)
                state.Value = math.clamp(value, state.Minimum, state.Maximum)
                draw()
        end
        state.SetChangeHandler = function(handler)
                onChange = handler
                draw()
        end
        state.Draw = draw
        state.Track = track

        return state
end

local scaleSlider = slider(panel, 2, "BUTTON SIZE", MobileControls.MIN_SCALE, MobileControls.MAX_SCALE, 1)
local alphaSlider = slider(panel, 3, "BUTTON OPACITY", MobileControls.MIN_TRANSPARENCY, MobileControls.MAX_TRANSPARENCY, 0)

local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.new(1, 0, 0, 44)
close.BackgroundColor3 = Color3.fromRGB(72, 80, 72)
close.TextColor3 = Color3.fromRGB(243, 239, 226)
close.Font = Enum.Font.GothamBold
close.TextScaled = true
close.Text = "DONE"
close.Selectable = true
close.LayoutOrder = 4
close.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 10)
closeCorner.Parent = close

local closeSize = Instance.new("UITextSizeConstraint")
closeSize.MaxTextSize = 20
closeSize.MinTextSize = 12
closeSize.Parent = close

local function refreshPanelScale()
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize
        if not viewport then return end
        panelScale.Scale = math.min(1, (viewport.X * 0.92) / 420, (viewport.Y * 0.82) / 220)
end

-- Sliders read the stored value so the panel opens showing what is in effect,
-- including a value written by an earlier session.
scaleSlider.Set(tonumber(player:GetAttribute(SETTINGS_PREFIX .. "Scale")) or 1)
alphaSlider.Set(tonumber(player:GetAttribute(SETTINGS_PREFIX .. "Transparency")) or 0)

scaleSlider.SetChangeHandler(function(value)
        player:SetAttribute(SETTINGS_PREFIX .. "Scale", value)
end)
alphaSlider.SetChangeHandler(function(value)
        player:SetAttribute(SETTINGS_PREFIX .. "Transparency", value)
end)

-- The track is narrower than the row, and a tap near its right edge means
-- "almost maximum" rather than "maximum", so the fraction is taken from where
-- on the track the input landed.
local function bindSlider(state)
        state.Track.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1
                        and input.UserInputType ~= Enum.UserInputType.Touch then
                        return
                end

                local x = input.Position.X - state.Track.AbsolutePosition.X
                local width = state.Track.AbsoluteSize.X
                if width <= 0 then return end

                local fraction = math.clamp(x / width, 0, 1)
                state.Set(state.Minimum + fraction * (state.Maximum - state.Minimum))
        end)
end

bindSlider(scaleSlider)
bindSlider(alphaSlider)

settings.Activated:Connect(function()
        menu.Visible = true
        card.Visible = false
        panel.Visible = true
        refreshPanelScale()
end)

close.Activated:Connect(function()
        panel.Visible = false
        card.Visible = true
end)

local function refreshScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	if not viewport then return end

	-- Fit the card to the viewport rather than let it clip on a phone.
	local scale = math.min(1, (viewport.X * 0.92) / 460, (viewport.Y * 0.82) / 260)
	cardScale.Scale = scale

	-- The top column spans the safe width, inset from the edges.
	column.Size = UDim2.new(0.94, 0, 0, BAR_HEIGHT + OBJECTIVE_HEIGHT + 6)
	local narrow = viewport.X < NARROW_BREAKPOINT
	columnLayout.Padding = UDim.new(0, if narrow then 4 else 6)
end

player.CameraMode = Enum.CameraMode.Classic
play.Activated:Connect(function()
	state.JoinMatch:FireServer()
	menu.Visible = false
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end)

-- The server admits a player on arrival, so the menu must not sit on top of a
-- game that is already running. It hides as soon as the player has a character,
-- which is the same moment the round loop can place them. The button still
-- works for anyone who wants to dismiss it early.
local function hideMenuWhenPlaying()
	if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
		menu.Visible = false
	end
end

if player.Character then hideMenuWhenPlaying() end
player.CharacterAdded:Connect(hideMenuWhenPlaying)

-- The map changes between matches, so the heading follows it rather than
-- staying on whatever map the player first saw.
state:GetAttributeChangedSignal("MapName"):Connect(function()
        heading.Text = state:GetAttribute("MapName") or heading.Text
end)

local function update()
	local phase = state:GetAttribute("Phase") or "Waiting for Players"
	local team = player.Team and player.Team.Name or "Unassigned"
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	local narrow = viewport and viewport.X < NARROW_BREAKPOINT

	local attackers = state:GetAttribute("AttackersScore") or 0
	local defenders = state:GetAttribute("DefendersScore") or 0
	local timer = state:GetAttribute("Timer") or 0

	if narrow then
		bar.Text = "A " .. attackers .. "  |  " .. phase .. "  " .. timer .. "s  |  D " .. defenders
	else
		bar.Text = "ATTACKERS " .. attackers .. "   |   " .. phase .. "  " .. timer .. "s   |   DEFENDERS " .. defenders
	end

	local goal = "Waiting for Players"
	-- One player is a practice round, and saying so is the difference between
	-- "this game is broken" and "I am warming up alone on purpose".
	local practice = state:GetAttribute("Practice") == true
	if phase == "Warm-up" then goal = if practice then "Practice round: warm-up, you are alone" else "Warm-up: get ready" end
	if phase == "Buy Phase" then goal = "Buy Phase: prepare your weapon" end
	if phase == "Combat" then goal = if team == "Attackers" then "Reach Bomb Site A or B" else "Defend the Bomb Sites" end
	if phase == "Planted" then goal = if team == "Attackers" then "Protect the Bomb" else "Defuse the Bomb" end
	if phase == "Round End" or phase == "Match Result" then goal = state:GetAttribute("Reason") or "Round End" end

	local money = player:GetAttribute("Money") or 0
	if narrow then
		objective.Text = goal .. "  |  $" .. money
	else
		objective.Text = team .. "  |  " .. goal
			.. "  |  ALIVE " .. (state:GetAttribute("AliveAttackers") or 0)
			.. "-" .. (state:GetAttribute("AliveDefenders") or 0)
			.. "  |  $" .. money
	end

	-- The range HUD is the tutorial overlay; it has no place once a match is
	-- running, so it is hidden whenever this HUD is drawing.
	local old = player.PlayerGui:FindFirstChild("RangeHud")
	if old then
		local title = old:FindFirstChild("Title")
		local hint = old:FindFirstChild("Hint")
		if title then title.Visible = false end
		if hint then hint.Visible = false end
	end
end

for _, attribute in ipairs({ "Phase", "Timer", "AttackersScore", "DefendersScore", "AliveAttackers", "AliveDefenders", "BombStatus", "Reason" }) do
	state:GetAttributeChangedSignal(attribute):Connect(update)
end

player:GetAttributeChangedSignal("Money"):Connect(update)
player:GetPropertyChangedSignal("Team"):Connect(update)

player:GetAttributeChangedSignal("Alive"):Connect(function()
	if player:GetAttribute("Alive") == true then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then workspace.CurrentCamera.CameraSubject = h end
	elseif not menu.Visible then
		player.CameraMode = Enum.CameraMode.Classic
		for _, other in ipairs(Players:GetPlayers()) do
			local h = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if other ~= player and other.Team == player.Team and other:GetAttribute("Alive") and h then
				workspace.CurrentCamera.CameraSubject = h
				break
			end
		end
	end
	update()
end)

local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshPanelScale)
end

refreshScale()
update()

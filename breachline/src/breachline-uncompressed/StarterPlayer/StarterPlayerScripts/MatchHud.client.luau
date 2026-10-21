local Players = game:GetService("Players")
local player = Players.LocalPlayer
local state = game:GetService("ReplicatedStorage"):WaitForChild("MatchState")
local gui = Instance.new("ScreenGui")
gui.Name = "MatchHud"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")
local function label(parent, name, size, position, anchor)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.Size = size
    t.Position = position
    t.AnchorPoint = anchor
    t.BackgroundColor3 = Color3.fromRGB(33, 36, 33)
    t.BackgroundTransparency = .1
    t.TextColor3 = Color3.fromRGB(243, 239, 226)
    t.Font = Enum.Font.GothamBold
    t.TextScaled = true
    t.Parent = parent
    return t
end
local bar = label(gui, "ScoreAndTime", UDim2.new(.78, 0, 0, 40), UDim2.new(.5, 0, 0, 6), Vector2.new(.5, 0))
local objective = label(gui, "Objective", UDim2.new(.78, 0, 0, 35), UDim2.new(.5, 0, 0, 51), Vector2.new(.5, 0))
local menu = Instance.new("Frame")
menu.Name = "MainMenu"
menu.Size = UDim2.fromScale(1, 1)
menu.BackgroundColor3 = Color3.fromRGB(25, 28, 25)
menu.BackgroundTransparency = .08
menu.Parent = gui
local card = Instance.new("Frame")
card.Size = UDim2.new(.8, 0, 0, 210)
card.Position = UDim2.fromScale(.5, .5)
card.AnchorPoint = Vector2.new(.5, .5)
card.BackgroundColor3 = Color3.fromRGB(53, 58, 52)
card.Parent = menu
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(430, 220)
limit.Parent = card
local heading = label(card, "Heading", UDim2.new(1, -30, 0, 60), UDim2.new(.5, 0, 0, 24), Vector2.new(.5, 0))
heading.Text = "DUST DISTRICT"
local detail = label(card, "Detail", UDim2.new(1, -30, 0, 40), UDim2.new(.5, 0, 0, 88), Vector2.new(.5, 0))
detail.Text = "Join a team. Two players start a match."
local play = Instance.new("TextButton")
play.Name = "Play"
play.Size = UDim2.new(1, -50, 0, 54)
play.Position = UDim2.new(.5, 0, 1, -14)
play.AnchorPoint = Vector2.new(.5, 1)
play.BackgroundColor3 = Color3.fromRGB(119, 138, 103)
play.TextColor3 = Color3.new(1, 1, 1)
play.Font = Enum.Font.GothamBold
play.TextScaled = true
play.Text = "PLAY"
play.Selectable = true
play.Parent = card
player.CameraMode = Enum.CameraMode.Classic
play.Activated:Connect(function()
    state.JoinMatch:FireServer()
    menu.Visible = false
    player.CameraMode = Enum.CameraMode.LockFirstPerson
end)
local function update()
    local phase = state:GetAttribute("Phase") or "Waiting for Players"
    local team = player.Team and player.Team.Name or "Unassigned"
    local narrow = workspace.CurrentCamera.ViewportSize.X < 600
    if narrow then
        bar.Text = "A " .. (state:GetAttribute("AttackersScore") or 0) .. " | " .. phase .. " " .. (state:GetAttribute("Timer") or 0) .. "s | D " .. (state:GetAttribute("DefendersScore") or 0)
    else
        bar.Text = "ATTACKERS " .. (state:GetAttribute("AttackersScore") or 0) .. "   |   " .. phase .. "  " .. (state:GetAttribute("Timer") or 0) .. "s   |   DEFENDERS " .. (state:GetAttribute("DefendersScore") or 0)
    end
    local goal = "Waiting for Players"
    if phase == "Warm-up" then goal = "Warm-up: get ready" end
    if phase == "Buy Phase" then goal = "Buy Phase: prepare your weapon" end
    if phase == "Combat" then goal = if team == "Attackers" then "Reach Bomb Site A or B" else "Defend the Bomb Sites" end
    if phase == "Planted" then goal = if team == "Attackers" then "Protect the Bomb" else "Defuse the Bomb" end
    if phase == "Round End" or phase == "Match Result" then goal = state:GetAttribute("Reason") or "Round End" end
    if narrow then
        objective.Text = goal .. " | $" .. (player:GetAttribute("Money") or 0)
    else
        objective.Text = team .. "  |  " .. goal .. "  |  ALIVE " .. (state:GetAttribute("AliveAttackers") or 0) .. "-" .. (state:GetAttribute("AliveDefenders") or 0) .. "  |  $" .. (player:GetAttribute("Money") or 0)
    end
    local old = player.PlayerGui:FindFirstChild("RangeHud")
    if old then
        local title = old:FindFirstChild("Title")
        local hint = old:FindFirstChild("Hint")
        if title then title.Visible = false end
        if hint then hint.Visible = false end
    end
end
for _, attribute in ipairs({"Phase", "Timer", "AttackersScore", "DefendersScore", "AliveAttackers", "AliveDefenders", "BombStatus", "Reason"}) do
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
update()
-- One server-owned round loop; the client only requests admission.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.MatchModules.RoundRules)
local state = ReplicatedStorage.MatchState
local range = workspace.PrototypeRange
local sites = range.BombSites
local participants = {}
local roundId = 0
local resolved = false
local bombPart = nil
local bombSite = ""
local pendingResult = nil
Players.CharacterAutoLoads = false

local function countPlayers()
    local n = 0
    for player in pairs(participants) do
        if player.Parent == Players then n += 1 end
    end
    return n
end
local function alive(teamName)
    local n = 0
    for player in pairs(participants) do
        if player.Parent == Players and player.Team and player.Team.Name == teamName and player:GetAttribute("Alive") == true then n += 1 end
    end
    return n
end
local function updateAlive()
    state:SetAttribute("AliveAttackers", alive("Attackers"))
    state:SetAttribute("AliveDefenders", alive("Defenders"))
end
local function setPhase(name, seconds)
    state:SetAttribute("Phase", name)
    state:SetAttribute("Timer", seconds)
end
local function clearBomb()
    if bombPart then bombPart:Destroy() end
    bombPart = nil
    bombSite = ""
    state:SetAttribute("BombStatus", "Idle")
    state:SetAttribute("BombSite", "")
end
local function assignTeam(player)
    local a, d = 0, 0
    for other in pairs(participants) do
        if other ~= player and other.Team == Teams.Attackers then a += 1 end
        if other ~= player and other.Team == Teams.Defenders then d += 1 end
    end
    player.Team = if a <= d then Teams.Attackers else Teams.Defenders
    player.Neutral = false
    player:SetAttribute("Money", 800)
    player:SetAttribute("Alive", false)
end
local function spawnForRound(player)
    if player.Parent ~= Players then return end
    player:SetAttribute("Armor", false)
    player:SetAttribute("HasSMG", false)
    player:LoadCharacter()
    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart", 8)
    local humanoid = character:WaitForChild("Humanoid", 8)
    if not root or not humanoid then return end
    local spawn = range:FindFirstChild(player.Team.Name .. " Spawn")
    if spawn then character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0)) end
    player:SetAttribute("Alive", true)
    humanoid.Died:Connect(function()
        if player.Character ~= character then return end
        player:SetAttribute("Alive", false)
        updateAlive()
    end)
end
local function validInteract(player, position, teamName)
    if not participants[player] or player.Team ~= Teams[teamName] or player:GetAttribute("Alive") ~= true then return false end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    return root ~= nil and humanoid ~= nil and humanoid.Health > 0 and (root.Position - position).Magnitude <= 12
end
local function plant(player, site)
    if state:GetAttribute("Phase") ~= "Combat" or bombPart then return end
    if not validInteract(player, site.Position, "Attackers") then return end
    bombSite = site.Name
    bombPart = Instance.new("Part")
    bombPart.Name = "PlantedBomb"
    bombPart.Anchored = true
    bombPart.Size = Vector3.new(2, 1, 2)
    bombPart.Position = site.Position + Vector3.new(0, .7, 0)
    bombPart.Color = Color3.fromRGB(76, 79, 67)
    bombPart.Material = Enum.Material.Metal
    bombPart.Parent = range
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "DefusePrompt"
    prompt.ActionText = "Defuse bomb"
    prompt.ObjectText = "Bomb at " .. site.Name
    prompt.HoldDuration = 5
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    prompt.Parent = bombPart
    local thisBomb = bombPart
    prompt.Triggered:Connect(function(defender)
        if bombPart ~= thisBomb or state:GetAttribute("Phase") ~= "Planted" then return end
        if not validInteract(defender, thisBomb.Position, "Defenders") then return end
        state:SetAttribute("BombStatus", "Defused")
        pendingResult = {"Defenders", "Bomb Defused"}
        prompt.Enabled = false
    end)
    state:SetAttribute("BombStatus", "Planted")
    state:SetAttribute("BombSite", bombSite)
    setPhase("Planted", Rules.BombSeconds)
end
for _, site in ipairs(sites:GetChildren()) do
    site.PlantPrompt.Triggered:Connect(function(player) plant(player, site) end)
end
state.JoinMatch.OnServerEvent:Connect(function(player)
    if participants[player] then return end
    participants[player] = true
    assignTeam(player)
    -- Late arrivals wait until the next buy phase.
    if player.Character == nil then spawnForRound(player) end
    player:SetAttribute("Alive", false)
    updateAlive()
end)
Players.PlayerRemoving:Connect(function(player)
    participants[player] = nil
    updateAlive()
end)

local function countdown(phase, seconds, activeRound)
    setPhase(phase, seconds)
    for left = seconds, 1, -1 do
        if activeRound and countPlayers() < Rules.MinimumPlayers then return false end
        if activeRound and pendingResult then return true end
        if activeRound and (phase == "Combat" or phase == "Planted") then
            local winner, reason = Rules.winner(phase, state:GetAttribute("BombStatus"), alive("Attackers"), alive("Defenders"), left)
            if winner then pendingResult = {winner, reason}; return true end
            if phase == "Combat" and bombPart then return true end
        end
        state:SetAttribute("Timer", left)
        task.wait(1)
    end
    state:SetAttribute("Timer", 0)
    return true
end
local function finishRound(winner, reason)
    if resolved then return end
    resolved = true
    state:SetAttribute("Reason", reason)
    state:SetAttribute(winner .. "Score", (state:GetAttribute(winner .. "Score") or 0) + 1)
    for player in pairs(participants) do
        if player.Parent == Players then
            local bonus = if player.Team and player.Team.Name == winner then 1500 else 900
            player:SetAttribute("Money", (player:GetAttribute("Money") or 0) + bonus)
        end
    end
    setPhase("Round End", Rules.EndSeconds)
end

task.spawn(function()
    while true do
        clearBomb()
        pendingResult = nil
        while countPlayers() < Rules.MinimumPlayers do
            setPhase("Waiting for Players", 0)
            task.wait(1)
        end
        countdown("Warm-up", Rules.WarmupSeconds, false)
        if countPlayers() < Rules.MinimumPlayers then continue end
        roundId += 1
        resolved = false
        state:SetAttribute("Round", roundId)
        state:SetAttribute("Reason", "")
        clearBomb()
        for player in pairs(participants) do
            if player.Parent == Players then spawnForRound(player) end
        end
        updateAlive()
        if not countdown("Buy Phase", Rules.BuySeconds, true) then continue end
        if countPlayers() < Rules.MinimumPlayers then continue end
        if not countdown("Combat", Rules.RoundSeconds, true) then continue end
        if bombPart and not pendingResult then
            countdown("Planted", Rules.BombSeconds, true)
            if not pendingResult and countPlayers() >= Rules.MinimumPlayers then
                pendingResult = {"Attackers", "Bomb Detonated"}
            end
        elseif not pendingResult and countPlayers() >= Rules.MinimumPlayers then
            local winner, reason = Rules.winner("Combat", "Idle", alive("Attackers"), alive("Defenders"), 0)
            pendingResult = {winner or "Defenders", reason or "Time Expired"}
        end
        if countPlayers() < Rules.MinimumPlayers then continue end
        finishRound(pendingResult[1], pendingResult[2])
        countdown("Round End", Rules.EndSeconds, false)
        if state:GetAttribute("AttackersScore") >= Rules.ScoreToWin or state:GetAttribute("DefendersScore") >= Rules.ScoreToWin then
            local champ = if state:GetAttribute("AttackersScore") > state:GetAttribute("DefendersScore") then "Attackers" else "Defenders"
            state:SetAttribute("Reason", champ .. " win the match")
            countdown("Match Result", 10, false)
            state:SetAttribute("AttackersScore", 0)
            state:SetAttribute("DefendersScore", 0)
            roundId = 0
        elseif roundId == 3 then
            for player in pairs(participants) do
                if player.Team == Teams.Attackers then player.Team = Teams.Defenders
                elseif player.Team == Teams.Defenders then player.Team = Teams.Attackers end
            end
        end
    end
end)
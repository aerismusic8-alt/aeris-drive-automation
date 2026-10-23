-- One server-owned round loop; the client only requests admission.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.MatchModules.RoundRules)
local MapRegistry = require(ReplicatedStorage.MatchModules.MapRegistry)
local state = ReplicatedStorage.MatchState

-- Which maps the place carries. Read out of Workspace rather than listed here,
-- so adding a map to the build is all it takes to put it in the rotation.
local maps = MapRegistry.collect(workspace)
local activeMap = nil

---Make `map` the one a round is played on. Its spawns and plant prompts are
---switched on and every other map's are switched off, so a player cannot spawn
---into or plant on a map that is not being played.
local function selectMap(map)
    if not map then return end
    activeMap = map
    for _, other in ipairs(maps) do
        if other.id == map.id then
            MapRegistry.activate(other.model)
        else
            MapRegistry.deactivate(other.model)
        end
    end
    state:SetAttribute("MapId", map.id)
    state:SetAttribute("MapName", map.name)
end

---The map after the current one in rotation order, wrapping at the end. Called
---with no map selected yet it picks the first, so the server always has a map
---to start on.
local function advanceMap()
    selectMap(MapRegistry.next(maps, activeMap and activeMap.id or nil))
end

local participants = {}
local roundId = 0
local resolved = false
local bombPart = nil
local bombSite = ""
local pendingResult = nil
-- Consecutive rounds lost by each team, counting the round just finished. It is
-- what the loss bonus grows with, and it is reset on a win so the bonus tracks
-- a live streak rather than a season total.
local lossStreak = { Attackers = 0, Defenders = 0 }
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
---How many players the current round needs. `count` is passed in rather than
---read again so the gate and the decision that used it cannot disagree.
local function requiredPlayers(count)
    return Rules.requiredPlayers(count)
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
    player:SetAttribute("Money", Rules.StartMoney)
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
    -- Team can be nil for a player who joined while the round loop was between
    -- assignments. Reading it through a guard keeps that from raising, because an
    -- error here used to propagate out of the round loop and end the match.
    local teamName = player.Team and player.Team.Name
    local spawn = teamName and activeMap and activeMap.model:FindFirstChild(teamName .. " Spawn")
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
    bombPart.Parent = activeMap and activeMap.model or workspace
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
---Bind a plant prompt to the round. The prompt belongs to a map, and the map
---changes every few rounds, so the site is read back from the prompt when it
---fires rather than captured here -- a captured site would still point at the
---map the match has left.
local function bindSite(site)
    if not site.PlantPrompt then return end
    site.PlantPrompt.Triggered:Connect(function(player)
        plant(player, site)
    end)
end

-- Bind the sites of every map once. Only the active map's prompts are enabled,
-- so a trigger can only arrive from the map being played, but binding all of
-- them means a map added to the rotation needs no rebinding.
for _, map in ipairs(maps) do
    local folder = map.model:FindFirstChild("BombSites")
    if folder then
        for _, site in ipairs(folder:GetChildren()) do
            bindSite(site)
        end
    end
end

-- Pick a map before anything can spawn. Until this runs every map's spawns are
-- enabled, so a player joining during "Waiting for Players" could be placed on a
-- map the match is not being played on.
advanceMap()

---Put `player` in the match. Both the menu's PLAY button and the automatic
---admission below go through here, so there is one admission path.
local function admit(player)
    if participants[player] then return end
    if player.Parent ~= Players then return end
    participants[player] = true
    assignTeam(player)
    -- A player gets a character on arrival rather than waiting for a round to
    -- start, so joining never leaves someone staring at a menu. The round loop
    -- respawns everyone at the start of each round regardless.
    if player.Character == nil then
        spawnForRound(player)
    else
        player:SetAttribute("Alive", true)
    end
    updateAlive()
end

-- A player is admitted as soon as they arrive, not when a button is pressed.
-- The game used to wait for the client to fire JoinMatch, which meant a player
-- whose HUD never drew -- a client script error, a slow device, a missed tap --
-- had no character at all, because CharacterAutoLoads is off. That reads as
-- "loads for minutes and never gets in". The menu still fires JoinMatch; it is
-- now a no-op for someone already admitted rather than the only way in.
Players.PlayerAdded:Connect(function(player)
    admit(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
    admit(player)
end

state.JoinMatch.OnServerEvent:Connect(admit)
Players.PlayerRemoving:Connect(function(player)
    participants[player] = nil
    updateAlive()
end)

local function countdown(phase, seconds, activeRound)
    setPhase(phase, seconds)
    for left = seconds, 1, -1 do
        if activeRound and countPlayers() < requiredPlayers(countPlayers()) then return false end
        if activeRound and pendingResult then return true end
        if activeRound and (phase == "Combat" or phase == "Planted") then
            local winner, reason = Rules.winner(phase, state:GetAttribute("BombStatus"), alive("Attackers"), alive("Defenders"), left, state:GetAttribute("Practice") == true)
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
    -- The streak is advanced for the loser and cleared for the winner before the
    -- payout reads it, so the round that was just lost is counted in its own
    -- bonus and a win starts the next loss back at the base rate.
    for team in pairs(lossStreak) do
        if team == winner then lossStreak[team] = 0 else lossStreak[team] += 1 end
    end
    for player in pairs(participants) do
        if player.Parent == Players then
            local won = player.Team ~= nil and player.Team.Name == winner
            local bonus = Rules.roundReward(won, lossStreak[player.Team and player.Team.Name or ""])
            player:SetAttribute("Money", Rules.addMoney(player:GetAttribute("Money"), bonus))
        end
    end
    setPhase("Round End", Rules.EndSeconds)
end

---One pass of the match loop: a round, its result, and the rotation that
---follows. It is a function so the driver below can catch a failure and start a
---fresh round instead of leaving the server with no loop at all.
local function roundLoopIteration()
    clearBomb()
    pendingResult = nil
    while countPlayers() < requiredPlayers(countPlayers()) do
        setPhase("Waiting for Players", 0)
        state:SetAttribute("Practice", false)
        task.wait(1)
    end
    -- A match is played on one map from start to finish; the rotation moves
    -- between matches, not between rounds, so both teams learn the map they
    -- are on before it changes under them. The first match uses the map
    -- selected at startup.
    -- One player is a practice round. The flag is what the HUD keys off,
    -- and it is recomputed every round so a second player joining turns
    -- practice off without a restart.
    local practice = countPlayers() < Rules.MinimumPlayers
    state:SetAttribute("Practice", practice)
    countdown("Warm-up", Rules.WarmupSeconds, false)
    if countPlayers() < requiredPlayers(countPlayers()) then return end
    roundId += 1
    resolved = false
    state:SetAttribute("Round", roundId)
    state:SetAttribute("Reason", "")
    clearBomb()
    for player in pairs(participants) do
        if player.Parent == Players then spawnForRound(player) end
    end
    updateAlive()
    if not countdown("Buy Phase", Rules.BuySeconds, true) then return end
    if countPlayers() < requiredPlayers(countPlayers()) then return end
    if not countdown("Combat", Rules.RoundSeconds, true) then return end
    if bombPart and not pendingResult then
        countdown("Planted", Rules.BombSeconds, true)
        if not pendingResult and countPlayers() >= requiredPlayers(countPlayers()) then
            pendingResult = {"Attackers", "Bomb Detonated"}
        end
    elseif not pendingResult and countPlayers() >= requiredPlayers(countPlayers()) then
        local winner, reason = Rules.winner("Combat", "Idle", alive("Attackers"), alive("Defenders"), 0, practice)
        pendingResult = {winner or "Defenders", reason or "Time Expired"}
    end
    if countPlayers() < requiredPlayers(countPlayers()) then return end
    finishRound(pendingResult[1], pendingResult[2])
    countdown("Round End", Rules.EndSeconds, false)
    if state:GetAttribute("AttackersScore") >= Rules.ScoreToWin or state:GetAttribute("DefendersScore") >= Rules.ScoreToWin then
        local champ = if state:GetAttribute("AttackersScore") > state:GetAttribute("DefendersScore") then "Attackers" else "Defenders"
        state:SetAttribute("Reason", champ .. " win the match")
        countdown("Match Result", 10, false)
        state:SetAttribute("AttackersScore", 0)
        state:SetAttribute("DefendersScore", 0)
        roundId = 0
        -- A new match starts a fresh economy, so neither team carries a bonus
        -- earned in the match that just ended.
        lossStreak.Attackers = 0
        lossStreak.Defenders = 0
        -- The next match is played on the next map in the rotation.
        advanceMap()
    elseif roundId == 3 then
        for player in pairs(participants) do
            if player.Team == Teams.Attackers then player.Team = Teams.Defenders
            elseif player.Team == Teams.Defenders then player.Team = Teams.Attackers end
        end
    end
end

-- The loop must never end. An uncaught error used to kill the thread that runs
-- the match, which left a live server where no round ever starts again: players
-- join, get a character, and nothing happens for minutes. A failure is logged
-- and the next round begins instead.
task.spawn(function()
    while true do
        local ok, err = pcall(roundLoopIteration)
        if not ok then
            warn(string.format("[Breachline] round loop error, continuing: %s", tostring(err)))
            task.wait(2)
        end
    end
end)
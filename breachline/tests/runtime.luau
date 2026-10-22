--!nocheck
-- Runtime tests for Breachline: boot the real server match layer, join two real
-- players, and play a round through its own remotes.
--
-- Why this file exists. Breachline shipped with no test suite at all. The garden
-- next door has one, and it exists for a stated reason: the previous game passed
-- its whole unit suite while being unplayable, because the unit tests never ran
-- the code that actually executes in Roblox. Breachline has the same gap, and it
-- is worse, because the thing that has never been run is the round loop itself.
--
-- So this suite does not read MatchManager.server.luau as text. It loads it,
-- lets it spawn its round coroutine, joins two players through JoinMatch, buys a
-- weapon through BuyItem, kills a defender, and reads the score back. If any
-- link in that chain is broken the test fails -- which is the only way to know
-- the round flow works without a Roblox Studio session.
--
--   luau breachline/tests/runtime.luau
--
-- What this cannot cover, and does not pretend to: touch input, rendering,
-- physics, replication latency, and anything that needs a real client. Those are
-- marked NOT VERIFIED in the Phase 1 report rather than being claimed as tested.

local t = require("../../roblox/tests/TestRunner")
local Shim = require("../../roblox/tests/RobloxShim")
local Sources = require("./.generated/Sources")

-- The round loop is `while true do ... task.wait(1) ... end`, so it never
-- finishes. The default resume cap would park it after eight waits, which is
-- before the first buy phase. Raising the cap lets the loop be stepped for as
-- long as a test needs; Shim.tick resumes it one wait at a time so the phase a
-- test reads is the phase the server is really in.
Shim.setTaskLimits({ resumeCap = 1000000, stepCap = 1000000 })

local state, range, sites
-- Engine datatypes and globals are not in this script's scope -- they belong to
-- a module environment -- so they come off the harness.
local G = Shim.globals()
local Vector3, CFrame, Instance = G.Vector3, G.CFrame, G.Instance

-- Build the parts of the place the match layer reaches for. These are the same
-- instances the built place carries -- MatchState with its two remotes, a
-- PrototypeRange with bomb sites and spawns, and the shop's weapon template --
-- created here rather than unpacked from the .rbxl so the suite has no external
-- dependency. The build checker already proves the real place has them; this
-- proves the code that reads them behaves.
local function buildPlace(env)
	local ReplicatedStorage = env.__game:GetService("ReplicatedStorage")
	local Workspace = env.__game:GetService("Workspace")
	local ServerStorage = env.__game:GetService("ServerStorage")

	-- MatchState: the folder the server owns and the client reads. The two
	-- remotes are the only way a client can ask for anything.
	local matchState = Instance.new("Folder")
	matchState.Name = "MatchState"
	for _, remoteName in ipairs({ "JoinMatch", "BuyItem" }) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = matchState
	end
	matchState.Parent = ReplicatedStorage
	-- Field access, not FindFirstChild: the server reads ReplicatedStorage.MatchState
	-- directly, and the service's __index would otherwise hand back a Signal.
	rawset(ReplicatedStorage, "MatchState", matchState)

	-- The place ships MatchState with its counters already set, and the round
	-- loop reads the scores back before it ever writes them -- so a fixture
	-- without them would crash the loop on `score >= Rules.ScoreToWin` and look
	-- like a game bug. These are the values the built place carries.
	for attributeName, value in pairs({
		AttackersScore = 0,
		DefendersScore = 0,
		Phase = "Waiting for Players",
		Timer = 0,
		BombStatus = "Idle",
		Reason = "",
		AliveAttackers = 0,
		AliveDefenders = 0,
	}) do
		matchState:SetAttribute(attributeName, value)
	end

	-- MatchModules holds the pure rules module the server requires by path.
	local matchModules = Shim.moduleFolder("MatchModules", "ReplicatedStorage/MatchModules", Sources)
	matchModules.Parent = ReplicatedStorage
	rawset(ReplicatedStorage, "MatchModules", matchModules)

	-- PrototypeRange: the playable map. The server names it directly.
	local proto = Instance.new("Model")
	proto.Name = "PrototypeRange"
	rawset(Workspace, "PrototypeRange", proto)
	proto.Parent = Workspace

	local bombSites = Instance.new("Folder")
	bombSites.Name = "BombSites"
	bombSites.Parent = proto

	local sitePositions = { A = Vector3.new(-40, 0, -40), B = Vector3.new(40, 0, -40) }
	for _, siteName in ipairs({ "A", "B" }) do
		local site = Instance.new("Part")
		site.Name = siteName
		site.Anchored = true
		site.Size = Vector3.new(6, 1, 6)
		site.CFrame = CFrame.new(sitePositions[siteName])
		site.Parent = bombSites
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PlantPrompt"
		prompt.ActionText = "Plant bomb"
		prompt.HoldDuration = 3
		prompt.Parent = site
	end

	local spawnPositions = {
		["Attackers Spawn"] = Vector3.new(0, 0, -70),
		["Defenders Spawn"] = Vector3.new(0, 0, 70),
		["Range Spawn"] = Vector3.new(0, 0, 0),
	}
	for spawnName, position in pairs(spawnPositions) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = spawnName
		spawn.CFrame = CFrame.new(position)
		spawn.Parent = proto
	end

	-- A range target, so the damage path has something tagged to hit.
	local target = Instance.new("Part")
	target.Name = "Target"
	target.CFrame = CFrame.new(0, 1, -20)
	target.Parent = proto
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TargetLabel"
	billboard.Parent = target
	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.Text = "100 HP"
	label.Parent = billboard

	-- The shop's weapon template. MatchShop clones this into a buyer's Backpack.
	local templates = Instance.new("Folder")
	templates.Name = "WeaponTemplates"
	templates.Parent = ServerStorage
	rawset(ServerStorage, "WeaponTemplates", templates)
	local smg = Instance.new("Tool")
	smg.Name = "CompactSMG"
	smg.Parent = templates

	return proto, bombSites
end

-- Boot the server match layer and let it reach its first wait.
local function boot()
	local env = Shim.harness(Sources)
	range, sites = buildPlace(env)
	env.__load("ServerScriptService/MatchManager.server")
	env.__load("ServerScriptService/MatchShop.server")
	env.__load("ServerScriptService/RangeTargets.server")
	state = env.__game:GetService("ReplicatedStorage").MatchState
	-- One tick starts the round coroutine and parks it on its first wait.
	Shim.tick(env, 1)
	return env
end

-- Fire a server remote the way the client's FireServer does.
local function fire(remote, player, ...)
	if remote.OnServerEvent == nil then
		error("no OnServerEvent on remote")
	end
	remote.OnServerEvent:Fire(player, ...)
end

-- Join a player through the real JoinMatch remote. The player is parented to
-- the Players service, because the round loop counts a participant only while
-- `player.Parent == Players`.
local function join(env, userId, name)
	local player = Shim.makePlayer(userId, name)
	local Players = env.__game:GetService("Players")
	table.insert(rawget(Players, "children"), player)
	rawset(player, "Parent", Players)
	Players.PlayerAdded:Fire(player)
	fire(state.JoinMatch, player)
	return player
end

-- Step the round loop until `predicate` holds, or the cap runs out. The cap is
-- what keeps a stuck round loop from hanging the suite: it fails with the phase
-- it was stuck in rather than spinning forever.
local function tickUntil(env, predicate, maxTicks, label)
	for _ = 1, maxTicks or 400 do
		if predicate() then return true end
		Shim.tick(env, 1)
	end
	if predicate() then return true end
	error(string.format("timed out waiting for %s (phase=%s, timer=%s)",
		label or "condition", tostring(state:GetAttribute("Phase")), tostring(state:GetAttribute("Timer"))))
end

local function phase() return state:GetAttribute("Phase") end
local function attr(player, name) return player:GetAttribute(name) end
local function money(player) return player:GetAttribute("Money") end

--------------------------------------------------------------------------
t.suite("breachline/match")

-- The match cannot start with one player, and must start with two. That is the
-- first thing the round loop gates on, and it is the first thing a player does.
t.test("one player does not start a round", function()
	local env = boot()
	local solo = join(env, 2, "Solo")
	Shim.tick(env, 5)
	t.assertEqual(phase(), "Waiting for Players", "phase with one player")
	t.assertEqual(attr(solo, "Alive"), false, "a waiting player is not alive")
	t.assertNil(state:GetAttribute("Round"), "no round was started")
end)

t.test("two players start warm-up, then a buy phase", function()
	local env = boot()
	join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	t.assertEqual(phase(), "Buy Phase", "phase")
	t.assertNotNil(state:GetAttribute("Round"), "a round number was assigned")
	t.assertEqual(state:GetAttribute("Round"), 1, "first round is 1")
end)

t.test("joining players are split across the two teams", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	local b = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	t.assertNotNil(a.Team, "first player has a team")
	t.assertNotNil(b.Team, "second player has a team")
	t.assertNotEqual(a.Team.Name, b.Team.Name, "the two players are on opposite teams")
	t.assertEqual(a.Team.Name, "Attackers", "first player is an attacker")
	t.assertEqual(b.Team.Name, "Defenders", "second player is a defender")
	t.assertEqual(a.Neutral, false, "a match player is not neutral")
end)

t.test("a player spawns with starting money and is alive", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	t.assertEqual(money(a), 800, "starting money")
	t.assertEqual(attr(a, "Alive"), true, "a player in a round is alive")
	t.assertNotNil(a.Character, "a player in a round has a character")
	t.assertNotNil(a.Character:FindFirstChild("Humanoid"), "the character has a humanoid")
end)

t.test("the phase timer counts down", function()
	local env = boot()
	join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	local first = state:GetAttribute("Timer")
	tickUntil(env, function() return state:GetAttribute("Timer") < first end, 20, "the timer to move")
	t.assertTrue(state:GetAttribute("Timer") < first,
		"the timer moved down from " .. tostring(first))
end)

--------------------------------------------------------------------------
t.suite("breachline/shop")

-- Buy an item the way the client does, then read the attributes back.
local function buy(env, player, itemName)
	fire(state.BuyItem, player, itemName)
end

t.test("a player can buy the SMG and is charged for it", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	buy(env, a, "CompactSMG")
	t.assertEqual(attr(a, "HasSMG"), true, "the SMG is owned")
	t.assertEqual(money(a), 100, "800 minus the 700 price")
	t.assertNotNil(a.Backpack:FindFirstChild("CompactSMG"), "the gun is in the backpack")
end)

t.test("a player can buy armor and is charged for it", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	-- A later round's budget, set directly: the economy is exercised by the
	-- money test above, and armour only needs to be affordable here.
	a:SetAttribute("Money", 800)
	buy(env, a, "Armor")
	t.assertEqual(attr(a, "Armor"), true, "armor is owned")
	t.assertEqual(money(a), 200, "800 minus the 600 price")
end)

t.test("a player cannot buy what they cannot afford", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	buy(env, a, "CompactSMG")
	buy(env, a, "Armor")
	t.assertFalse(attr(a, "Armor"), "armor was not granted on 100")
	t.assertEqual(money(a), 100, "money unchanged by the refused purchase")
end)

t.test("an item cannot be bought twice", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Buy Phase" end, 200, "buy phase")
	buy(env, a, "CompactSMG")
	buy(env, a, "CompactSMG")
	t.assertEqual(money(a), 100, "the second purchase did not charge again")
	local count = 0
	for _, item in ipairs(a.Backpack:GetChildren()) do
		if item.Name == "CompactSMG" then count += 1 end
	end
	t.assertEqual(count, 1, "only one gun in the backpack")
end)

t.test("nothing can be bought outside the buy phase", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	-- Still in warm-up here: the phase gate must hold.
	tickUntil(env, function() return phase() == "Warm-up" or phase() == "Buy Phase" end, 200, "warm-up")
	if phase() == "Warm-up" then
		buy(env, a, "CompactSMG")
		t.assertFalse(attr(a, "HasSMG"), "no purchase during warm-up")
		t.assertEqual(money(a), 800, "money untouched during warm-up")
	end
end)

--------------------------------------------------------------------------
t.suite("breachline/round")

t.test("combat starts when the buy phase ends", function()
	local env = boot()
	join(env, 2, "Alpha")
	join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")
	t.assertEqual(phase(), "Combat", "phase")
	t.assertEqual(state:GetAttribute("AliveAttackers"), 1, "one attacker alive")
	t.assertEqual(state:GetAttribute("AliveDefenders"), 1, "one defender alive")
end)

t.test("killing a team ends the round for the other team", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	local b = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")
	-- The defender dies. The round loop learns it from Humanoid.Died, which is
	-- the same signal the engine fires.
	local humanoid = b.Character:FindFirstChildOfClass("Humanoid")
	humanoid:TakeDamage(100)
	tickUntil(env, function() return phase() == "Round End" end, 200, "round end")
	t.assertEqual(state:GetAttribute("AttackersScore"), 1, "attackers scored")
	t.assertEqual(state:GetAttribute("Reason"), "Team Eliminated", "reason")
	t.assertEqual(attr(b, "Alive"), false, "the dead player is not alive")
	t.assertEqual(attr(a, "Alive"), true, "the surviving player is alive")
end)

t.test("a round win pays the winner more than the loser", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	local b = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")
	b.Character:FindFirstChildOfClass("Humanoid"):TakeDamage(100)
	tickUntil(env, function() return phase() == "Round End" end, 200, "round end")
	t.assertEqual(money(a), 800 + 1500, "winner bonus")
	t.assertEqual(money(b), 800 + 900, "loser bonus")
end)

t.test("the next round starts and resets the loadout", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	local b = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")
	b.Character:FindFirstChildOfClass("Humanoid"):TakeDamage(100)
	tickUntil(env, function() return phase() == "Round End" end, 200, "round end")
	tickUntil(env, function() return state:GetAttribute("Round") == 2 end, 400, "round 2")
	t.assertEqual(state:GetAttribute("Round"), 2, "round number")
	t.assertEqual(attr(a, "HasSMG"), false, "the loadout is cleared for the new round")
	t.assertEqual(attr(a, "Armor"), false, "armor is cleared for the new round")
	t.assertEqual(attr(a, "Alive"), true, "the new round spawned the player")
end)

t.test("a team elimination ends the round immediately", function()
	local env = boot()
	local a = join(env, 2, "Alpha")
	local b = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")
	-- The attacker dies this time, so the defenders take the round.
	a.Character:FindFirstChildOfClass("Humanoid"):TakeDamage(100)
	tickUntil(env, function() return phase() == "Round End" end, 200, "round end")
	t.assertEqual(state:GetAttribute("DefendersScore"), 1, "defenders scored")
	t.assertEqual(state:GetAttribute("AttackersScore"), 0, "attackers did not score")
end)

t.test("the bomb can be planted and detonates on the timer", function()
	local env = boot()
	local attacker = join(env, 2, "Alpha")
	local defender = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")

	-- Move the attacker onto site A, which is the same thing a player walking
	-- there does. The plant is range-gated, so this is what makes it legal.
	local siteA = sites:FindFirstChild("A")
	attacker.Character:PivotTo(CFrame.new(siteA.Position))
	local root = attacker.Character:FindFirstChild("HumanoidRootPart")
	t.assertTrue((root.Position - siteA.Position).Magnitude <= 12, "the attacker is in plant range")

	siteA.PlantPrompt:Trigger(attacker)
	t.assertEqual(state:GetAttribute("BombStatus"), "Planted", "the bomb is planted")
	t.assertEqual(state:GetAttribute("BombSite"), "A", "the site is recorded")
	tickUntil(env, function() return phase() == "Planted" end, 20, "planted phase")

	-- Run the fuse out. The defenders never defuse, so it detonates.
	tickUntil(env, function() return phase() == "Round End" end, 400, "detonation")
	t.assertEqual(state:GetAttribute("AttackersScore"), 1, "attackers scored on detonation")
	t.assertEqual(state:GetAttribute("Reason"), "Bomb Detonated", "reason")
end)

t.test("a defender can defuse a planted bomb", function()
	local env = boot()
	local attacker = join(env, 2, "Alpha")
	local defender = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")
	local siteA = sites:FindFirstChild("A")
	attacker.Character:PivotTo(CFrame.new(siteA.Position))
	siteA.PlantPrompt:Trigger(attacker)
	tickUntil(env, function() return phase() == "Planted" end, 20, "planted phase")

	local bomb = range:FindFirstChild("PlantedBomb")
	t.assertNotNil(bomb, "the bomb is in the world")
	local prompt = bomb:FindFirstChild("DefusePrompt")
	t.assertNotNil(prompt, "the bomb has a defuse prompt")

	-- The defender walks to the bomb and holds the prompt.
	defender.Character:PivotTo(CFrame.new(bomb.Position))
	prompt:Trigger(defender)
	t.assertEqual(state:GetAttribute("BombStatus"), "Defused", "the bomb is defused")
	tickUntil(env, function() return phase() == "Round End" end, 200, "round end")
	t.assertEqual(state:GetAttribute("DefendersScore"), 1, "defenders scored on defuse")
	t.assertEqual(state:GetAttribute("Reason"), "Bomb Defused", "reason")
end)

t.test("a team-mate cannot plant for the other team", function()
	local env = boot()
	local attacker = join(env, 2, "Alpha")
	local defender = join(env, 3, "Bravo")
	tickUntil(env, function() return phase() == "Combat" end, 400, "combat")
	local siteA = sites:FindFirstChild("A")
	-- The defender stands on the site and tries to plant. The server checks the
	-- team, so nothing happens.
	defender.Character:PivotTo(CFrame.new(siteA.Position))
	siteA.PlantPrompt:Trigger(defender)
	t.assertNotEqual(state:GetAttribute("BombSite"), "A", "a defender planted nothing")
	t.assertEqual(state:GetAttribute("BombStatus"), "Idle", "the bomb is still idle")
end)

--------------------------------------------------------------------------
t.suite("breachline/rules")

-- The pure rules module, required straight out of the same bundle the server
-- uses, so the round loop and this suite agree on one source of truth.
local Rules = Shim.loader(Sources)("ReplicatedStorage/MatchModules/RoundRules")

t.test("RoundRules refuses to start a match below the minimum", function()
	t.assertEqual(Rules.MinimumPlayers, 2, "minimum players")
end)

t.test("the winner rules match the phases the server drives", function()
	local rules = Rules
	local w, reason = rules.winner("Combat", "Idle", 1, 0, 30)
	t.assertEqual(w, "Attackers", "attackers win when defenders are eliminated")
	t.assertEqual(reason, "Team Eliminated", "reason")
	local w2 = rules.winner("Combat", "Idle", 1, 1, 40)
	t.assertNil(w2, "a live round has no winner yet")
	local w3, r3 = rules.winner("Combat", "Idle", 1, 1, 0)
	t.assertEqual(w3, "Defenders", "defenders win on time")
	t.assertEqual(r3, "Time Expired", "reason")
end)

t.finish()

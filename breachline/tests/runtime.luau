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

	-- PrototypeRange: the first map. The server picks it out of Workspace by the
	-- attributes MapRegistry reads, so the fixture carries the same three the
	-- build stamps onto the real place.
	local proto = Instance.new("Model")
	proto.Name = "PrototypeRange"
	proto:SetAttribute("MapId", "dust-district")
	proto:SetAttribute("MapName", "Dust District")
	proto:SetAttribute("MapOrder", 1)
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

	-- Foundry: the second map, far enough away that a spawn on one is never inside
	-- the other. The rotation has nothing to rotate to without it, so a test that
	-- asserts the map changes needs a real second map.
	local foundry = Instance.new("Model")
	foundry.Name = "Foundry"
	foundry:SetAttribute("MapId", "foundry")
	foundry:SetAttribute("MapName", "Foundry")
	foundry:SetAttribute("MapOrder", 2)
	foundry.Parent = Workspace

	local foundrySites = Instance.new("Folder")
	foundrySites.Name = "BombSites"
	foundrySites.Parent = foundry
	for _, siteName in ipairs({ "A", "B" }) do
		local site = Instance.new("Part")
		site.Name = siteName
		site.Anchored = true
		site.Size = Vector3.new(6, 1, 6)
		site.CFrame = CFrame.new(Vector3.new(siteName == "A" and 160 or 240, 0, -40))
		site.Parent = foundrySites
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PlantPrompt"
		prompt.ActionText = "Plant bomb"
		prompt.HoldDuration = 3
		prompt.Parent = site
	end
	for _, spawnName in ipairs({ "Attackers Spawn", "Defenders Spawn" }) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = spawnName
		spawn.CFrame = CFrame.new(Vector3.new(spawnName == "Attackers Spawn" and 188 or 212, 0, 70))
		spawn.Parent = foundry
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

--------------------------------------------------------------------------
t.suite("breachline/weapon")

-- The shot-to-damage path, driven through the real Firearm2Server script.
--
-- Why this exists. A round can run to completion with a gun that does nothing.
-- The shop hands the player a Tool, but the code that turns a trigger pull into
-- damage is a separate script living inside that Tool, and nothing here had ever
-- run it -- the match suite above kills players by firing the damage path's
-- remote directly, which never enters the weapon. This suite boots the actual
-- script against a Tool built like the shipped one and fires through its own
-- Fire remote, so a broken shot is a failure rather than a green suite.
--
-- What this does not cover: the client half (camera, input, HUD, aim assist) and
-- the replicated tracer. Those need a real client and are NOT VERIFIED.

local Constants = Shim.loader(Sources)("ReplicatedStorage/FourD/Architects/Firearm2/Common/Constants")
local ARMOR_MULTIPLIER = 0.65

-- A Tool shaped like the shipped CompactSMG, with the real weapon script booted
-- inside it. The script gates on `script.Parent:IsA("Tool")` and reads its
-- tunables off the Tool, so both have to be real. Params come from the same
-- Constants module the weapon reads its defaults from, rather than being
-- hand-copied, so the test and the code cannot drift apart.
local function equipWeapon(env, shooter)
	Shim.mount(Sources, env, "ReplicatedStorage", "ReplicatedStorage/FourD")

	local tool = Instance.new("Tool")
	tool.Name = "CompactSMG"
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = tool
	local fire, ammoChanged
	for _, remoteName in ipairs({ "AmmoChanged", "Fire", "ReloadAck", "ReloadCancel", "Reload", "ReloadStarted", "ShotReplicate" }) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotes
		if remoteName == "Fire" then fire = remote end
		if remoteName == "AmmoChanged" then ammoChanged = remote end
	end

	-- The weapon reports ammo to the owner over this remote, so listening is the
	-- only way to see that a shot was really consumed rather than dropped.
	local ammo = { reported = nil }
	ammoChanged.OnClientEvent:Connect(function(value)
		ammo.reported = value
	end)

	-- ShotOrigin is where the server traces from; without it the handler warns
	-- and drops the shot before any damage is applied.
	local origin = Instance.new("Attachment")
	origin.Name = "ShotOrigin"
	origin.WorldPosition = Vector3.new(0, 5, 0)
	origin.Parent = tool

	for key, value in pairs(Constants.DEFAULT_PARAMS) do
		if type(value) ~= "table" then
			tool:SetAttribute(key, value)
		end
	end

	tool.Parent = shooter.Character
	Shim.runScript(Sources, env, "ServerStorage/WeaponTemplates/CompactSMG/Firearm2Server.server", tool)
	return tool, fire, ammo
end

-- Two players on opposite teams, alive, with heads at known positions so a shot
-- can be aimed. The match loop is not started: this suite tests the weapon, and
-- the match layer has its own suite above.
local function weaponEnv()
	local env = Shim.harness(Sources)
	local ReplicatedStorage = env.__game:GetService("ReplicatedStorage")
	local Workspace = env.__game:GetService("Workspace")
	local Players = env.__game:GetService("Players")
	local Teams = env.__game:GetService("Teams")

	local matchState = Instance.new("Folder")
	matchState.Name = "MatchState"
	matchState:SetAttribute("Phase", "Combat")
	matchState.Parent = ReplicatedStorage
	rawset(ReplicatedStorage, "MatchState", matchState)

	local function place(player, position)
		player.LoadCharacter()
		player.Character.Parent = Workspace
		for _, partName in ipairs({ "HumanoidRootPart", "Head" }) do
			local part = player.Character:FindFirstChild(partName)
			part.CFrame = CFrame.new(position)
			part.Position = position
		end
		return player.Character
	end

	local shooter = Shim.makePlayer(2, "Shooter")
	local victim = Shim.makePlayer(3, "Victim")
	rawset(Players, "children", { shooter, victim })
	shooter.Team = Teams.Attackers
	victim.Team = Teams.Defenders
	shooter:SetAttribute("Alive", true)
	victim:SetAttribute("Alive", true)
	place(shooter, Vector3.new(0, 5, 0))
	place(victim, Vector3.new(0, 5, -20))

	local tool, fire, ammo = equipWeapon(env, shooter)
	return env, shooter, victim, tool, fire, ammo
end

local function fireShot(shooter, fire, victim)
	local camera = CFrame.new(shooter.Character:FindFirstChild("Head").Position)
	fire.OnServerEvent:Fire(shooter, camera, victim.Character:FindFirstChild("Head").Position)
end

local function victimHealth(victim)
	return victim.Character:FindFirstChildOfClass("Humanoid").Health
end

t.test("a shot from the real weapon damages an enemy and spends a round", function()
	local env, shooter, victim, tool, fire, ammo = weaponEnv()
	local magSize = tool:GetAttribute("AmmoMagSize")
	Shim.advanceClock(1)
	fireShot(shooter, fire, victim)
	t.assertNear(victimHealth(victim), 100 - Constants.DEFAULT_PARAMS.DamagePerRound, 0.01,
		"an enemy hit takes the weapon's configured damage")
	t.assertEqual(ammo.reported, magSize - 1, "the shot spent one round from the magazine")
end)

t.test("armor reduces the damage a shot deals", function()
	local env, shooter, victim, tool, fire = weaponEnv()
	victim:SetAttribute("Armor", true)
	Shim.advanceClock(1)
	fireShot(shooter, fire, victim)
	local expected = 100 - Constants.DEFAULT_PARAMS.DamagePerRound * ARMOR_MULTIPLIER
	t.assertNear(victimHealth(victim), expected, 0.01, "an armored enemy takes 65% of the damage")
end)

t.test("a shot at a team-mate does no damage", function()
	local env, shooter, victim, tool, fire = weaponEnv()
	victim.Team = shooter.Team
	Shim.advanceClock(1)
	fireShot(shooter, fire, victim)
	t.assertEqual(victimHealth(victim), 100, "a team-mate is not hurt by their own team")
end)

t.test("a shot outside the combat phases does no damage", function()
	local env, shooter, victim, tool, fire = weaponEnv()
	env.__game:GetService("ReplicatedStorage").MatchState:SetAttribute("Phase", "Buy Phase")
	Shim.advanceClock(1)
	fireShot(shooter, fire, victim)
	t.assertEqual(victimHealth(victim), 100, "the server rejects damage outside combat")
end)

t.test("a second shot inside the fire interval is ignored", function()
	local env, shooter, victim, tool, fire, ammo = weaponEnv()
	local magSize = tool:GetAttribute("AmmoMagSize")
	Shim.advanceClock(1)
	fireShot(shooter, fire, victim)
	local afterFirst = victimHealth(victim)
	-- No clock advance: the same instant, so the rate limiter must drop it.
	fireShot(shooter, fire, victim)
	t.assertEqual(victimHealth(victim), afterFirst, "firing faster than the weapon allows does nothing")
	t.assertEqual(ammo.reported, magSize - 1, "the dropped shot spent no round")
	Shim.advanceClock(1)
	fireShot(shooter, fire, victim)
	t.assertLess(victimHealth(victim), afterFirst, "once the interval passes the next shot lands")
	t.assertEqual(ammo.reported, magSize - 2, "the second landed shot spent a round")
end)

--------------------------------------------------------------------------
t.suite("breachline/controls")

-- Which touch controls a weapon may show.
--
-- Why this exists. The cluster draws a fixed set of buttons for every weapon, so
-- a weapon with iron sights was given a SCOPE button that did nothing when
-- tapped. The decision is a pure function of the weapon's params, and it is the
-- thing that decides whether a button is on screen at all, so it is tested here
-- rather than left to a Studio session.
local WeaponControls = Shim.loader(Sources)("ReplicatedStorage/FourD/Architects/Firearm2/Common/WeaponControls")

t.test("a weapon with iron sights hides the scope button", function()
        t.assertFalse(WeaponControls.hasOptic({ AimMode = "default" }), "default aim is not an optic")
        t.assertEqual(WeaponControls.available({ AimMode = "default" }).Scope, false, "SCOPE is hidden")
end)

t.test("a weapon with an optic shows the scope button", function()
        t.assertTrue(WeaponControls.hasOptic({ AimMode = "scope" }), "scope aim is an optic")
        t.assertEqual(WeaponControls.available({ AimMode = "scope" }).Scope, true, "SCOPE is shown")
end)

t.test("a weapon with no params hides the scope button rather than erroring", function()
        t.assertFalse(WeaponControls.hasOptic(nil), "no params is not an optic")
        t.assertFalse(WeaponControls.hasOptic("scope"), "a non-table is not an optic")
        t.assertEqual(WeaponControls.available(nil).Scope, false, "SCOPE is hidden")
end)

t.test("only the scope button is ever turned off", function()
        -- The rest of the cluster is the same gun to gun; a second entry here
        -- would silently hide a verb the player needs.
        local available = WeaponControls.available({ AimMode = "default" })
        local names = {}
        for name in pairs(available) do
                table.insert(names, name)
        end
        t.assertEqual(#names, 1, "exactly one control is decided per weapon")
        t.assertEqual(names[1], "Scope", "and it is the scope button")
end)

t.suite("breachline/maps")

-- The rotation and the contract it reads.
--
-- Why this exists. The place shipped one map and the server named it directly,
-- so "which map are we playing" was a constant. The rotation turns it into
-- state, and state that is only exercised by playing a full match to four round
-- wins is state nobody checks. These tests drive the registry against the same
-- map contract the build stamps onto the real place, and then play a real match
-- out to its end to prove the server actually moves to the second map.
local MapRegistry = Shim.loader(Sources)("ReplicatedStorage/MatchModules/MapRegistry")

-- The registry reads a container's children, so a plain table of Models is not
-- enough -- it has to be a real instance the shim will enumerate.
local function mapContainer(env, models)
        local folder = Instance.new("Folder")
        folder.Name = "Maps"
        for _, model in ipairs(models) do model.Parent = folder end
        return folder
end

local function mapModel(name, id, order)
        local model = Instance.new("Model")
        model.Name = name
        model:SetAttribute("MapId", id)
        model:SetAttribute("MapName", name)
        model:SetAttribute("MapOrder", order)

        local sites = Instance.new("Folder")
        sites.Name = "BombSites"
        sites.Parent = model
        for _, siteName in ipairs({ "A", "B" }) do
                local site = Instance.new("Part")
                site.Name = siteName
                site.Parent = sites
                local prompt = Instance.new("ProximityPrompt")
                prompt.Name = "PlantPrompt"
                prompt.Parent = site
        end
        for _, spawnName in ipairs({ "Attackers Spawn", "Defenders Spawn" }) do
                local spawn = Instance.new("SpawnLocation")
                spawn.Name = spawnName
                spawn.Parent = model
        end
        return model
end

t.test("a complete map satisfies the contract", function()
        local env = Shim.harness(Sources)
        local model = mapModel("Alpha", "alpha", 1)
        t.assertEqual(#MapRegistry.problems(model), 0, "a complete map has no problems")
        t.assertTrue(MapRegistry.isMap(model), "and is recognised as a map")
end)

t.test("an incomplete map names what is missing", function()
        local env = Shim.harness(Sources)
        local model = mapModel("Alpha", "alpha", 1)
        model:FindFirstChild("BombSites"):FindFirstChild("B"):Destroy()
        local problems = MapRegistry.problems(model)
        t.assertEqual(#problems, 1, "one problem is reported")
        t.assertTrue(problems[1]:find("two bomb sites") ~= nil, "and it names the missing site: " .. tostring(problems[1]))
end)

t.test("a map with no id is rejected", function()
        local env = Shim.harness(Sources)
        local model = mapModel("Alpha", "alpha", 1)
        model:SetAttribute("MapId", nil)
        local problems = MapRegistry.problems(model)
        t.assertTrue(#problems >= 1, "a map with no id is a problem")
        t.assertFalse(MapRegistry.isMap(model), "and is not a map")
end)

t.test("collect skips a half-built map and sorts by order", function()
        local env = Shim.harness(Sources)
        local second = mapModel("Second", "second", 2)
        local first = mapModel("First", "first", 1)
        local broken = mapModel("Broken", "broken", 3)
        broken:FindFirstChild("BombSites"):Destroy()

        local maps = MapRegistry.collect(mapContainer(env, { second, broken, first }))
        t.assertEqual(#maps, 2, "the half-built map is skipped, not returned")
        t.assertEqual(maps[1].id, "first", "order 1 comes first")
        t.assertEqual(maps[2].id, "second", "order 2 comes second")
end)

t.test("the rotation advances and wraps", function()
        local env = Shim.harness(Sources)
        local maps = MapRegistry.collect(mapContainer(env, {
                mapModel("First", "first", 1),
                mapModel("Second", "second", 2),
        }))
        t.assertEqual(MapRegistry.next(maps, nil).id, "first", "an unknown current map starts at the first")
        t.assertEqual(MapRegistry.next(maps, "first").id, "second", "the rotation advances")
        t.assertEqual(MapRegistry.next(maps, "second").id, "first", "and wraps at the end")
        t.assertEqual(MapRegistry.next(maps, "gone").id, "first", "a removed map falls back to the first")
end)

t.test("deactivating a map switches off its spawns and plant prompts", function()
        local env = Shim.harness(Sources)
        local model = mapModel("Alpha", "alpha", 1)
        MapRegistry.deactivate(model)
        t.assertEqual(model:GetAttribute("MapActive"), false, "the map is marked inactive")
        for _, descendant in ipairs(model:GetDescendants()) do
                if descendant.ClassName == "SpawnLocation" or descendant.ClassName == "ProximityPrompt" then
                        t.assertEqual(descendant.Enabled, false, descendant.Name .. " is disabled")
                end
        end
end)

t.test("the range targets are bound on the map that carries them", function()
        local env = boot()
        -- The targets used to be found by naming one map. Now every map is
        -- scanned, so a target on the second map is bound too -- and a target
        -- that was never tagged takes no damage from the firearm rig.
        local foundry = G.workspace:FindFirstChild("Foundry")
        local target = Instance.new("Part")
        target.Name = "Target"
        target.CFrame = CFrame.new(0, 1, -60)
        target.Parent = foundry
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "TargetLabel"
        billboard.Parent = target
        local label = Instance.new("TextLabel")
        label.Name = "TextLabel"
        label.Text = "100 HP"
        label.Parent = billboard

        -- Re-run the script against the map that now carries a target, the way
        -- the server would after the map is in the place.
        env.__load("ServerScriptService/RangeTargets.server")

        local damage = target:FindFirstChild("TakeDamage")
        t.assertNotNil(damage, "the second map's target got a damage event")
        t.assertEqual(target:GetAttribute("TargetHealth"), nil, "health starts unset until the first hit")
        damage.Event:Fire(30)
        t.assertEqual(target:GetAttribute("TargetHealth"), 70, "the target took the damage")
        t.assertEqual(label.Text, "70 HP", "and its label follows")
end)

t.test("a match plays on one map and the next match rotates", function()
        local env = boot()
        local a = join(env, 2, "Alpha")
        local b = join(env, 3, "Bravo")

        -- The first match starts on the first map in order.
        t.assertEqual(state:GetAttribute("MapId"), "dust-district", "the first match is on the first map")

        -- Only the active map's spawns are enabled, so a round cannot start a
        -- player on the map the match has left.
        local dust = range
        local foundry = G.workspace:FindFirstChild("Foundry")
        t.assertNotNil(foundry, "the second map is in the place")
        t.assertEqual(dust:FindFirstChild("Attackers Spawn").Enabled, true, "the active map's spawns are on")
        t.assertEqual(foundry:FindFirstChild("Attackers Spawn").Enabled, false, "the idle map's spawns are off")

        -- Win a match: four rounds to the defenders, which is ScoreToWin.
        local rules = Shim.loader(Sources)("ReplicatedStorage/MatchModules/RoundRules")
        for _ = 1, rules.ScoreToWin do
                tickUntil(env, function() return phase() == "Combat" end, 600, "combat")
                a.Character:FindFirstChildOfClass("Humanoid"):TakeDamage(100)
                tickUntil(env, function() return phase() == "Round End" end, 300, "round end")
                tickUntil(env, function() return phase() ~= "Round End" end, 300, "next round")
        end

        -- The match is over, and the next one is on the other map.
        tickUntil(env, function() return state:GetAttribute("MapId") == "foundry" end, 400, "rotation to the second map")
        t.assertEqual(state:GetAttribute("MapId"), "foundry", "the next match rotated to the second map")
        t.assertEqual(state:GetAttribute("MapName"), "Foundry", "and its name follows")
        t.assertEqual(foundry:FindFirstChild("Attackers Spawn").Enabled, true, "the new map's spawns are on")
        t.assertEqual(dust:FindFirstChild("Attackers Spawn").Enabled, false, "the old map's spawns are off")
end)

t.suite("breachline/client")

-- The client half, loaded and driven.
--
-- Why this suite exists. Everything above runs the server and the world, and
-- the file's own header said the client was NOT VERIFIED because it "needs a
-- real client". That was true of the shim, not of the game: the shim was missing
-- UIListLayout and five other UI classes the HUD instantiates, so the HUD script
-- aborted on its first layout object and no test could load it at all. The
-- client half -- the menu a player presses PLAY on, the score bar, the buy card
-- -- had therefore never been executed by any test, on the build that shipped.
--
-- These tests load the real MatchHud.client against the real containers and
-- press the real button. They assert the two things a player needs and nothing
-- more: the menu appears, and pressing PLAY reaches the server.

local function clientEnv()
        local env = Shim.harness(Sources)
        local ReplicatedStorage = env.__game:GetService("ReplicatedStorage")

        local matchState = Instance.new("Folder")
        matchState.Name = "MatchState"
        for _, remoteName in ipairs({ "JoinMatch", "BuyItem" }) do
                local remote = Instance.new("RemoteEvent")
                remote.Name = remoteName
                remote.Parent = matchState
        end
        matchState.Parent = ReplicatedStorage
        rawset(ReplicatedStorage, "MatchState", matchState)
        matchState:SetAttribute("MapName", "Dust District")
        matchState:SetAttribute("Phase", "Waiting for Players")

        -- The HUD requires MobileControls out of this tree at load, so a missing
        -- mount is a client that never starts -- exactly the failure this suite
        -- is here to catch.
        Shim.mount(Sources, env, "ReplicatedStorage", "ReplicatedStorage/FourD")

        local ok, err = pcall(function()
                env.__load("StarterPlayer/StarterPlayerScripts/MatchHud.client")
        end)
        return env, ok, err, matchState
end

local function findPlay(gui)
        local menu = gui:FindFirstChild("MainMenu")
        local card = menu and menu:FindFirstChild("Frame")
        return card and card:FindFirstChild("Play")
end

t.test("the client HUD loads and builds its menu", function()
        local env, ok, err = clientEnv()
        t.assertTrue(ok, "MatchHud.client failed to load: " .. tostring(err))

        local gui = env.__player.PlayerGui:FindFirstChild("MatchHud")
        t.assertNotNil(gui, "the client built no MatchHud ScreenGui")

        local bar = gui:FindFirstChild("TopColumn")
        t.assertNotNil(bar, "the client built no top column")
        t.assertNotNil(bar:FindFirstChild("ScoreAndTime"), "no score bar")
        t.assertNotNil(bar:FindFirstChild("Objective"), "no objective line")

        local play = findPlay(gui)
        t.assertNotNil(play, "the menu has no PLAY button, so a player cannot join")
        t.assertEqual(play.ClassName, "TextButton", "PLAY is pressable")
end)

t.test("the menu heading follows the map the server selected", function()
        local env, ok = clientEnv()
        t.assertTrue(ok, "client failed to load")
        local gui = env.__player.PlayerGui:FindFirstChild("MatchHud")
        local menu = gui:FindFirstChild("MainMenu")
        local card = menu:FindFirstChild("Frame")
        local heading = card:FindFirstChild("Heading")
        t.assertEqual(heading.Text, "Dust District", "heading shows the map name")
end)

t.test("pressing PLAY reaches the server and the menu closes", function()
        local env, ok = clientEnv()
        t.assertTrue(ok, "client failed to load")

        local matchState = env.__game:GetService("ReplicatedStorage").MatchState
        local joined = 0
        matchState.JoinMatch.OnServerEvent:Connect(function() joined += 1 end)

        local player = env.__player
        local Players = env.__game:GetService("Players")
        table.insert(rawget(Players, "children"), player)
        rawset(player, "Parent", Players)

        local gui = player.PlayerGui:FindFirstChild("MatchHud")
        local play = findPlay(gui)
        play.Activated:Fire()

        t.assertEqual(joined, 1, "PLAY fired JoinMatch once")
        t.assertEqual(gui:FindFirstChild("MainMenu").Visible, false, "the menu closed on PLAY")
        t.assertEqual(player.CameraMode, G.Enum.CameraMode.LockFirstPerson, "the camera went first person")
end)

t.finish()

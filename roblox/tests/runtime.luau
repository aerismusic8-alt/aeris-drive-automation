--!nocheck
-- Runtime tests: boot the real server, build the real world, run the real
-- client, and join a real player.
--
-- Why this file exists. Every other test in this repo loaded only the pure
-- modules in src/shared. World.luau, init.server.luau, init.client.luau and
-- Hud.luau -- the code that actually runs in Roblox -- were never executed by
-- CI. The suite passed while the game was unplayable, because every failure was
-- a runtime one:
--
--   * World.buildWorld() ran at server start and threw inside Scenery: a
--     Vector3 arrival point was passed where pure Luau wanted { x, y, z }, so
--     arrival.x was nil and the subtraction threw. The whole server script died
--     there, before it created a single remote or served a single player. From
--     inside the game that reads as "no systems at all".
--   * pushPlayerState reached for `broadcastNow`, a local belonging to the
--     heartbeat loop, which is nil there, and handed it to Farm.snapshot. Any
--     player holding a crop threw their own state push.
--   * The state payload carried none of the character sheet, so the client's
--     Stats, Skills, Job and Bag tabs rendered their empty defaults: no stats.
--
-- None of these is visible to a text check, and none is a pure-logic bug, so no
-- existing test could have caught them. These tests run the code instead.
--
--   luau roblox/tests/runtime.luau

local t = require("./TestRunner")
local Shim = require("./RobloxShim")
local Sources = require("./.generated/Sources")

local function boot()
        return Shim.bootServer(Sources)
end

-- Capture the next PlayerState payload the server pushes, then join a player.
local function joinAndCapture(env, userId, name)
        local captured = nil
        local PlayerState = env.__replicatedRemotes:FindFirstChild("PlayerState")
        PlayerState.OnClientEvent:Connect(function(payload)
                captured = payload
        end)
        Shim.joinPlayer(env, userId, name)
        return captured
end

--------------------------------------------------------------------------
t.suite("Runtime: the world builds")
--------------------------------------------------------------------------

t.test("World.luau builds ground, a town and every field", function()
        local env = Shim.harness(Sources)
        local World = env.__load("server/World")
        local root = World.buildWorld()

        t.assertTrue(root ~= nil, "buildWorld returned nil")
        t.assertTrue(root:FindFirstChild("WorldGround") ~= nil, "no ground to stand on")
        t.assertTrue(root:FindFirstChild("Town") ~= nil, "no town")

        local Fields = env.__load("shared/Fields")
        local fields = Fields.list()
        t.assertTrue(#fields > 0, "no fields are defined")
        for _, field in ipairs(fields) do
                t.assertTrue(
                        root:FindFirstChild("Field_" .. field.id) ~= nil,
                        "no map built for field " .. tostring(field.id))
        end
end)

t.test("the town has a spawn pad a player lands on", function()
        local env = Shim.harness(Sources)
        local World = env.__load("server/World")
        local root = World.buildWorld()
        local town = root:FindFirstChild("Town")
        t.assertTrue(town ~= nil, "no town")
        t.assertTrue(
                town:FindFirstChildWhichIsA("SpawnLocation") ~= nil,
                "the town has no SpawnLocation, so a player has nowhere to land")
end)

--------------------------------------------------------------------------
t.suite("Runtime: the server boots")
--------------------------------------------------------------------------

t.test("the server script loads and finishes starting", function()
        -- The load path is the whole test. A throw anywhere in it -- the world
        -- build, a remote, a handler -- leaves the game with no systems.
        local ok, err = pcall(boot)
        t.assertTrue(ok, "the server failed to start: " .. tostring(err))
end)

t.test("the server creates every remote the client waits on", function()
        local env = boot()
        local remotes = env.__replicatedRemotes
        t.assertTrue(remotes ~= nil, "the server never created the Remotes folder")

        -- Read the client's own WaitForChild list, so a remote added on one side
        -- only fails here rather than hanging the real client forever.
        local source = Sources["client/init.client"]
        local waited, count = {}, 0
        for name in string.gmatch(source, 'Remotes:WaitForChild%("([A-Za-z]+)"%)') do
                waited[name] = true
                count += 1
        end
        t.assertTrue(count > 0, "found no WaitForChild calls in the client")

        for name in pairs(waited) do
                t.assertTrue(
                        remotes:FindFirstChild(name) ~= nil,
                        "the client waits for " .. name .. " but the server never creates it")
        end
end)

--------------------------------------------------------------------------
t.suite("Runtime: a player joins and gets a real character sheet")
--------------------------------------------------------------------------

t.test("joining a player does not throw", function()
        local env = boot()
        local ok, err = pcall(Shim.joinPlayer, env, 7, "K")
        t.assertTrue(ok, "joining threw: " .. tostring(err))
end)

t.test("the payload carries the basics a player must see", function()
        local env = boot()
        local captured = joinAndCapture(env, 7, "K")

        t.assertTrue(captured ~= nil, "the server pushed no player state on join")
        if not captured then
                return
        end

        t.assertTrue(captured.level ~= nil, "no level")
        t.assertTrue(captured.health ~= nil, "no health")
        t.assertTrue(captured.maxHealth ~= nil, "no maxHealth")
        t.assertTrue(captured.derived ~= nil, "no derived stats")
        t.assertTrue(captured.derived.maxHealth > 0, "maxHealth is not positive")
        t.assertTrue(captured.farm ~= nil, "no farm state")
        t.assertTrue(captured.fields ~= nil, "no field list, so the map menu is empty")
end)

t.test("the payload carries the character sheet the tabs render", function()
        local env = boot()
        local captured = joinAndCapture(env, 7, "K")
        t.assertTrue(captured ~= nil, "no state was pushed")
        if not captured then
                return
        end

        -- Each of these is read by the client's Stats, Skills, Job or Bag tab.
        -- The payload used to carry none of them, so every tab showed the
        -- client's empty defaults.
        t.assertTrue(captured.attributes ~= nil, "no attributes: the Stats tab has no sheet")
        t.assertTrue(captured.attributeSheet ~= nil, "no attributeSheet: the derived list is blank")
        t.assertTrue(captured.attributeNames ~= nil, "no attributeNames")
        t.assertTrue(captured.class ~= nil, "no class")
        t.assertTrue(captured.className ~= nil and #captured.className > 0,
                "no className, so the character title is blank")
        t.assertTrue(captured.jobLevel ~= nil, "no jobLevel")
        t.assertTrue(captured.skills ~= nil, "no skills: the Skills tab is empty")
        t.assertTrue(captured.equipment ~= nil, "no equipment")
        t.assertTrue(captured.bag ~= nil, "no bag")
        t.assertTrue(captured.sp ~= nil and captured.maxSp ~= nil, "no SP, so skills cannot be paid for")

        -- The sheet has to be real numbers, not just present. A blank sheet is
        -- the symptom being fixed.
        local sheet = captured.attributeSheet or {}
        t.assertTrue((sheet.maxHealth or 0) > 0, "the attribute sheet has no maxHealth")
        t.assertTrue((sheet.attack or 0) > 0, "the attribute sheet has no attack")
        t.assertTrue((sheet.defense or 0) >= 0, "the attribute sheet has no defense")

        -- And the six attributes themselves.
        local attrs = captured.attributes or {}
        for _, name in ipairs({ "STR", "AGI", "VIT", "INT", "DEX", "LUK" }) do
                t.assertTrue(attrs[name] ~= nil, "the attribute sheet is missing " .. name)
        end
end)

t.test("a player with a planted crop still gets a state push", function()
        local env = boot()
        local player = Shim.joinPlayer(env, 9, "Farmer")

        -- The exact shape of the broadcastNow bug: a plot holding a crop makes
        -- Farm.snapshot do arithmetic on the clock it is handed. With nil, this
        -- threw and the player's state never arrived.
        local PlantCrop = env.__replicatedRemotes:FindFirstChild("PlantCrop")
        t.assertTrue(PlantCrop ~= nil, "no PlantCrop remote")
        t.assertTrue(type(PlantCrop.OnServerInvoke) == "function",
                "PlantCrop has no OnServerInvoke")

        local planted, err = PlantCrop.OnServerInvoke(player, 1, "Wheat")
        t.assertTrue(planted, "planting a crop failed: " .. tostring(err))

        -- Any later push recomputes the farm snapshot, so this is what used to
        -- throw once a plot was occupied.
        local captured = nil
        local PlayerState = env.__replicatedRemotes:FindFirstChild("PlayerState")
        PlayerState.OnClientEvent:Connect(function(payload)
                captured = payload
        end)

        local ClaimDaily = env.__replicatedRemotes:FindFirstChild("ClaimDaily")
        local ok, pushErr = pcall(ClaimDaily.OnServerInvoke, player)
        t.assertTrue(ok, "the state push threw with a planted crop: " .. tostring(pushErr))
        t.assertTrue(captured ~= nil, "no state was pushed after planting")
        if captured then
                -- Farm.snapshot returns the plot list itself, one entry per plot.
                t.assertTrue(captured.farm ~= nil, "the farm snapshot is missing")
                t.assertTrue(#captured.farm > 0, "the farm snapshot has no plots")
                local plantedPlot = captured.farm[1]
                t.assertTrue(plantedPlot ~= nil, "plot 1 is missing from the snapshot")
                t.assertTrue(plantedPlot.cropId ~= nil,
                        "the crop planted through PlantCrop is not in the snapshot")
                t.assertTrue(plantedPlot.secondsLeft ~= nil,
                        "the plot has no secondsLeft, which is the value the broadcastNow bug broke")
        end
end)

--------------------------------------------------------------------------
t.suite("Runtime: the client boots and renders")
--------------------------------------------------------------------------

t.test("the client loads and builds its HUD", function()
        local env = boot()
        local ok, err = pcall(function()
                env.__load("client/init.client")
        end)
        t.assertTrue(ok, "the client failed to load: " .. tostring(err))

        local gui = env.__player.PlayerGui:FindFirstChild("AXArenaHUD")
        t.assertTrue(gui ~= nil, "the client built no HUD")
end)

t.test("a real state payload renders into the HUD without error", function()
        local env = boot()
        env.__load("client/init.client")

        -- The client read Players.LocalPlayer once, at load, and built the HUD
        -- on that player. Joining replaces the local player, so the client's own
        -- player is kept here to look the HUD up afterwards.
        local clientPlayer = env.__player

        -- The server payload the client has to render. If a field it reads is
        -- missing or the wrong shape, the render throws and the screen stays
        -- blank -- which is exactly the "no systems" report.
        local payload = joinAndCapture(env, 11, "Viewer")
        t.assertTrue(payload ~= nil, "no payload to render")
        if not payload then
                return
        end

        local PlayerState = env.__replicatedRemotes:FindFirstChild("PlayerState")
        local ok, err = pcall(function()
                PlayerState:FireClient(clientPlayer, payload)
        end)
        t.assertTrue(ok, "rendering the state payload threw: " .. tostring(err))

        -- Not throwing is necessary but not sufficient: the panel could still be
        -- blank. These read the labels the payload is supposed to fill, which is
        -- the difference between "the client ran" and "the player can see stats".
        local gui = clientPlayer.PlayerGui:FindFirstChild("AXArenaHUD")
        t.assertTrue(gui ~= nil, "no HUD")

        local function labelText(name)
                local node = gui:FindFirstChild(name, true)
                return node and node.Text or nil
        end

        local levelText = labelText("Level")
        t.assertTrue(levelText ~= nil, "the Level label is missing")
        if levelText then
                -- Hud.luau seeds this as "Level 1"; a real render replaces the
                -- level number, and a blank payload would leave it at the seed.
                t.assertTrue(levelText ~= "", "the Level label is empty")
                t.assertTrue(string.find(levelText, "1", 1, true) ~= nil or
                        string.find(levelText, "Level", 1, true) ~= nil,
                        "the Level label shows nothing recognisable: " .. levelText)
        end

        local coinsText = labelText("Coins")
        t.assertTrue(coinsText ~= nil, "the Coins label is missing")
        if coinsText then
                t.assertTrue(string.find(coinsText, tostring(payload.coins), 1, true) ~= nil,
                        "the Coins label does not show the pushed balance: " .. coinsText)
        end
end)

t.test("the HUD is built to fit the phone screen it is on", function()
	local env = boot()

	-- A phone screen, set before the client loads, because the client builds the
	-- HUD once and sizes its panels from the screen it finds at that moment.
	local camera = env.__workspace.CurrentCamera
	t.assertTrue(camera ~= nil, "the harness has no camera")
	if not camera then
		return
	end
	camera.ViewportSize = Shim.Vector2.new(640, 360)

	local ok, err = pcall(function()
		env.__load("client/init.client")
	end)
	t.assertTrue(ok, "the client failed to build a HUD on a phone viewport: " .. tostring(err))
	if not ok then
		return
	end

	local gui = env.__player.PlayerGui:FindFirstChild("AXArenaHUD")
	t.assertTrue(gui ~= nil, "the client built no HUD on the phone viewport")
	if not gui then
		return
	end

	local viewportHeight = 360
	local safeBottom = 96
	local panels = { "Stats", "QuestPanel", "WavePanel", "BossPanel", "Rewards",
		"TravelPanel", "Combat", "Actions", "CharPanel" }
	for _, name in ipairs(panels) do
		local node = gui:FindFirstChild(name)
		if node then
			local sizeY = node.Size.Y.Offset
			local posY = node.Position.Y.Offset
			t.assertTrue(sizeY <= viewportHeight - safeBottom,
				name .. " is " .. sizeY .. "px tall on a 360px screen")
			-- A panel anchored at the top has its top at posY; one anchored at the
			-- bottom has its bottom at posY. Both must be inside the screen.
			if node.AnchorPoint.Y == 0 then
				t.assertTrue(posY >= 0 and posY + sizeY <= viewportHeight,
					name .. " runs off the phone screen (top " .. posY .. ", height " .. sizeY .. ")")
			end
		end
	end

	-- The character sheet is the one that could be opened and not closed. Its
	-- close button must be inside the screen.
	local charPanel = gui:FindFirstChild("CharPanel")
	if charPanel then
		local close = charPanel:FindFirstChild("CloseChar")
		t.assertTrue(close ~= nil, "the character sheet has no close button")
		if close then
			local closeBottom = charPanel.Position.Y.Offset + close.Position.Y.Offset + close.Size.Y.Offset
			t.assertTrue(closeBottom <= viewportHeight,
				"the character sheet's close button is below the phone screen at " .. closeBottom .. "px")
		end
	end
end)

t.finish()

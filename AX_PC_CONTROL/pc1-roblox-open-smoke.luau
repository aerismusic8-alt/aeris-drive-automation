-- AX Arena: open smoke test.
--
-- Roblox Studio runs this through `--task RunScript`, so it executes in the
-- command bar context against the freshly built local place file. Nothing here
-- touches a published experience, which matters because a brand new universe is
-- unrated and Roblox will not let anyone join it until the owner answers the
-- maturity questionnaire.
--
-- What this proves: the place file opens in real Studio, every shared module
-- loads, both entry points exist, and the world builder runs and produces the
-- town plus five fields with real parts in them.
-- What it cannot prove: that the server loop and the HUD actually run, because
-- Edit mode does not execute Script or LocalScript instances. The play capture
-- step covers that separately.
--
-- Output is one `SMOKE_PASS|label|detail` or `SMOKE_FAIL|label|detail` line per
-- check, so the caller can parse the log without guessing.

local function report(ok: boolean, label: string, detail: string)
	print(string.format("%s|%s|%s", ok and "SMOKE_PASS" or "SMOKE_FAIL", label, detail or ""))
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local shared = ReplicatedStorage:FindFirstChild("Shared")
if not shared then
	report(false, "shared-folder", "ReplicatedStorage.Shared is missing")
	return
end

-- Every shared module is a ModuleScript, so each one can be required here.
-- A module that fails to load is a real defect: it would fail the same way at
-- runtime, just later and less visibly.
local names = {}
for _, child in ipairs(shared:GetChildren()) do
	if child:IsA("ModuleScript") then
		table.insert(names, child.Name)
	end
end
table.sort(names)

report(#names > 0, "module-count", tostring(#names))

local failures = {}
for _, name in ipairs(names) do
	local ok, err = pcall(function()
		return require(shared:FindFirstChild(name))
	end)
	if not ok then
		table.insert(failures, string.format("%s (%s)", name, tostring(err)))
	end
end

report(#failures == 0, "modules-require", table.concat(failures, " ~ "))

-- The two entry points are what actually make the game run, so check the
-- instances Rojo was supposed to create rather than only the module folder.
local serverScript = ServerScriptService:FindFirstChild("AXArenaServer")
report(serverScript ~= nil, "server-script", serverScript and serverScript.ClassName or "missing")

local starterScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
local clientScript = starterScripts and starterScripts:FindFirstChild("AXArenaClient")
report(clientScript ~= nil, "client-script", clientScript and clientScript.ClassName or "missing")

-- The world is built by the server at runtime, so in Edit mode it must be
-- absent. A world already in the place file would mean the build captured
-- runtime state, which is a sign the file was saved from a running session.
local prebuilt = workspace:FindFirstChild("AXArenaWorld")
report(prebuilt == nil, "world-not-baked", prebuilt and "AXArenaWorld is baked into the file" or "clean")

-- Now build the world for real. This is the strongest check available in Edit
-- mode: it runs the same code the server runs on start, so a broken landmark,
-- a bad scenery palette or a field that fails to spawn a floor all surface here
-- instead of in front of a player.
if not serverScript then
	report(false, "world-build", "no server script, cannot build")
	return
end

local ok, err = pcall(function()
	local World = require(serverScript:FindFirstChild("World"))
	World.buildWorld()
end)
if not ok then
	report(false, "world-build", tostring(err))
	return
end
report(true, "world-build", "buildWorld returned")

local world = workspace:FindFirstChild("AXArenaWorld")
if not world then
	report(false, "world-present", "buildWorld did not parent a world into Workspace")
	return
end

local fields = 0
local towns = 0
for _, child in ipairs(world:GetChildren()) do
	if child.Name == "Town" then
		towns += 1
	elseif child.Name:sub(1, 6) == "Field_" then
		fields += 1
	end
end
report(towns == 1, "town-count", tostring(towns))
report(fields == 5, "field-count", tostring(fields))

-- Count real geometry, not just model containers. An empty field model would
-- otherwise pass the count above.
local parts = 0
for _, d in ipairs(world:GetDescendants()) do
	if d:IsA("BasePart") then
		parts += 1
	end
end
report(parts > 500, "world-parts", tostring(parts))

-- Each field needs a floor big enough to stand on, or travelling there drops
-- the player into the void.
local thin = {}
for _, child in ipairs(world:GetChildren()) do
	if child.Name:sub(1, 6) == "Field_" then
		local floor = child:FindFirstChild("FieldFloor")
		if not floor or not floor:IsA("BasePart") or floor.Size.X < 100 then
			table.insert(thin, child.Name)
		end
	end
end
report(#thin == 0, "field-floors", #thin == 0 and "all five have a floor" or table.concat(thin, ","))

report(true, "smoke-complete", string.format("%d modules, %d parts, %d fields", #names, parts, fields))

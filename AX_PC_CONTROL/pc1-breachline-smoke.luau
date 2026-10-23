-- Breachline: Studio edit-mode smoke test.
--
-- Roblox Studio runs this through `--task RunScript`, so it executes against the
-- freshly built local place file. Nothing here touches a published experience.
--
-- What this proves: the place opens in real Studio, the match modules load and
-- answer, all three maps satisfy the contract the rotation reads, and the server
-- and client entry points exist. The map contract is the one that matters most:
-- a map missing a bomb site or a team spawn is invisible to MapRegistry, so the
-- failure would be a rotation that quietly plays one map forever.
--
-- What it cannot prove: that the server loop and the HUD run, because Edit mode
-- does not execute Script or LocalScript instances. Play mode covers that.
--
-- Output is one `SMOKE_PASS|label|detail` or `SMOKE_FAIL|label|detail` line per
-- check, so the caller can parse the log without guessing.

local function report(ok: boolean, label: string, detail: string)
	print(string.format("%s|%s|%s", ok and "SMOKE_PASS" or "SMOKE_FAIL", label, detail or ""))
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

-- --- Match plumbing ------------------------------------------------------

local state = ReplicatedStorage:FindFirstChild("MatchState")
report(state ~= nil, "match-state", state and state.ClassName or "ReplicatedStorage.MatchState is missing")
if state then
	report(state:FindFirstChild("JoinMatch") ~= nil, "join-remote", "MatchState.JoinMatch is missing")
end

local modules = ReplicatedStorage:FindFirstChild("MatchModules")
report(modules ~= nil, "match-modules", modules and modules.ClassName or "ReplicatedStorage.MatchModules is missing")

local rules = modules and modules:FindFirstChild("RoundRules")
local registry = modules and modules:FindFirstChild("MapRegistry")

local okRules, rulesOrErr = pcall(function()
	return require(rules)
end)
report(okRules, "rules-require", okRules and "RoundRules loaded" or tostring(rulesOrErr))

local okRegistry, registryOrErr = pcall(function()
	return require(registry)
end)
report(okRegistry, "registry-require", okRegistry and "MapRegistry loaded" or tostring(registryOrErr))

-- One player must be able to start a round, or a new experience with nobody
-- else on the server parks the first player on "Waiting for Players" forever.
if okRules and type(rulesOrErr) == "table" and rulesOrErr.requiredPlayers then
	local solo = rulesOrErr.requiredPlayers(1)
	report(solo == 1, "solo-round-allowed", "requiredPlayers(1)=" .. tostring(solo))
else
	report(false, "solo-round-allowed", "RoundRules.requiredPlayers is missing")
end

-- --- Maps ----------------------------------------------------------------

if okRegistry and type(registryOrErr) == "table" and registryOrErr.collect then
	local maps = registryOrErr.collect(workspace)
	report(#maps == 3, "map-count", "MapRegistry found " .. tostring(#maps) .. " maps")

	local orders = {}
	local allComplete = true
	for _, map in ipairs(maps) do
		local problems = registryOrErr.problems(map.model)
		if #problems > 0 then
			allComplete = false
			report(false, "map-" .. tostring(map.id), table.concat(problems, "; "))
		else
			report(true, "map-" .. tostring(map.id), tostring(map.name))
		end
		table.insert(orders, map.order)
	end
	report(allComplete, "maps-complete", allComplete and "every map satisfies the contract" or "see the per-map lines")

	table.sort(orders)
	local distinct = true
	for i = 2, #orders do
		if orders[i] == orders[i - 1] then distinct = false end
	end
	report(distinct, "map-orders", table.concat(orders, ","))
else
	report(false, "map-count", "MapRegistry.collect is unavailable")
end

-- --- Entry points --------------------------------------------------------

local serverScript = ServerScriptService:FindFirstChild("MatchManager")
report(serverScript ~= nil, "server-script", serverScript and serverScript.ClassName or "MatchManager is missing")

-- The server admits a player on join because CharacterAutoLoads is off. Without
-- this the client is the only way in, and a client that fails to draw leaves the
-- player with no character at all.
if serverScript and serverScript:IsA("Script") then
	local src = serverScript.Source
	report(src:find("Players.PlayerAdded:Connect", 1, true) ~= nil, "admits-on-join",
		"the server must admit a player without waiting for the client")
	report(src:find("pcall(roundLoopIteration)", 1, true) ~= nil, "loop-guarded",
		"the round loop must survive an error rather than end")
end

local starterScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
for _, name in ipairs({ "MatchHud", "BuyHud" }) do
	local found = starterScripts and starterScripts:FindFirstChild(name)
	report(found ~= nil, "client-" .. name, found and found.ClassName or (name .. " is missing"))
end

print("SMOKE_DONE")

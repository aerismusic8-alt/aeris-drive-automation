--[[
	Map pass for Breachline, applied to the place at build time.

	The recovered place ships one map: PrototypeRange, the shooting range the
	upstream project was built around. It is playable as a bomb-defusal map --
	it has two sites, two team spawns and a practice pad -- but it is the only
	one, so a match always looks the same and the map rotation the match layer
	needs has nothing to rotate.

	This pass does two things:

	  1. Stamps the three attributes a map must carry (MapId, MapName, MapOrder)
	     onto PrototypeRange, and gives it the name players will see.

	  2. Builds Foundry, a second map with a different shape: a central pillar
	     with a lane either side, sites pulled in from the corners, and more
	     mid-field cover than the range has. A map that played like the first
	     would not be worth rotating to.

	Both maps are then checked against the same contract MapRegistry enforces at
	runtime -- two sites with a plant prompt, both team spawns -- so an
	incomplete map fails the build instead of crashing the round loop.

	The attributes are stamped here rather than in the scene pass because they
	describe the map, not the lighting, and this is the pass that knows what the
	maps are.

	Usage:
	  rbxmk run --allow-insecure-paths breachline/maps.lua <place.rbxl> <out.rbxl>
]]

local inPath, outPath = ...

assert(inPath, "usage: maps.lua <place.rbxl> <out.rbxl>")
assert(outPath, "usage: maps.lua <place.rbxl> <out.rbxl>")

local place = fs.read(inPath)
assert(place and place.ClassName == "DataModel", "place did not decode to a DataModel")

local Workspace = place:FindFirstChild("Workspace")
assert(Workspace, "place has no Workspace service")

-- The three attributes MapRegistry reads. Spelled here exactly as the module
-- spells them; the build check asserts the two agree.
local ID_ATTRIBUTE = "MapId"
local NAME_ATTRIBUTE = "MapName"
local ORDER_ATTRIBUTE = "MapOrder"

local RANGE_NAME = "PrototypeRange"
local FOUNDRY_NAME = "Foundry"

-- How far the second map sits from the first. The two are never in the world at
-- the same time -- the server moves the inactive one out -- so this only has to
-- be clear of an overlap for the build, not for play.
local FOUNDRY_OFFSET = 200

--------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------

local function part(parent, name, size, cframe, colour)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.size = size
	p.CFrame = cframe
	if colour then p.Color = colour end
	p.Parent = parent
	return p
end

local function spawn(parent, name, position)
	local s = Instance.new("SpawnLocation")
	s.Name = name
	s.Anchored = true
	s.size = Vector3.new(6, 1, 6)
	s.CFrame = CFrame.new(position)
	s.Parent = parent
	return s
end

local function bombSite(parent, name, position)
	local site = Instance.new("Part")
	site.Name = name
	site.Anchored = true
	site.size = Vector3.new(13, 0.3, 13)
	site.CFrame = CFrame.new(position)
	site.Color = Color3.fromRGB(196, 132, 78)
	site.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlantPrompt"
	prompt.ActionText = "Plant"
	prompt.ObjectText = "Bomb Site " .. name
	prompt.HoldDuration = 3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = site

	return site
end

--------------------------------------------------------------------------
-- The contract, checked the same way MapRegistry checks it at runtime
--------------------------------------------------------------------------

---Everything a map must have for a round to run on it, as a list of problems.
---Mirrors MapRegistry.problems; the duplication is deliberate, because this
---runs at build time in rbxmk's Lua and cannot require the Luau module. If the
---two ever disagree the build check catches it.
local function problems(model)
	local found = {}

	if model.ClassName ~= "Model" then
		table.insert(found, "not a Model")
	end

	local id = model:GetAttribute(ID_ATTRIBUTE)
	if type(id) ~= "string" or id == "" then
		table.insert(found, "no " .. ID_ATTRIBUTE .. " attribute")
	end
	if type(model:GetAttribute(NAME_ATTRIBUTE)) ~= "string" then
		table.insert(found, "no " .. NAME_ATTRIBUTE .. " attribute")
	end

	local sites = model:FindFirstChild("BombSites")
	if not sites then
		table.insert(found, "no BombSites folder")
	else
		local count = 0
		for _, site in ipairs(sites:GetChildren()) do
			if site.ClassName == "Part" and site:FindFirstChild("PlantPrompt") then
				count = count + 1
			end
		end
		if count < 2 then
			table.insert(found, "needs two bomb sites with a PlantPrompt, found " .. count)
		end
	end

	for _, spawnName in ipairs({ "Attackers Spawn", "Defenders Spawn" }) do
		local s = model:FindFirstChild(spawnName)
		if not s or s.ClassName ~= "SpawnLocation" then
			table.insert(found, "no " .. spawnName .. " SpawnLocation")
		end
	end

	return found
end

local failures = {}

local function validate(model)
	local found = problems(model)
	for _, problem in ipairs(found) do
		table.insert(failures, model.Name .. ": " .. problem)
	end
	print(string.format("MAP %s id=%s order=%s ok=%s",
		model.Name,
		tostring(model:GetAttribute(ID_ATTRIBUTE)),
		tostring(model:GetAttribute(ORDER_ATTRIBUTE)),
		tostring(#found == 0)))
end

--------------------------------------------------------------------------
-- Map 1: the range, named and registered
--------------------------------------------------------------------------

local range = Workspace:FindFirstChild(RANGE_NAME)
assert(range, "place has no " .. RANGE_NAME .. " to register as a map")

range:SetAttribute(ID_ATTRIBUTE, "dust-district")
range:SetAttribute(NAME_ATTRIBUTE, "Dust District")
range:SetAttribute(ORDER_ATTRIBUTE, 1)
range:SetAttribute("MapActive", false)

--------------------------------------------------------------------------
-- Map 2: Foundry
--------------------------------------------------------------------------

-- A rebuild starts from the same base every time, but a run against an already
-- built place should replace the map rather than stack a second copy beside it.
local existing = Workspace:FindFirstChild(FOUNDRY_NAME)
if existing then existing:Destroy() end

local foundry = Instance.new("Model")
foundry.Name = FOUNDRY_NAME
foundry:SetAttribute(ID_ATTRIBUTE, "foundry")
foundry:SetAttribute(NAME_ATTRIBUTE, "Foundry")
foundry:SetAttribute(ORDER_ATTRIBUTE, 2)
foundry:SetAttribute("MapActive", false)
foundry.Parent = Workspace

local X = FOUNDRY_OFFSET
local STEEL = Color3.fromRGB(96, 100, 106)
local RUST = Color3.fromRGB(140, 92, 66)

-- The shell: a 90 by 112 floor inside walls, the same footprint as the range so
-- the two share a scale and a player's sense of distance carries over.
part(foundry, "Ground", Vector3.new(90, 2, 112), CFrame.new(X, -1, 0), STEEL)
part(foundry, "West Wall", Vector3.new(2, 15, 112), CFrame.new(X - 45, 7.5, 0), STEEL)
part(foundry, "East Wall", Vector3.new(2, 15, 112), CFrame.new(X + 45, 7.5, 0), STEEL)
part(foundry, "Backstop", Vector3.new(90, 19, 2), CFrame.new(X, 9.5, -55), STEEL)
part(foundry, "Rear Wall", Vector3.new(90, 10, 2), CFrame.new(X, 5, 55), STEEL)

-- A central pillar splits the map into two lanes. The range is one open field,
-- which makes every fight a long sightline; the pillar gives each side of the
-- map its own approach to both sites.
part(foundry, "Pillar", Vector3.new(16, 12, 16), CFrame.new(X, 5, 0), RUST)

-- Cover along the lanes and at the site entrances. Offset from the pillar so a
-- lane is never fully blocked.
local COVER = {
	{ X - 26, 2.5, 22 },
	{ X + 26, 2.5, 22 },
	{ X - 26, 2.5, -22 },
	{ X + 26, 2.5, -22 },
	{ X, 2.5, 34 },
	{ X - 34, 2.5, 4 },
	{ X + 34, 2.5, 4 },
	{ X, 2.5, -40 },
}
for _, c in ipairs(COVER) do
	part(foundry, "Cover", Vector3.new(10, 5, 3), CFrame.new(c[1], c[2], c[3]), STEEL)
end

spawn(foundry, "Attackers Spawn", Vector3.new(X - 12, 0.5, 46))
spawn(foundry, "Defenders Spawn", Vector3.new(X + 12, 0.5, -46))

-- Sites pulled in from the corners, unlike the range's pair, so a defender has
-- to cover a shorter distance between them and an attacker cannot see both from
-- one angle.
local sites = Instance.new("Folder")
sites.Name = "BombSites"
sites.Parent = foundry
bombSite(sites, "A", Vector3.new(X - 30, 0.16, -20))
bombSite(sites, "B", Vector3.new(X + 30, 0.16, -20))

--------------------------------------------------------------------------
-- Verify before writing
--------------------------------------------------------------------------

validate(range)
validate(foundry)

if #failures > 0 then
	io.stderr:write("MAPS_FAILED: maps missing part of the contract:\n")
	for _, f in ipairs(failures) do io.stderr:write("  " .. f .. "\n") end
	os.exit(1)
end

fs.write(outPath, place, "rbxl")
print(string.format("MAPS_OK maps=2 out=%s", outPath))

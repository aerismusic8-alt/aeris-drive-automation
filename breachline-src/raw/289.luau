--[[
TestFixtures - Generates Part-based placeholder models for testing capabilities

Given a capability name and a schema, creates a simple Model in workspace
with correctly named Part children and a FourDCapability tag + CapabilityName attribute.
Useful for testing capability bind() without real mesh assets.
]]

local CollectionService = game:GetService("CollectionService")
local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local ModelSchemaUtils = require(Capabilities.ModelSchemaUtils)

local TestFixtures = {}

local PART_COLORS = {
	body = BrickColor.new("Medium stone grey"),
	hull = BrickColor.new("Medium stone grey"),
	frame = BrickColor.new("Medium stone grey"),
	chassis = BrickColor.new("Dark stone grey"),
	undercarriage = BrickColor.new("Dark stone grey"),
	default_wheel = BrickColor.new("Black"),
	default_special = BrickColor.new("Bright red"),
	gun = BrickColor.new("Really black"),
	cannon = BrickColor.new("Really black"),
}

local PART_SIZES = {
	body = Vector3.new(4, 2, 8),
	hull = Vector3.new(5, 3, 12),
	frame = Vector3.new(4, 2, 8),
	chassis = Vector3.new(4, 0.4, 8),
	undercarriage = Vector3.new(4, 1, 6),
	default_wheel = Vector3.new(1, 2, 2),
	default_small = Vector3.new(1, 1, 1),
	gun = Vector3.new(0.6, 0.6, 2),
	cannon = Vector3.new(0.8, 0.8, 3),
	carpet = Vector3.new(4, 0.2, 6),
}

local function isWheelPart(name)
	return name:find("wheel") or name:find("roller") or name:find("tread") or name:find("rotor")
end

local function getPartColor(name)
	local lower = name:lower()
	if PART_COLORS[lower] then return PART_COLORS[lower] end
	if isWheelPart(lower) then return PART_COLORS.default_wheel end
	return PART_COLORS.default_special
end

local function getPartSize(name)
	local lower = name:lower()
	if PART_SIZES[lower] then return PART_SIZES[lower] end
	if isWheelPart(lower) then return PART_SIZES.default_wheel end
	if lower:find("body") or lower:find("hull") or lower:find("frame") then
		return PART_SIZES.body
	end
	if lower:find("gun") or lower:find("cannon") then
		return PART_SIZES.gun
	end
	return PART_SIZES.default_small
end

local function getWheelPosition(name, bodySize)
	local lower = name:lower()
	local halfX = bodySize.X / 2 + 0.5
	local halfZ = bodySize.Z / 2 - 1
	local y = 1

	local isFront = lower:find("front")
	local isRear = lower:find("rear")
	local isLeft = lower:find("left")
	local isRight = lower:find("right")
	local isMid = lower:find("mid")

	local z = 0
	if isFront then z = -halfZ
	elseif isRear then z = halfZ
	elseif isMid then z = 0 end

	local x = 0
	if isLeft then x = -halfX
	elseif isRight then x = halfX end

	return Vector3.new(x, y, z)
end

function TestFixtures.createFixture(capabilityName, schemaName, spawnPosition)
	spawnPosition = spawnPosition or Vector3.new(0, 5, 0)

	local labels = ModelSchemaUtils.getComponentLabels(schemaName)

	local model = Instance.new("Model")
	model.Name = "Test" .. schemaName

	CollectionService:AddTag(model, "FourDCapability")
	model:SetAttribute("CapabilityName", capabilityName)

	local bodySize = PART_SIZES.body
	for _, partLabel in ipairs(labels) do
		if partLabel:lower():find("body") or partLabel:lower():find("hull") or partLabel:lower():find("frame")
			or partLabel:lower():find("chassis") or partLabel:lower():find("undercarriage")
			or partLabel:lower():find("cart") or partLabel:lower():find("carpet") then
			bodySize = getPartSize(partLabel)
			break
		end
	end

	local partIndex = 0
	for _, partLabel in ipairs(labels) do
		local part = Instance.new("Part")
		part.Name = partLabel
		part.Size = getPartSize(partLabel)
		part.BrickColor = getPartColor(partLabel)
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth

		if isWheelPart(partLabel:lower()) then
			part.Shape = Enum.PartType.Cylinder
			part.CFrame = CFrame.new(spawnPosition + getWheelPosition(partLabel, bodySize))
				* CFrame.Angles(0, 0, math.rad(90))
		else
			local offset = Vector3.new(0, bodySize.Y / 2 + partIndex * 0.5, 0)
			part.CFrame = CFrame.new(spawnPosition + offset)
		end

		part.Parent = model
		partIndex += 1
	end

	local primaryPart = model:FindFirstChild("body")
		or model:FindFirstChild("hull")
		or model:FindFirstChild("frame")
		or model:FindFirstChild("chassis")
		or model:FindFirstChild("undercarriage")
		or model:FindFirstChild("cart")
		or model:FindFirstChild("carpet")
	if primaryPart then
		model.PrimaryPart = primaryPart
	end

	return model
end

function TestFixtures.spawnFixture(capabilityName, schemaName, spawnPosition)
	local model = TestFixtures.createFixture(capabilityName, schemaName, spawnPosition)
	model.Parent = workspace
	return model
end

return TestFixtures

--[[
Trailer4 Capability - Passive towable receiver (no drive, no engine)

Composes: Towable receiver only
Schema: Trailer4 (body, left wheel, right wheel, hitch)
A passive vehicle that gets towed by other vehicles.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Beh = FourD:FindFirstChild("Behaviors")
local Towable = require(Beh.Towable)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

local WHEEL_DENSITY = 10
local WHEEL_FRICTION = 1
local BODY_DENSITY = 0.2

local function isWheelPart(part: BasePart, leftWheel: Instance, rightWheel: Instance): boolean
	return part == leftWheel
		or part == rightWheel
		or part:IsDescendantOf(leftWheel)
		or part:IsDescendantOf(rightWheel)
end

local function applyWheelDensity(part: BasePart): ()
	local existing = part.CustomPhysicalProperties
	part.CustomPhysicalProperties = PhysicalProperties.new(
		WHEEL_DENSITY,
		WHEEL_FRICTION,
		if existing then existing.Elasticity else 0.5,
		if existing then existing.FrictionWeight else 1,
		if existing then existing.ElasticityWeight else 1
	)
end

local function applyBodyDensity(part: BasePart): ()
	local existing = part.CustomPhysicalProperties
	part.CustomPhysicalProperties = PhysicalProperties.new(
		BODY_DENSITY,
		if existing then existing.Friction else 0.3,
		if existing then existing.Elasticity else 0.5,
		if existing then existing.FrictionWeight else 1,
		if existing then existing.ElasticityWeight else 1
	)
end

local function makeFunctional(root: Model, _): Model
	local body = root:FindFirstChild("body")
	local leftWheel = root:FindFirstChild("left wheel")
	local rightWheel = root:FindFirstChild("right wheel")
	local hitch = root:FindFirstChild("hitch")

	if not body then error("Missing 'body'") end
	if not leftWheel then error("Missing 'left wheel'") end
	if not rightWheel then error("Missing 'right wheel'") end
	if not hitch then error("Missing 'hitch'") end

	local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
	ConstructionHelpers.weldAllParts(body, bodyAnchor)
	ConstructionHelpers.weldAllParts(leftWheel, bodyAnchor)
	ConstructionHelpers.weldAllParts(rightWheel, bodyAnchor)
	ConstructionHelpers.weldAllParts(hitch, bodyAnchor)

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			if isWheelPart(descendant, leftWheel, rightWheel) then
				descendant.Massless = false
				applyWheelDensity(descendant)
			else
				descendant.Massless = false
				applyBodyDensity(descendant)
			end
		end
	end

	Towable.setupTowable(root, hitch)

	return root
end

local Trailer4 = CapabilityBase.createChild()

function Trailer4:getCapabilityDocumentation()
	return [[
The Trailer4Capability creates a passive towable trailer. It has no engine or drive - it gets towed
by vehicles with a Towable hitch (e.g. tractors, trucks). The hitch is set up as a receiver for connection.
]]
end

function Trailer4:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "Trailer4",
			description = "a trailer with body, left wheel, right wheel, and hitch",
		},
	}
end

function Trailer4:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Trailer4:getCapabilitySelectionExamples()
	return {
		{
			user = "a trailer",
			assistant = {
				capability_reasoning = 'A trailer is a passive towable vehicle. Trailer4Capability handles this.',
				capability_selection = "Trailer4Capability",
				overall_size_reasoning = "A small trailer is about 2m wide, 1m tall, 3m long.",
				overall_size_selection = { x = 2, y = 1, z = 3 },
			},
		},
	}
end

function Trailer4:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("Trailer4Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model in generatedModels") end

	return makeFunctional(carModel, parameters)
end

return Trailer4
)
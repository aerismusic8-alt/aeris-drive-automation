--[[
Wheelchair7 Capability - Four-wheeled wheelchair pushed from behind, ridden by a passenger

Composes: Pushable behavior (grab push handles, walk to push, IK hands)
Adds: a passive rider Seat (no driving control) placed on the seat part
Schema: Wheelchair7 (frame, seat, push handles, 4 wheels)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Pushable = require(FourD.Behaviors.Pushable)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local recenterModelPivot = require(FourD.Common.recenterModelPivot)

local WHEEL_NAMES = {
	"left front wheel",
	"right front wheel",
	"left rear wheel",
	"right rear wheel",
}

local RIDER_SEAT_HEIGHT = 0.5
local PUSH_WALK_SPEED = 10

local function bounds(instance: PVInstance): (CFrame, Vector3)
	if instance:IsA("BasePart") then return instance.CFrame, instance.Size end
	return (instance :: Model):GetBoundingBox()
end

local function bottomOffsetY(cf: CFrame, size: Vector3): number
	-- World-space distance from a part's center down to its lowest point. A wheel
	-- authored as a single rotated BasePart spreads its vertical extent across its
	-- local axes, so `size.Y / 2` alone lands the ground contact above the true
	-- bottom; project every local axis onto world Y. Models are recentered above,
	-- so their bounds are already world-aligned and this reduces to `size.Y / 2`.
	return 0.5 * (
		math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z
	)
end

local function makeFunctional(root, _)
	local frame = root:FindFirstChild("frame")
	local handles = root:FindFirstChild("push handles")
	local seatPart = root:FindFirstChild("seat")

	if not frame then error("Missing 'frame'") end
	if not handles then error("Missing 'push handles'") end
	if not seatPart then error("Missing 'seat'") end
	for _, wheelName in ipairs(WHEEL_NAMES) do
		if not root:FindFirstChild(wheelName) then error("Missing '" .. wheelName .. "'") end
	end

	for _, child in root:GetChildren() do
		if child:IsA("Model") then
			recenterModelPivot(child, true)
		end
	end

	local frameAnchor = GeometryUtils.getOrSetPrimaryPart(frame)
	if not frameAnchor then error("Could not resolve a chassis part from 'frame'") end

	root.PrimaryPart = frameAnchor
	ConstructionHelpers.weldAllParts(root, frameAnchor)

	for _, part in ipairs(GeometryUtils.getInstanceParts(root)) do
		if part ~= frameAnchor then
			part.Massless = true
		end
		part.CanCollide = false
	end

	frameAnchor.Anchored = true

	local function wheelCenter(wheelName: string): Vector3?
		local wheel = root:FindFirstChild(wheelName)
		return if wheel and wheel:IsA("PVInstance") then (bounds(wheel)).Position else nil
	end

	local pushConfig: Pushable.PushableConfig = {}
	pushConfig.WalkSpeed = PUSH_WALK_SPEED
	pushConfig.ObjectText = "Wheelchair"
	local forwardDir = frameAnchor.CFrame.LookVector
	local leftFront = wheelCenter("left front wheel")
	local rightFront = wheelCenter("right front wheel")
	local leftRear = wheelCenter("left rear wheel")
	local rightRear = wheelCenter("right rear wheel")
	if leftFront and rightFront and leftRear and rightRear then
		local forward = ((leftFront + rightFront) / 2) - ((leftRear + rightRear) / 2)
		forward = Vector3.new(forward.X, 0, forward.Z)
		if forward.Magnitude >= 1e-3 then
			forwardDir = forward.Unit
			pushConfig.ForwardWorld = forwardDir
		end
	end

	local groundContacts = {}
	local wheels = {}
	for _, wheelName in ipairs(WHEEL_NAMES) do
		local wheel = root:FindFirstChild(wheelName)
		if wheel and wheel:IsA("PVInstance") then
			local wheelCFrame, wheelSize = bounds(wheel)
			table.insert(groundContacts, wheelCFrame.Position - Vector3.new(0, bottomOffsetY(wheelCFrame, wheelSize), 0))
			table.insert(wheels, wheel)
		end
	end
	if #groundContacts == #WHEEL_NAMES then
		pushConfig.GroundContacts = groundContacts
	end
	if #wheels == #WHEEL_NAMES then
		pushConfig.Wheels = wheels
	end

	Pushable.setup(root, handles, pushConfig)

	local seatCFrame, seatSize = bounds(seatPart :: PVInstance)
	local seatTopY = seatCFrame.Position.Y + (seatSize.Y / 2)
	local riderSeat = Instance.new("Seat")
	riderSeat.Name = "RiderSeat"
	riderSeat.Size = Vector3.new(
		math.clamp(seatSize.X, 1, 2),
		RIDER_SEAT_HEIGHT,
		math.clamp(seatSize.Z, 1, 2)
	)
	riderSeat.Transparency = 1
	riderSeat.CanCollide = false
	riderSeat.Massless = true
	riderSeat.Anchored = false
	local seatPosition = Vector3.new(seatCFrame.Position.X, seatTopY - (RIDER_SEAT_HEIGHT / 2), seatCFrame.Position.Z)
	riderSeat.CFrame = CFrame.lookAlong(seatPosition, forwardDir)
	riderSeat.Parent = root
	ConstructionHelpers.makeWeld(frameAnchor, riderSeat)

	local clientTemplate = script.Parent:FindFirstChild("WheelchairClient")
	if clientTemplate then
		local clone = clientTemplate:Clone()
		if clone:IsA("BaseScript") then
			clone.Enabled = true
		end
		clone.Parent = root
	else
		warn("[Wheelchair7] WheelchairClient template not found in capability folder")
	end

	return root
end

local Wheelchair7 = CapabilityBase.createChild()

function Wheelchair7:getCapabilityDocumentation()
	return [[
The Wheelchair7Capability creates a functional wheelchair from parts with four wheels, a seat, and push handles.
Composes the Pushable behavior: one player grabs the push handles via a ProximityPrompt and pushes the wheelchair by walking, with their hands driven onto the handles by IK.
A second player can ride in the wheelchair by walking onto the seat to sit down; the rider has no control over the wheelchair and exits by jumping.
]]
end

function Wheelchair7:getModelSpecs()
	return {
		{
			name = "wheelchair",
			modelSchema = "Wheelchair7",
			description = "a wheelchair with frame, seat, push handles, and four wheels",
		},
	}
end

function Wheelchair7:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Wheelchair7:getCapabilitySelectionExamples()
	return {
		{
			user = "a wheelchair",
			assistant = {
				capability_reasoning = "A wheelchair is a four-wheeled seat pushed from behind by another person. Wheelchair7Capability handles this schema.",
				capability_selection = "Wheelchair7Capability",
				overall_size_reasoning = "A wheelchair is about 1m long, 0.6m wide, 0.9m tall.",
				overall_size_selection = { x = 0.6, y = 0.9, z = 1.0 },
			},
		},
	}
end

function Wheelchair7:getConfigureCapabilityExamples()
	return {
		{
			user = "a wheelchair",
			assistant = {
				capability_parameters_reasoning = "Wheelchair has no configurable parameters.",
				capability_parameters_selection = {},
			},
		},
	}
end

function Wheelchair7:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Wheelchair7Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["wheelchair"]
	if not model then error("Could not find 'wheelchair' model in generatedModels") end

	return makeFunctional(model, parameters)
end

return Wheelchair7
d
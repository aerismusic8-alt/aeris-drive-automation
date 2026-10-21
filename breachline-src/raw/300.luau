--[[
ShoppingCart6 Capability - Four-wheeled shopping cart with handlebar

Composes: Pushable behavior (grab handle, walk to push, IK hands)
Schema: ShoppingCart6 (frame, handlebar, 4 wheels)
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

local PUSH_WALK_SPEED = 12

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

local function MakeFunctional(root, _)
	local frame = root:FindFirstChild("frame")
	local handlebar = root:FindFirstChild("handlebar")

	if not frame then error("Missing 'frame'") end
	if not handlebar then error("Missing 'handlebar'") end
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
	local leftFront = wheelCenter("left front wheel")
	local rightFront = wheelCenter("right front wheel")
	local leftRear = wheelCenter("left rear wheel")
	local rightRear = wheelCenter("right rear wheel")
	if leftFront and rightFront and leftRear and rightRear then
		local forward = ((leftFront + rightFront) / 2) - ((leftRear + rightRear) / 2)
		forward = Vector3.new(forward.X, 0, forward.Z)
		if forward.Magnitude >= 1e-3 then
			pushConfig.ForwardWorld = forward.Unit
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

	Pushable.setup(root, handlebar, pushConfig)

	return root
end

local ShoppingCart6 = CapabilityBase.createChild()

function ShoppingCart6:getCapabilityDocumentation()
	return [[
The ShoppingCart6Capability creates a functional shopping cart from parts with four wheels and a handlebar.
Composes the Pushable behavior: a player grabs the handlebar via a ProximityPrompt and pushes the cart by walking, with their hands driven onto the handle by IK.
]]
end

function ShoppingCart6:getModelSpecs()
	return {
		{
			name = "shoppingCart",
			modelSchema = "ShoppingCart6",
			description = "a shopping cart with frame, handlebar, and four wheels",
		},
	}
end

function ShoppingCart6:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function ShoppingCart6:getCapabilitySelectionExamples()
	return {
		{
			user = "a shopping cart",
			assistant = {
				capability_reasoning = "Shopping cart is a four-wheeled cart pushed by hand. ShoppingCart6Capability handles this schema.",
				capability_selection = "ShoppingCart6Capability",
				overall_size_reasoning = "A shopping cart is about 1m long, 0.5m wide, 1m tall.",
				overall_size_selection = { x = 0.5, y = 1.0, z = 1.0 },
			},
		},
	}
end

function ShoppingCart6:getConfigureCapabilityExamples()
	return {
		{
			user = "a shopping cart",
			assistant = {
				capability_parameters_reasoning = "Shopping cart has no configurable parameters.",
				capability_parameters_selection = {},
			},
		},
	}
end

function ShoppingCart6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("ShoppingCart6Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["shoppingCart"]
	if not model then error("Could not find 'shoppingCart' model in generatedModels") end

	return MakeFunctional(model, parameters)
end

return ShoppingCart6

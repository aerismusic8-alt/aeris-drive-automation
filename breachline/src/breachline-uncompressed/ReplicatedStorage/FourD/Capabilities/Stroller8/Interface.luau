--[[
Stroller8 Capability - Baby stroller with canopy and handlebar

Composes: Pushable behavior (grab handle, walk to push, IK hands)
Schema: Stroller8 (frame, canopy, seat, handlebar, 4 wheels)
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

	local pushConfig: Pushable.PushableConfig = {}
	pushConfig.WalkSpeed = PUSH_WALK_SPEED
	pushConfig.ObjectText = "Stroller"
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

local Stroller8 = CapabilityBase.createChild()

function Stroller8:getCapabilityDocumentation()
	return [[
The Stroller8Capability creates a functional baby stroller from parts with four wheels, canopy, seat, and handlebar.
Composes the Pushable behavior: a player grabs the handlebar via a ProximityPrompt and pushes the stroller by walking, with their hands driven onto the handle by IK.
]]
end

function Stroller8:getModelSpecs()
	return {
		{
			name = "stroller",
			modelSchema = "Stroller8",
			description = "a baby stroller with frame, canopy, seat, handlebar, and four wheels",
		},
	}
end

function Stroller8:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Stroller8:getCapabilitySelectionExamples()
	return {
		{
			user = "a baby stroller",
			assistant = {
				capability_reasoning = "Stroller is a four-wheeled cart pushed by hand. Stroller8Capability handles this schema.",
				capability_selection = "Stroller8Capability",
				overall_size_reasoning = "A stroller is about 1m long, 0.5m wide, 1m tall.",
				overall_size_selection = { x = 0.5, y = 1.0, z = 1.0 },
			},
		},
	}
end

function Stroller8:getConfigureCapabilityExamples()
	return {
		{
			user = "a stroller",
			assistant = {
				capability_parameters_reasoning = "Stroller has no configurable parameters.",
				capability_parameters_selection = {},
			},
		},
	}
end

function Stroller8:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Stroller8Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["stroller"]
	if not model then error("Could not find 'stroller' model in generatedModels") end

	return MakeFunctional(model, parameters)
end

return Stroller8

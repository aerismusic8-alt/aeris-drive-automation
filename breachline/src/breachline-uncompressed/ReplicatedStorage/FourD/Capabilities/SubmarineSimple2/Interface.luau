--[[
SubmarineSimple2 Capability - Submersible water vehicle with thrust, steering, and depth controls

Composes: WaterSubmersible Architect
Schema: SubmarineSimple2 (hull, propeller)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WaterSubmersibleArchitect = require(FourD.Architects.WaterSubmersible)

local function MakeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local hull = root:FindFirstChild("hull")
	local propeller = root:FindFirstChild("propeller")

	if not hull then error("Missing 'hull' child in submarine model") end
	if not propeller then error("Missing 'propeller' child in submarine model") end

	WaterSubmersibleArchitect.build(root, {
		Acceleration = config.acceleration,
		DepthChangeSpeed = config.depthChangeSpeed,
		MaxForwardSpeed = config.maxForwardSpeed,
		MaxReverseSpeed = config.maxReverseSpeed,
		MaxTurnSpeed = config.maxTurnSpeed,
		Rotors = { propeller },
		TurnAcceleration = config.turnAcceleration,
	})

	return root.Parent
end

local SubmarineSimple2 = CapabilityBase.createChild()

function SubmarineSimple2:getCapabilityDocumentation()
	return [[
The SubmarineSimple2Capability creates a functional submarine that can travel underwater. The player sits in a driver seat and controls the vessel with WASD: W/S for forward and reverse throttle, A/D for steering. E dives the submarine deeper; Q surfaces it. Releasing E or Q holds the current depth. The propeller spins visually when throttle is applied. All speed and turning parameters are specified in real units (studs/second, degrees/second).
]]
end

function SubmarineSimple2:getModelSpecs()
	return {
		{
			name = "submarine",
			modelSchema = "SubmarineSimple2",
			description = "a submarine with a hull and propeller",
		},
	}
end

function SubmarineSimple2:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxForwardSpeed", {
			type = "number",
			default = 45,
			description = "Maximum forward speed in studs per second",
		})
		:addOptionalArgument("maxReverseSpeed", {
			type = "number",
			default = 20,
			description = "Maximum reverse speed in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 4,
			description = "How quickly the submarine reaches top speed, in studs per second squared",
		})
		:addOptionalArgument("maxTurnSpeed", {
			type = "number",
			default = 45,
			description = "Maximum turning speed in degrees per second",
		})
		:addOptionalArgument("turnAcceleration", {
			type = "number",
			default = 30,
			description = "How quickly the submarine reaches max turn speed, in degrees per second squared",
		})
		:addOptionalArgument("depthChangeSpeed", {
			type = "number",
			default = 15,
			description = "Speed at which the submarine dives or surfaces, in studs per second",
		})
		:build()
end

function SubmarineSimple2:getCapabilitySelectionExamples()
	return {
		{
			user = "a submarine",
			assistant = {
				capability_reasoning = "The user wants a submarine, which is an underwater vessel that can dive and surface. SubmarineSimple2Capability creates a functional submersible with buoyancy, thrust, steering, and dive/surface controls.",
				capability_selection = "SubmarineSimple2Capability",
				overall_size_reasoning = "A submarine should be elongated and cylindrical, roughly 2.0m wide, 1.8m tall, and 7m long to fit a Roblox avatar inside.",
				overall_size_selection = { x = 2.0, y = 1.8, z = 7.0 },
			},
		},
		{
			user = "a yellow submarine",
			assistant = {
				capability_reasoning = "A yellow submarine is still a submarine — an underwater vessel with dive capability. SubmarineSimple2Capability is the correct choice; the color is handled by model generation.",
				capability_selection = "SubmarineSimple2Capability",
				overall_size_reasoning = "A classic submarine shape, roughly 2.0m wide, 2.0m tall, and 6m long.",
				overall_size_selection = { x = 2.0, y = 2.0, z = 6.0 },
			},
		},
	}
end

function SubmarineSimple2:getConfigureCapabilityExamples()
	return {
		{
			user = "a submarine",
			assistant = {
				capability_parameters_reasoning = "A standard submarine uses default thrust, steering, and dive speed values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast submarine",
			assistant = {
				capability_parameters_reasoning = "A fast submarine should have a higher top speed and quicker acceleration.",
				capability_parameters_selection = {
					maxForwardSpeed = 70,
					maxReverseSpeed = 35,
					acceleration = 15,
				},
			},
		},
	}
end

function SubmarineSimple2:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("SubmarineSimple2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["submarine"]
	if not model then
		error("Could not find 'submarine' model in generatedModels")
	end

	return MakeFunctional(model, parameters)
end

return SubmarineSimple2

--[[
MotorboatSimple2 Capability - Drivable water vehicle with buoyancy and thrust

Composes: WaterVehicle2 Architect
Schema: MotorboatSimple2 (body, motor)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WaterVehicleArchitect = require(FourD.Architects.WaterVehicle2)

local function MakeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local body = root:FindFirstChild("body")
	local motor = root:FindFirstChild("motor")

	if not body then error("Missing 'body' child in motorboat model") end
	if not motor then error("Missing 'motor' child in motorboat model") end

	WaterVehicleArchitect.build(root, {
		Acceleration = config.acceleration,
		Draft = 0.4,
		MaxForwardSpeed = config.maxForwardSpeed,
		MaxReverseSpeed = config.maxReverseSpeed,
		MaxTurnSpeed = config.maxTurnSpeed,
		SternReference = motor,
		TurnAcceleration = config.turnAcceleration,
	})

	return root.Parent
end

local MotorboatSimple2 = CapabilityBase.createChild()

function MotorboatSimple2:getCapabilityDocumentation()
	return [[
The MotorboatSimple2Capability creates a functional motorboat that floats on water. The player sits in a driver seat and controls the boat with WASD: W/S for throttle forward and reverse, A/D for steering. Buoyancy is simulated with a spring-damper system that keeps the hull at the water surface.
]]
end

function MotorboatSimple2:getModelSpecs()
	return {
		{
			name = "motorboat",
			modelSchema = "MotorboatSimple2",
			description = "a motorboat with a hull body and an outboard motor",
		},
	}
end

function MotorboatSimple2:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxForwardSpeed", {
			type = "number",
			default = 50,
			description = "Maximum forward speed in studs/sec",
		})
		:addOptionalArgument("maxReverseSpeed", {
			type = "number",
			default = 15,
			description = "Maximum reverse speed in studs/sec",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 6,
			description = "Surge acceleration rate in studs/sec^2",
		})
		:addOptionalArgument("maxTurnSpeed", {
			type = "number",
			default = 50,
			description = "Maximum yaw rate in degrees/sec",
		})
		:addOptionalArgument("turnAcceleration", {
			type = "number",
			default = 30,
			description = "Yaw acceleration rate in degrees/sec^2",
		})
		:build()
end

function MotorboatSimple2:getCapabilitySelectionExamples()
	return {
		{
			user = "a motorboat",
			assistant = {
				capability_reasoning = 'The user wants a motorboat, which is a water vehicle with an engine that players can drive. This maps directly to MotorboatSimple2Capability which creates a functional motorboat with buoyancy, thrust, and steering.',
				capability_selection = "MotorboatSimple2Capability",
				overall_size_reasoning = "A typical motorboat should fit one Roblox avatar (1.5m tall) in a driver seat. A small motorboat is around 1.5m wide, 1.3m tall, and 4m long.",
				overall_size_selection = { x = 1.5, y = 1.3, z = 4.0 },
			},
		},
		{
			user = "a speedboat",
			assistant = {
				capability_reasoning = 'A speedboat is a fast motorboat — it is a water vehicle driven by a motor. MotorboatSimple2Capability is the correct choice for any motor-driven boat.',
				capability_selection = "MotorboatSimple2Capability",
				overall_size_reasoning = "A speedboat is sleek and low-profile, roughly 1.4m wide, 1.0m tall, and 5m long.",
				overall_size_selection = { x = 1.4, y = 1.0, z = 5.0 },
			},
		},
	}
end

function MotorboatSimple2:getConfigureCapabilityExamples()
	return {
		{
			user = "a motorboat",
			assistant = {
				capability_parameters_reasoning = "A standard motorboat uses default thrust and steering values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast motorboat",
			assistant = {
				capability_parameters_reasoning = "A fast motorboat should have a higher top speed.",
				capability_parameters_selection = {
					maxForwardSpeed = 60,
					maxReverseSpeed = 30,
				},
			},
		},
	}
end

function MotorboatSimple2:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("MotorboatSimple2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["motorboat"]
	if not model then
		error("Could not find 'motorboat' model in generatedModels")
	end

	return MakeFunctional(model, parameters)
end

return MotorboatSimple2

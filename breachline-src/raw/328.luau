--[[
HelicopterSimple2 Capability - Rotor-driven aircraft (helicopter / drone) with arcade flight model

Composes: AirVehicle Architect (Rotor SubType)
Schema: HelicopterSimple2 (body, main rotor blade)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)

local function collectChildrenByName(root: Model, name: string): { PVInstance }
	local matches: { PVInstance } = {}
	for _, child in root:GetChildren() do
		if child.Name == name and (child:IsA("Model") or child:IsA("BasePart")) then
			table.insert(matches, child)
		end
	end

	return matches
end

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local body = root:FindFirstChild("body")
	if not body then error("Missing 'body' child in helicopter model") end

	local mainRotors = collectChildrenByName(root, "main rotor blade")
	if #mainRotors == 0 then error("Missing 'main rotor blade' child in helicopter model") end

	local schema = {
		Body = body,
		MainRotors = mainRotors,
	}

	local rotor = AirVehicleArchitect.buildRotor(root, {
		Schema = schema,
		Performance = {
			MaxSpeedLateral = config.maxSpeedLateral,
			MaxSpeedStrafe = config.maxSpeedStrafe,
			Acceleration = config.acceleration,
			MaxCollective = config.maxCollective,
			CollectiveRate = config.collectiveRate,
			YawRate = config.yawRate,
			CameraDistance = config.cameraDistance,
			CameraHeight = config.cameraHeight,
			BlurDiskOpacity = config.blurDiskOpacity,
		},
		ProximityPromptText = config.proximityPromptText,
	})

	return rotor.rotorModel
end

local HelicopterSimple2 = CapabilityBase.createChild()

function HelicopterSimple2:getCapabilityDocumentation()
	return [[
The HelicopterSimple2Capability creates a functional rotor-driven aircraft with an arcade flight model. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the helicopter and the same key to dismount. The craft hovers in place with no input, climbs / descends with Space / Left Control (Right Stick Up / Down on Gamepad), translates forward / back / left / right with WASD (Left Stick on Gamepad), and yaws with Mouse X (Right Stick X on Gamepad). Mobile uses the default thumbstick for forward + yaw (no strafe) plus Ascend / Descend / Exit context buttons. Holding right mouse button (or pressing Right Stick R3 on Gamepad to toggle) frees the camera to orbit around the craft; releasing returns the camera smoothly to the chase position. Visual pitch and roll respond to translation. Combined forward + strafe input caps total horizontal speed at the average of MaxSpeedLateral and MaxSpeedStrafe. Main rotor blades spin on top and decorate with semi-transparent blur disks at speed. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function HelicopterSimple2:getModelSpecs()
	return {
		{
			name = "helicopter",
			modelSchema = "HelicopterSimple2",
			description = "a rotor-driven helicopter with a body and one or more main rotor blades on top",
		},
	}
end

function HelicopterSimple2:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeedLateral", {
			type = "number",
			default = 150,
			description = "Maximum forward / backward speed in studs per second",
		})
		:addOptionalArgument("maxSpeedStrafe", {
			type = "number",
			default = 80,
			description = "Maximum left / right strafe speed in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 20,
			description = "How quickly current translation speed ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("maxCollective", {
			type = "number",
			default = 20,
			description = "Maximum altitude change rate in studs per second",
		})
		:addOptionalArgument("collectiveRate", {
			type = "number",
			default = 15,
			description = "How quickly altitude rate ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("yawRate", {
			type = "number",
			default = 40,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 25,
			description = "Distance behind the helicopter for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 6,
			description = "Vertical offset above the helicopter root for the chase camera, in studs",
		})
		:addOptionalArgument("blurDiskOpacity", {
			type = "number",
			default = 0.7,
			description = "Transparency of the rotor blur disks; 0 is opaque, 1 is invisible",
		})
		:addOptionalArgument("proximityPromptText", {
			type = "string",
			default = "Pilot",
			description = "Action text shown on the mount ProximityPrompt",
		})
		:build()
end

function HelicopterSimple2:getCapabilitySelectionExamples()
	return {
		{
			user = "a helicopter",
			assistant = {
				capability_reasoning = "The user wants a rotor-driven aircraft. HelicopterSimple2Capability creates a pilotable helicopter with a body and a top main rotor, plus an arcade hover-and-translate flight model.",
				capability_selection = "HelicopterSimple2Capability",
				overall_size_reasoning = "A small helicopter is roughly 6m wide, 4m tall, and 12m long.",
				overall_size_selection = { x = 6.0, y = 4.0, z = 12.0 },
			},
		},
		{
			user = "a quadcopter drone",
			assistant = {
				capability_reasoning = "A quadcopter is a rotor-driven aircraft. HelicopterSimple2Capability is the correct choice; the four main rotors are handled by model generation.",
				capability_selection = "HelicopterSimple2Capability",
				overall_size_reasoning = "A consumer quadcopter is roughly 0.5m wide, 0.2m tall, and 0.5m long.",
				overall_size_selection = { x = 0.5, y = 0.2, z = 0.5 },
			},
		},
	}
end

function HelicopterSimple2:getConfigureCapabilityExamples()
	return {
		{
			user = "a helicopter",
			assistant = {
				capability_parameters_reasoning = "A standard helicopter uses default speed and rate values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast attack helicopter",
			assistant = {
				capability_parameters_reasoning = "An attack helicopter should translate and yaw quickly; bump max speeds, yaw rate, and acceleration.",
				capability_parameters_selection = {
					maxSpeedLateral = 220,
					maxSpeedStrafe = 120,
					acceleration = 35,
					yawRate = 70,
				},
			},
		},
	}
end

function HelicopterSimple2:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("HelicopterSimple2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["helicopter"]
	if not model then
		error("Could not find 'helicopter' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return HelicopterSimple2
>
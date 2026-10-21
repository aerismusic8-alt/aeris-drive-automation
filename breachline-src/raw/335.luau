local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local body = root:FindFirstChild("body")
	if not body then error("Missing 'body' child in ufo model") end

	local schema = {
		Body = body,
	}

	local lights = root:FindFirstChild("lights")
	if lights then
		schema.Preserve = { lights }
	end

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
			MaxVisualPitchDegrees = 0,
			MaxVisualRollDegrees = 0,
		},
		ProximityPromptText = config.proximityPromptText,
		ProximityPromptTitle = "UFO",
	})

	return rotor.rotorModel
end

local Ufo2 = CapabilityBase.createChild()

function Ufo2:getCapabilityDocumentation(): string
	return [[
The Ufo2Capability creates a functional flying saucer with an arcade hover flight model. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the UFO and the same key to dismount. The craft hovers in place with no input, climbs / descends with Space / Left Control (Right Stick Up / Down on Gamepad), translates forward / back / left / right with WASD (Left Stick on Gamepad), and yaws with Mouse X (Right Stick X on Gamepad). Mobile uses the default thumbstick for forward + yaw plus Ascend / Descend / Exit context buttons. Holding right mouse button (or pressing Right Stick R3 on Gamepad to toggle) frees the camera to orbit around the craft; releasing returns the camera smoothly to the chase position. Visual pitch and roll respond to translation. The saucer strafes as fast as it flies forward, making it omnidirectional and highly maneuverable. The UFO has no spinning rotors; its lights are decorative and ride along with the body. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function Ufo2:getModelSpecs(): { { name: string, modelSchema: string, description: string } }
	return {
		{
			name = "ufo",
			modelSchema = "Ufo2",
			description = "a flying saucer with a rounded disc-shaped body and a ring or cluster of lights",
		},
	}
end

function Ufo2:getBindParametersDefinition(): { [string]: any }
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeedLateral", {
			type = "number",
			default = 100,
			description = "Maximum forward / backward speed in studs per second",
		})
		:addOptionalArgument("maxSpeedStrafe", {
			type = "number",
			default = 100,
			description = "Maximum left / right strafe speed in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 45,
			description = "How quickly current translation speed ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("maxCollective", {
			type = "number",
			default = 45,
			description = "Maximum altitude change rate in studs per second",
		})
		:addOptionalArgument("collectiveRate", {
			type = "number",
			default = 20,
			description = "How quickly altitude rate ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("yawRate", {
			type = "number",
			default = 45,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 30,
			description = "Distance behind the ufo for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 8,
			description = "Vertical offset above the ufo root for the chase camera, in studs",
		})
		:addOptionalArgument("proximityPromptText", {
			type = "string",
			default = "Pilot",
			description = "Action text shown on the mount ProximityPrompt",
		})
		:build()
end

function Ufo2:getCapabilitySelectionExamples(): { any }
	return {
		{
			user = "a UFO",
			assistant = {
				capability_reasoning = "The user wants a flying saucer. Ufo2Capability creates a pilotable UFO with a disc-shaped body and lights, plus an omnidirectional arcade hover-and-translate flight model.",
				capability_selection = "Ufo2Capability",
				overall_size_reasoning = "A small flying saucer is roughly 10m wide, 3m tall, and 10m long.",
				overall_size_selection = { x = 10.0, y = 3.0, z = 10.0 },
			},
		},
		{
			user = "a flying saucer alien spaceship",
			assistant = {
				capability_reasoning = "A flying saucer is a hovering aircraft. Ufo2Capability provides a pilotable saucer with a hover flight model and no rotors.",
				capability_selection = "Ufo2Capability",
				overall_size_reasoning = "An alien saucer is roughly 14m wide, 4m tall, and 14m long.",
				overall_size_selection = { x = 14.0, y = 4.0, z = 14.0 },
			},
		},
	}
end

function Ufo2:getConfigureCapabilityExamples(): { any }
	return {
		{
			user = "a UFO",
			assistant = {
				capability_parameters_reasoning = "A standard flying saucer uses default speed and rate values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast agile scout saucer",
			assistant = {
				capability_parameters_reasoning = "A scout saucer should translate, climb, and spin very quickly; bump max speeds, acceleration, collective, and yaw rate.",
				capability_parameters_selection = {
					maxSpeedLateral = 240,
					maxSpeedStrafe = 240,
					acceleration = 45,
					maxCollective = 45,
					collectiveRate = 35,
					yawRate = 160,
				},
			},
		},
	}
end

function Ufo2:bind(generatedModels: { [string]: Instance }, parameters: { [string]: any }): Instance?
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Ufo2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["ufo"]
	if not model then
		error("Could not find 'ufo' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return Ufo2

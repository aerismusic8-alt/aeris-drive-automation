 all treated as main rotors)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)

local PROPELLER_NAMES = {
	"left front propeller",
	"right front propeller",
	"left rear propeller",
	"right rear propeller",
}

local FRONT_PROPELLER_NAMES = {
	"left front propeller",
	"right front propeller",
}

local function collectByNames(root: Model, names: { string }): { PVInstance }
	local matches: { PVInstance } = {}
	for _, propellerName in names do
		for _, child in root:GetChildren() do
			if child.Name == propellerName and (child:IsA("Model") or child:IsA("BasePart")) then
				table.insert(matches, child)
			end
		end
	end

	return matches
end

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local body = root:FindFirstChild("body")
	if not body then error("Missing 'body' child in drone model") end

	local mainRotors = collectByNames(root, PROPELLER_NAMES)
	if #mainRotors == 0 then error("Missing propeller children in drone model") end

	local frontPropellers = collectByNames(root, FRONT_PROPELLER_NAMES)

	local schema = {
		Body = body,
		MainRotors = mainRotors,
		ForwardHint = if #frontPropellers > 0 then frontPropellers else nil,
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

local Drone5 = CapabilityBase.createChild()

function Drone5:getCapabilityDocumentation()
	return [[
The Drone5Capability creates a functional multi-rotor drone aircraft with an arcade flight model. The drone has four main rotors (one at each corner) and no tail rotor, making it more agile than a traditional helicopter. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the drone and the same key to dismount. The craft hovers in place with no input, climbs / descends with Space / Left Control (Right Stick Up / Down on Gamepad), translates forward / back / left / right with WASD (Left Stick on Gamepad), and yaws with Mouse X (Right Stick X on Gamepad). Mobile uses the default thumbstick for forward + yaw plus Ascend / Descend / Exit context buttons. Holding right mouse button (or pressing Right Stick R3 on Gamepad to toggle) frees the camera to orbit around the craft; releasing returns the camera smoothly to the chase position. Visual pitch and roll respond to translation. Combined forward + strafe input caps total horizontal speed at the average of MaxSpeedLateral and MaxSpeedStrafe. All four propellers spin and decorate with semi-transparent blur disks at speed. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function Drone5:getModelSpecs()
	return {
		{
			name = "drone",
			modelSchema = "Drone5",
			description = "a multi-rotor drone with a body and four propellers (left front, right front, left rear, right rear); no tail rotor",
		},
	}
end

function Drone5:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeedLateral", {
			type = "number",
			default = 200,
			description = "Maximum forward / backward speed in studs per second",
		})
		:addOptionalArgument("maxSpeedStrafe", {
			type = "number",
			default = 130,
			description = "Maximum left / right strafe speed in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 35,
			description = "How quickly current translation speed ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("maxCollective", {
			type = "number",
			default = 30,
			description = "Maximum altitude change rate in studs per second",
		})
		:addOptionalArgument("collectiveRate", {
			type = "number",
			default = 25,
			description = "How quickly altitude rate ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("yawRate", {
			type = "number",
			default = 80,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 25,
			description = "Distance behind the drone for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 6,
			description = "Vertical offset above the drone root for the chase camera, in studs",
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

function Drone5:getCapabilitySelectionExamples()
	return {
		{
			user = "a quadcopter drone",
			assistant = {
				capability_reasoning = "The user wants a multi-rotor aircraft with no tail rotor. Drone5Capability creates a pilotable drone with a body and four corner propellers, plus an agile arcade hover-and-translate flight model.",
				capability_selection = "Drone5Capability",
				overall_size_reasoning = "A consumer quadcopter drone is roughly 0.6m wide, 0.2m tall, and 0.6m long.",
				overall_size_selection = { x = 0.6, y = 0.2, z = 0.6 },
			},
		},
		{
			user = "a delivery drone",
			assistant = {
				capability_reasoning = "A delivery drone is a multi-rotor aircraft. Drone5Capability provides four-rotor flight with no tail rotor.",
				capability_selection = "Drone5Capability",
				overall_size_reasoning = "A package delivery drone is roughly 1m wide, 0.4m tall, and 1m long.",
				overall_size_selection = { x = 1.0, y = 0.4, z = 1.0 },
			},
		},
	}
end

function Drone5:getConfigureCapabilityExamples()
	return {
		{
			user = "a quadcopter drone",
			assistant = {
				capability_parameters_reasoning = "A standard drone uses default speed and rate values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast racing drone",
			assistant = {
				capability_parameters_reasoning = "A racing drone should translate, climb, and yaw very quickly; bump max speeds, acceleration, collective, and yaw rate.",
				capability_parameters_selection = {
					maxSpeedLateral = 320,
					maxSpeedStrafe = 220,
					acceleration = 60,
					maxCollective = 60,
					collectiveRate = 50,
					yawRate = 180,
				},
			},
		},
	}
end

function Drone5:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Drone5Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["drone"]
	if not model then
		error("Could not find 'drone' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return Drone5

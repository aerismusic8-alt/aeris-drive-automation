local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)

local SEAT_SCRIPT_NAME = "FlyingCarpetSeat"

local function computeForwardAxis(carpet: Instance): Vector3
	local carpetCFrame = GeometryUtils.getInstanceCFrame(carpet)
	local carpetSize = GeometryUtils.getInstanceSize(carpet)
	local localLongest = GeometryUtils.getLongestAxis(carpetSize)
	local worldLongest = carpetCFrame:VectorToWorldSpace(localLongest)
	local forward = if worldLongest.Z <= 0 then worldLongest else -worldLongest
	return forward.Unit
end

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local carpet = root:FindFirstChild("carpet")
	if not carpet then error("Missing 'carpet' child in flying carpet model") end

	local schema = {
		Body = carpet,
		ForwardAxis = computeForwardAxis(carpet),
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
			PitchFollow = true,
			PitchRate = config.pitchRate,
			MaxPitchFollowDegrees = config.maxPitchDegrees,
		},
		ProximityPromptText = config.proximityPromptText,
		ProximityPromptTitle = "Carpet",
		RiderVisible = true,
		RiderPlatformStand = false,
	})

	local seatScript = script.Parent:FindFirstChild(SEAT_SCRIPT_NAME)
	if seatScript then
		local clone = seatScript:Clone()
		if clone:IsA("BaseScript") then
			clone.Enabled = true
		end
		clone.Parent = rotor.rotorModel
	end

	return rotor.rotorModel
end

local FlyingCarpet1 = CapabilityBase.createChild()

function FlyingCarpet1:getCapabilityDocumentation(): string
	return [[
The FlyingCarpet1Capability creates a functional rideable flying carpet with an arcade free-flight hover model. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the carpet and the same key to dismount. Unlike a helicopter the rider stays visible, seated cross the carpet as it flies. The carpet hovers in place with no input and translates forward / back / left / right with WASD (Left Stick on Gamepad). Its nose follows the look input on BOTH axes: yaw with Mouse X and pitch with Mouse Y (Right Stick X / Y on Gamepad), so pointing the nose up climbs and pointing it down dives as you thrust forward, giving a jetpack-like feel. Space / Left Control (Gamepad ButtonA / ButtonB) still add pure vertical hover. Mobile uses the default thumbstick for forward + yaw plus Nose Up / Nose Down / Exit context buttons. Holding right mouse button (or pressing Right Stick R3 on Gamepad to toggle) frees the camera to orbit; releasing returns it smoothly to the chase position. The carpet strafes as fast as it flies forward, making it omnidirectional. The carpet has no rotors; it is a flat woven rug. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function FlyingCarpet1:getModelSpecs(): { { name: string, modelSchema: string, description: string } }
	return {
		{
			name = "flyingCarpet",
			modelSchema = "FlyingCarpet1",
			description = "a flat woven rug or carpet, much wider and longer than it is thick, with a decorative patterned top",
		},
	}
end

function FlyingCarpet1:getBindParametersDefinition(): { [string]: any }
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeedLateral", {
			type = "number",
			default = 90,
			description = "Maximum forward / backward speed in studs per second",
		})
		:addOptionalArgument("maxSpeedStrafe", {
			type = "number",
			default = 90,
			description = "Maximum left / right strafe speed in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 35,
			description = "How quickly current translation speed ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("maxCollective", {
			type = "number",
			default = 35,
			description = "Maximum altitude change rate in studs per second",
		})
		:addOptionalArgument("collectiveRate", {
			type = "number",
			default = 18,
			description = "How quickly altitude rate ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("yawRate", {
			type = "number",
			default = 45,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("pitchRate", {
			type = "number",
			default = 55,
			description = "Nose pitch rate at maximum look input, in degrees per second",
		})
		:addOptionalArgument("maxPitchDegrees", {
			type = "number",
			default = 65,
			description = "Maximum nose-up / nose-down angle the carpet can hold, in degrees",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 25,
			description = "Distance behind the carpet for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 7,
			description = "Vertical offset above the carpet root for the chase camera, in studs",
		})
		:addOptionalArgument("proximityPromptText", {
			type = "string",
			default = "Ride",
			description = "Action text shown on the mount ProximityPrompt",
		})
		:build()
end

function FlyingCarpet1:getCapabilitySelectionExamples(): { any }
	return {
		{
			user = "a flying carpet",
			assistant = {
				capability_reasoning = "The user wants a rideable flying carpet. FlyingCarpet1Capability creates a pilotable carpet with an arcade hover-and-translate flight model and a visible seated rider.",
				capability_selection = "FlyingCarpet1Capability",
				overall_size_reasoning = "A flying carpet is roughly 4m wide, 0.2m thick, and 6m long.",
				overall_size_selection = { x = 4.0, y = 0.2, z = 6.0 },
			},
		},
		{
			user = "a magic carpet like Aladdin",
			assistant = {
				capability_reasoning = "A magic carpet is a rideable hovering rug. FlyingCarpet1Capability provides a pilotable carpet with a hover flight model and no rotors.",
				capability_selection = "FlyingCarpet1Capability",
				overall_size_reasoning = "An ornate magic carpet is roughly 5m wide, 0.2m thick, and 7m long.",
				overall_size_selection = { x = 5.0, y = 0.2, z = 7.0 },
			},
		},
	}
end

function FlyingCarpet1:getConfigureCapabilityExamples(): { any }
	return {
		{
			user = "a flying carpet",
			assistant = {
				capability_parameters_reasoning = "A standard flying carpet uses default speed and rate values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast nimble magic carpet",
			assistant = {
				capability_parameters_reasoning = "A nimble carpet should translate, climb, and spin quickly; bump max speeds, acceleration, collective, and yaw rate.",
				capability_parameters_selection = {
					maxSpeedLateral = 160,
					maxSpeedStrafe = 160,
					acceleration = 45,
					maxCollective = 45,
					collectiveRate = 30,
					yawRate = 120,
				},
			},
		},
	}
end

function FlyingCarpet1:bind(generatedModels: { [string]: Instance }, parameters: { [string]: any }): Instance?
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("FlyingCarpet1Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["flyingCarpet"]
	if not model then
		error("Could not find 'flyingCarpet' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return FlyingCarpet1

--[[
Jetpack2 Capability - Player-worn rocket pack with arcade flight model

Composes: AirVehicle Architect (Jetpack SubType)
Schema: Jetpack2 (pack, thruster)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)

local FORWARD_EPSILON = 1e-3
local DEFAULT_FORWARD_AXIS = Vector3.new(0, 0, -1)

local function computeForwardAxis(pack: Instance): Vector3
	local packCFrame = GeometryUtils.getInstanceCFrame(pack)
	local packSize = GeometryUtils.getInstanceSize(pack)
	local localForward = if packSize.X <= packSize.Z then Vector3.xAxis else Vector3.zAxis
	local worldForward = packCFrame:VectorToWorldSpace(localForward)
	local flattened = Vector3.new(worldForward.X, 0, worldForward.Z)
	if flattened.Magnitude < FORWARD_EPSILON then
		return DEFAULT_FORWARD_AXIS
	end

	return (if flattened.Z <= 0 then flattened else -flattened).Unit
end

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local pack = root:FindFirstChild("pack")
	if not pack then error("Missing 'pack' child in jetpack model") end
	if not (pack:IsA("Model") or pack:IsA("BasePart")) then
		error("'pack' must be a Model or BasePart")
	end

	local thruster = root:FindFirstChild("thruster")
	if not thruster then error("Missing 'thruster' child in jetpack model") end
	if not (thruster:IsA("Model") or thruster:IsA("BasePart")) then
		error("'thruster' must be a Model or BasePart")
	end

	local jetpack = AirVehicleArchitect.buildJetpack(root, {
		Schema = {
			Pack = pack,
			Thruster = thruster,
			ForwardAxis = computeForwardAxis(pack),
		},
		Performance = {
			MaxSpeed = config.maxSpeed,
			Acceleration = config.acceleration,
			AltitudeChangeRate = config.altitudeChangeRate,
			LookRate = config.lookRate,
			CameraDistance = config.cameraDistance,
			CameraHeight = config.cameraHeight,
		},
		ProximityPromptText = config.proximityPromptText,
	})

	return jetpack.jetpackModel
end

local Jetpack2 = CapabilityBase.createChild()

function Jetpack2:getCapabilityDocumentation()
	return [[
The Jetpack2Capability creates a player-worn rocket pack with an arcade flight model. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) and the jetpack snaps onto the player's back, welded in place; the player remains visible. The pack hovers in place with no input, climbs / descends with Space / Left Control (ButtonA / ButtonB on Gamepad), translates forward / back / left / right in camera-local space with WASD (Left Stick on Gamepad). Yaw and pitch follow the camera look direction at LookRate degrees per second. Mobile uses the default thumbstick for camera-local forward + strafe plus Ascend / Descend / Exit context buttons. Holding right mouse button (or pressing Right Stick R3 on Gamepad to toggle) frees the camera to orbit around the player without re-orienting the pack. Pressing E (or ButtonX) while worn dismounts; the player stays in place. Forward / back movement tilts the pack forward, strafe rolls it; forward tilt tapers to zero when the player looks straight up or down. Each detected thruster gets a clone of the JetFlame_Purple VFX asset welded to its bottom-most BasePart. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function Jetpack2:getModelSpecs()
	return {
		{
			name = "jetpack",
			modelSchema = "Jetpack2",
			description = "a player-worn jetpack with a back pack and one or more thrusters/engines mounted below or to the sides of the pack",
		},
	}
end

function Jetpack2:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeed", {
			type = "number",
			default = 50,
			description = "Maximum lateral speed (forward / back / strafe) in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 15,
			description = "How quickly current lateral speed ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("altitudeChangeRate", {
			type = "number",
			default = 10,
			description = "Target altitude move rate while ascending / descending, in studs per second",
		})
		:addOptionalArgument("lookRate", {
			type = "number",
			default = 40,
			description = "Combined yaw + pitch slerp rate toward the camera look direction, in degrees per second",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 18,
			description = "Distance behind the player for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 4,
			description = "Vertical offset above the player root for the chase camera, in studs",
		})
		:addOptionalArgument("proximityPromptText", {
			type = "string",
			default = "Wear",
			description = "Action text shown on the mount ProximityPrompt",
		})
		:build()
end

function Jetpack2:getCapabilitySelectionExamples()
	return {
		{
			user = "a jetpack",
			assistant = {
				capability_reasoning = "The user wants a player-worn rocket pack. Jetpack2Capability creates a wearable jetpack with a back pack and one or more thrusters, plus an arcade hover-and-translate flight model.",
				capability_selection = "Jetpack2Capability",
				overall_size_reasoning = "A jetpack worn on a player's back is roughly 1.2m wide, 1.5m tall, and 0.8m deep.",
				overall_size_selection = { x = 1.2, y = 1.5, z = 0.8 },
			},
		},
		{
			user = "a rocket pack",
			assistant = {
				capability_reasoning = "A rocket pack is a player-worn jetpack. Jetpack2Capability is the correct choice.",
				capability_selection = "Jetpack2Capability",
				overall_size_reasoning = "A rocket pack is similar in size to a jetpack, roughly 1.2m wide, 1.5m tall, and 0.8m deep.",
				overall_size_selection = { x = 1.2, y = 1.5, z = 0.8 },
			},
		},
	}
end

function Jetpack2:getConfigureCapabilityExamples()
	return {
		{
			user = "a jetpack",
			assistant = {
				capability_parameters_reasoning = "A standard jetpack uses default speed and rate values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast military jetpack",
			assistant = {
				capability_parameters_reasoning = "A military jetpack should translate and climb quickly; bump max speed, acceleration, and altitude change rate.",
				capability_parameters_selection = {
					maxSpeed = 100,
					acceleration = 30,
					altitudeChangeRate = 20,
					lookRate = 60,
				},
			},
		},
	}
end

function Jetpack2:bind(generatedModels: { [string]: Instance }, parameters: { [string]: any }): Instance?
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Jetpack2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["jetpack"]
	if not model then
		error("Could not find 'jetpack' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return Jetpack2

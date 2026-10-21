--[[
Spacecraft3 Capability - Agile spacecraft flown like a jet aircraft

Composes: AirVehicle Architect (Plane SubType)
Schema: Spacecraft3 (body, left thruster, right thruster)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)

local THRUSTER_NAMES = {
	"left thruster",
	"right thruster",
}

local SPACECRAFT_MAX_BANK_DEGREES = 90

local function collectThrusters(root: Model): { PVInstance }
	local matches: { PVInstance } = {}
	for _, name in THRUSTER_NAMES do
		local thruster = root:FindFirstChild(name)
		if thruster and (thruster:IsA("Model") or thruster:IsA("BasePart")) then
			table.insert(matches, thruster)
		end
	end

	return matches
end

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local body = root:FindFirstChild("body")
	if not body then error("Missing 'body' child in spacecraft model") end

	local thrusters = collectThrusters(root)
	if #thrusters == 0 then error("Missing thruster children in spacecraft model") end

	local schema: { [string]: any } = {
		Body = body,
		Thrusters = thrusters,
	}

	local plane = AirVehicleArchitect.buildPlane(root, {
		Schema = schema,
		Performance = {
			MaxSpeed = config.maxSpeed,
			StallSpeed = config.stallSpeed,
			Acceleration = config.acceleration,
			PitchRate = config.pitchRate,
			TurnRate = config.turnRate,
			CameraDistance = config.cameraDistance,
			CameraHeight = config.cameraHeight,
			MaxBankDegrees = SPACECRAFT_MAX_BANK_DEGREES,
		},
		ProximityPromptText = config.proximityPromptText,
	})

	return plane.planeModel
end

local Spacecraft3 = CapabilityBase.createChild()

function Spacecraft3:getCapabilityDocumentation()
	return [[
The Spacecraft3Capability creates a functional, highly agile spacecraft that flies like a jet aircraft. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the craft and the same key to dismount. While flying, mouse / right-stick / mobile thumbstick controls pitch and rotation; W or ButtonA increases the target throttle while held, S or ButtonB decreases it. The craft flies straight in its facing direction with a very high top speed, fast turn and pitch rates, and aggressive banking. Lift fades only at very low speed (below StallSpeed). Pitch is clamped to plus or minus 85 degrees. The left and right thrusters are tracked for forward-axis detection and receive jet-flame thrust visuals. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function Spacecraft3:getModelSpecs()
	return {
		{
			name = "spacecraft",
			modelSchema = "Spacecraft3",
			description = "an agile spacecraft with a body and a left and right thruster",
		},
	}
end

function Spacecraft3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeed", {
			type = "number",
			default = 400,
			description = "Maximum target speed in studs per second",
		})
		:addOptionalArgument("stallSpeed", {
			type = "number",
			default = 15,
			description = "Speed below which lift begins to fade, in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 80,
			description = "How quickly current speed ramps toward effective target, in studs per second squared",
		})
		:addOptionalArgument("pitchRate", {
			type = "number",
			default = 50,
			description = "Pitch rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("turnRate", {
			type = "number",
			default = 90,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 30,
			description = "Distance behind the craft for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 8,
			description = "Vertical offset above the craft root for the chase camera, in studs",
		})
		:addOptionalArgument("proximityPromptText", {
			type = "string",
			default = "Pilot",
			description = "Action text shown on the mount ProximityPrompt",
		})
		:build()
end

function Spacecraft3:getCapabilitySelectionExamples()
	return {
		{
			user = "a spaceship",
			assistant = {
				capability_reasoning = "The user wants a pilotable spacecraft. Spacecraft3Capability creates an agile, jet-like spacecraft with a body and two thrusters.",
				capability_selection = "Spacecraft3Capability",
				overall_size_reasoning = "A small spacecraft is roughly 10m wide, 4m tall, and 14m long.",
				overall_size_selection = { x = 10.0, y = 4.0, z = 14.0 },
			},
		},
		{
			user = "a sci-fi starfighter",
			assistant = {
				capability_reasoning = "A starfighter is an agile single-pilot spacecraft. Spacecraft3Capability is the correct choice.",
				capability_selection = "Spacecraft3Capability",
				overall_size_reasoning = "A starfighter is roughly 9m wide, 3m tall, and 13m long.",
				overall_size_selection = { x = 9.0, y = 3.0, z = 13.0 },
			},
		},
	}
end

function Spacecraft3:getConfigureCapabilityExamples()
	return {
		{
			user = "a spaceship",
			assistant = {
				capability_parameters_reasoning = "A standard spacecraft uses the default agile flight values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast nimble interceptor",
			assistant = {
				capability_parameters_reasoning = "An interceptor pushes top speed and turn and pitch rates above the baseline.",
				capability_parameters_selection = {
					maxSpeed = 550,
					acceleration = 120,
					pitchRate = 90,
					turnRate = 130,
				},
			},
		},
	}
end

function Spacecraft3:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Spacecraft3Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["spacecraft"]
	if not model then
		error("Could not find 'spacecraft' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return Spacecraft3

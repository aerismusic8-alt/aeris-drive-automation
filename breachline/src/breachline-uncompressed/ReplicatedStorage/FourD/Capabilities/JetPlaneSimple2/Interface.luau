--[[
JetPlaneSimple2 Capability - Jet-powered winged aircraft with simple flight model

Composes: AirVehicle Architect (Plane SubType)
Schema: JetPlaneSimple2 (body, thruster)
Optional named children: left landing gear, right landing gear, center landing gear
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)

local OPTIONAL_CHILDREN = {
	"left landing gear",
	"right landing gear",
	"center landing gear",
}

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
	if not body then error("Missing 'body' child in jet plane model") end

	local thrusters = collectChildrenByName(root, "thruster")
	if #thrusters == 0 then error("Missing 'thruster' child in jet plane model") end

	local schema: { [string]: any } = {
		Body = body,
		Thrusters = thrusters,
	}

	for _, optionalName in OPTIONAL_CHILDREN do
		local match = root:FindFirstChild(optionalName)
		if not match then continue end
		if optionalName == "left landing gear" then
			schema.LeftLandingGear = match
		elseif optionalName == "right landing gear" then
			schema.RightLandingGear = match
		elseif optionalName == "center landing gear" then
			schema.CenterLandingGear = match
		end
	end

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
			MaxBankDegrees = 75,
		},
		ProximityPromptText = config.proximityPromptText,
	})

	return plane.planeModel
end

local JetPlaneSimple2 = CapabilityBase.createChild()

function JetPlaneSimple2:getCapabilityDocumentation()
	return [[
The JetPlaneSimple2Capability creates a functional jet-powered aircraft with a simple non-aerodynamic flight model. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the plane and the same key to dismount. While flying, mouse / right-stick / mobile thumbstick controls pitch and rotation; W or ButtonA increases the target throttle while held, S or ButtonB decreases it. The plane flies straight in its facing direction and lift fades as it drops below StallSpeed (full lift above StallSpeed; partial between StallSpeed * 0.5 and StallSpeed; zero below). Pitch is clamped to plus or minus 85 degrees. Diving boosts speed; climbing reduces it. Thrusters are tracked for forward-axis detection only; jet thrust visuals are not yet implemented. Landing gear, if present, is welded along with the body. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function JetPlaneSimple2:getModelSpecs()
	return {
		{
			name = "plane",
			modelSchema = "JetPlaneSimple2",
			description = "a jet-powered plane with a body and one or more thrusters; landing gear is not part of the schema but is honoured if present as optional named children",
		},
	}
end

function JetPlaneSimple2:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeed", {
			type = "number",
			default = 225,
			description = "Maximum target speed in studs per second",
		})
		:addOptionalArgument("stallSpeed", {
			type = "number",
			default = 40,
			description = "Speed below which lift begins to fade, in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 35,
			description = "How quickly current speed ramps toward effective target, in studs per second squared",
		})
		:addOptionalArgument("pitchRate", {
			type = "number",
			default = 25,
			description = "Pitch rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("turnRate", {
			type = "number",
			default = 50,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 25,
			description = "Distance behind the plane for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 6,
			description = "Vertical offset above the plane root for the chase camera, in studs",
		})
		:addOptionalArgument("proximityPromptText", {
			type = "string",
			default = "Pilot",
			description = "Action text shown on the mount ProximityPrompt",
		})
		:build()
end

function JetPlaneSimple2:getCapabilitySelectionExamples()
	return {
		{
			user = "a simple jet plane",
			assistant = {
				capability_reasoning = "The user wants a basic jet aircraft without armament. JetPlaneSimple2Capability creates a pilotable jet plane with a body and one or more thrusters.",
				capability_selection = "JetPlaneSimple2Capability",
				overall_size_reasoning = "A simple jet plane is roughly 9m wide (wingspan), 3m tall, and 12m long.",
				overall_size_selection = { x = 9.0, y = 3.0, z = 12.0 },
			},
		},
		{
			user = "a small civilian jet",
			assistant = {
				capability_reasoning = "A civilian jet is an unarmed jet aircraft. JetPlaneSimple2Capability is the correct choice.",
				capability_selection = "JetPlaneSimple2Capability",
				overall_size_reasoning = "A small civilian jet is roughly 10m wide, 3m tall, and 11m long.",
				overall_size_selection = { x = 10.0, y = 3.0, z = 11.0 },
			},
		},
	}
end

function JetPlaneSimple2:getConfigureCapabilityExamples()
	return {
		{
			user = "a simple jet plane",
			assistant = {
				capability_parameters_reasoning = "A standard jet plane uses default jet speed values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast supersonic trainer jet",
			assistant = {
				capability_parameters_reasoning = "A supersonic trainer needs higher top speed and faster turn rates over the baseline.",
				capability_parameters_selection = {
					maxSpeed = 220,
					acceleration = 60,
					pitchRate = 40,
					turnRate = 70,
				},
			},
		},
	}
end

function JetPlaneSimple2:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("JetPlaneSimple2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["plane"]
	if not model then
		error("Could not find 'plane' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return JetPlaneSimple2

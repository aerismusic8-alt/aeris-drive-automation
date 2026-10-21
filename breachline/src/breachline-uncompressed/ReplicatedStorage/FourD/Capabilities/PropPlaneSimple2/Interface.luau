--[[
PropPlaneSimple2 Capability - Propeller-driven winged aircraft with simple flight model

Composes: AirVehicle Architect (Plane SubType)
Schema: PropPlaneSimple2 (body, propeller)
Optional named children: left landing gear, right landing gear, center landing gear, thruster
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
	if not body then error("Missing 'body' child in plane model") end

	local propellers = collectChildrenByName(root, "propeller")
	if #propellers == 0 then error("Missing 'propeller' child in plane model") end

	local thrusters = collectChildrenByName(root, "thruster")

	local schema = {
		Body = body,
		Propellers = propellers,
	}

	if #thrusters > 0 then
		schema.Thrusters = thrusters
	end

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
			MaxBankDegrees = 50,
		},
		ProximityPromptText = config.proximityPromptText,
	})

	return plane.planeModel
end

local PropPlaneSimple2 = CapabilityBase.createChild()

function PropPlaneSimple2:getCapabilityDocumentation()
	return [[
The PropPlaneSimple2Capability creates a functional propeller-driven aircraft with a simple non-aerodynamic flight model. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the plane and the same key to dismount. While flying, mouse / right-stick / mobile thumbstick controls pitch and rotation; W or ButtonA increases the target throttle while held, S or ButtonB decreases it. The plane flies straight in its facing direction and lift fades as it drops below StallSpeed (full lift above StallSpeed; partial between StallSpeed * 0.5 and StallSpeed; zero below). Pitch is clamped to plus or minus 85 degrees. Diving boosts speed; climbing reduces it. The propeller spins visually proportional to current speed and is decorated with a semi-transparent blur disk. Landing gear, if present, is welded along with the body. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function PropPlaneSimple2:getModelSpecs()
	return {
		{
			name = "plane",
			modelSchema = "PropPlaneSimple2",
			description = "a propeller-driven plane with a body and a propeller; landing gear and thrusters are not part of the schema but are honoured if present as optional named children",
		},
	}
end

function PropPlaneSimple2:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeed", {
			type = "number",
			default = 120,
			description = "Maximum target speed in studs per second",
		})
		:addOptionalArgument("stallSpeed", {
			type = "number",
			default = 20,
			description = "Speed below which lift begins to fade, in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 25,
			description = "How quickly current speed ramps toward effective target, in studs per second squared",
		})
		:addOptionalArgument("pitchRate", {
			type = "number",
			default = 20,
			description = "Pitch rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("turnRate", {
			type = "number",
			default = 40,
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

function PropPlaneSimple2:getCapabilitySelectionExamples()
	return {
		{
			user = "a propeller plane",
			assistant = {
				capability_reasoning = "The user wants a propeller-driven aircraft. PropPlaneSimple2Capability creates a pilotable propeller aircraft with a body and a spinning propeller, plus a simple non-aerodynamic flight model.",
				capability_selection = "PropPlaneSimple2Capability",
				overall_size_reasoning = "A small propeller plane is roughly 10m wide (wingspan), 3m tall, and 8m long.",
				overall_size_selection = { x = 10.0, y = 3.0, z = 8.0 },
			},
		},
		{
			user = "a small biplane",
			assistant = {
				capability_reasoning = "A biplane is still a propeller-driven aircraft. PropPlaneSimple2Capability is the correct choice; the visual configuration is handled by model generation.",
				capability_selection = "PropPlaneSimple2Capability",
				overall_size_reasoning = "A compact biplane is roughly 8m wide, 3m tall, and 7m long.",
				overall_size_selection = { x = 8.0, y = 3.0, z = 7.0 },
			},
		},
	}
end

function PropPlaneSimple2:getConfigureCapabilityExamples()
	return {
		{
			user = "a propeller plane",
			assistant = {
				capability_parameters_reasoning = "A standard propeller plane uses default speed and turn values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast aerobatic plane",
			assistant = {
				capability_parameters_reasoning = "An aerobatic plane should turn and pitch quickly with a higher top speed; bump pitch and turn rates plus max speed.",
				capability_parameters_selection = {
					maxSpeed = 160,
					pitchRate = 45,
					turnRate = 75,
					acceleration = 50,
				},
			},
		},
	}
end

function PropPlaneSimple2:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("PropPlaneSimple2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["plane"]
	if not model then
		error("Could not find 'plane' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return PropPlaneSimple2

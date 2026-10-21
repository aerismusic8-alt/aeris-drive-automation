--[[
CombatSpacecraft4 Capability - Agile spacecraft flown like a jet, with a forward-fire cannon

Composes: AirVehicle Architect (Plane SubType) + Gunnable (newHardpoint, infinite ammo)
Schema: CombatSpacecraft4 (body, left thruster, right thruster, cannon)
]]

local Players = game:GetService("Players")

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)
local Gunnable = require(Behaviors.Gunnable)

local THRUSTER_NAMES = {
	"left thruster",
	"right thruster",
}

local SPACECRAFT_MAX_BANK_DEGREES = 60
local SPACECRAFT_TRACER_COLOR = Color3.fromRGB(255, 0, 0)
local SPACECRAFT_THRUSTER_COLOR = Color3.fromRGB(40, 120, 255)
local DEFAULT_GUN_DAMAGE = 30
local DEFAULT_GUN_FIRE_RATE = 600

local function fillInConfigDefaults(config: { [string]: any })
	config.gunDamage = config.gunDamage or DEFAULT_GUN_DAMAGE
	config.gunFireRate = config.gunFireRate or DEFAULT_GUN_FIRE_RATE
end

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

local function bindFirerToPilot(planeModel: Model, controllerHandle)
	local hullRoot = planeModel.PrimaryPart
	if not hullRoot then
		warn("[CombatSpacecraft4] planeModel has no PrimaryPart; cannot bind firer to pilot")
		return
	end

	local function syncFirer()
		local userId = hullRoot:GetAttribute("PilotUserId")
		if typeof(userId) ~= "number" or userId == 0 then
			controllerHandle:SetController(nil)
			return
		end
		controllerHandle:SetController(Players:GetPlayerByUserId(userId))
	end

	hullRoot:GetAttributeChangedSignal("PilotUserId"):Connect(syncFirer)
	syncFirer()
end

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}
	fillInConfigDefaults(config)

	local body = root:FindFirstChild("body")
	if not body then error("Missing 'body' child in spacecraft model") end

	local thrusters = collectThrusters(root)
	if #thrusters == 0 then error("Missing thruster children in spacecraft model") end

	local cannonModel = root:FindFirstChild("cannon")
	if not cannonModel or not (cannonModel:IsA("Model") or cannonModel:IsA("BasePart")) then
		error("Missing 'cannon' child in spacecraft model")
	end

	cannonModel.Parent = nil

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
		ThrusterColor = SPACECRAFT_THRUSTER_COLOR,
	})

	local planeModel = plane.planeModel

	local controllerHandle = Gunnable.newHardpoint(planeModel, cannonModel, {
		FireSequence = "Simultaneous",
		GunDamage = config.gunDamage,
		GunFireRate = config.gunFireRate,
		GunAmmo = -1,
		GunRange = config.gunRange,
		ProjectileSpeed = config.projectileSpeed,
		SpreadDegrees = 1,
		ConvergenceRange = (config.gunRange or 800) / 2,
		TracerColor = SPACECRAFT_TRACER_COLOR,
	})

	if controllerHandle then
		bindFirerToPilot(planeModel, controllerHandle)
	else
		warn("[CombatSpacecraft4] Gunnable.newHardpoint returned nil; cannon will not fire")
	end

	return planeModel
end

local CombatSpacecraft4 = CapabilityBase.createChild()

function CombatSpacecraft4:getCapabilityDocumentation()
	return [[
The CombatSpacecraft4Capability creates a functional, highly agile spacecraft that flies like a jet aircraft and carries a fixed forward-fire cannon with infinite ammo. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the craft and the same key to dismount. While flying, mouse / right-stick / mobile thumbstick controls pitch and rotation; W or ButtonA increases the target throttle while held, S or ButtonB decreases it. The craft flies straight in its facing direction with a very high top speed, fast turn and pitch rates, and aggressive banking. Lift fades only at very low speed (below StallSpeed). Pitch is clamped to plus or minus 85 degrees. The mounted pilot is automatically authorised to fire; LMB / R2 fires all cannon barrels simultaneously and ammunition never depletes. The left and right thrusters are tracked for forward-axis detection and receive jet-flame thrust visuals. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function CombatSpacecraft4:getModelSpecs()
	return {
		{
			name = "spacecraft",
			modelSchema = "CombatSpacecraft4",
			description = "an armed agile spacecraft with a body, a left and right thruster, and a cannon",
		},
	}
end

function CombatSpacecraft4:getBindParametersDefinition()
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
		:addOptionalArgument("gunDamage", {
			type = "number",
			default = DEFAULT_GUN_DAMAGE,
			description = "Damage applied per projectile hit",
		})
		:addOptionalArgument("gunFireRate", {
			type = "number",
			default = DEFAULT_GUN_FIRE_RATE,
			description = "Total rounds per minute across all barrels",
		})
		:addOptionalArgument("gunRange", {
			type = "number",
			description = "Maximum projectile range in studs (defaults handled by Gunnable)",
		})
		:addOptionalArgument("projectileSpeed", {
			type = "number",
			description = "Projectile travel speed in studs per second (defaults handled by Gunnable)",
		})
		:build()
end

function CombatSpacecraft4:getCapabilitySelectionExamples()
	return {
		{
			user = "an armed spaceship",
			assistant = {
				capability_reasoning = "The user wants a pilotable spacecraft with weapons. CombatSpacecraft4Capability creates an agile, jet-like spacecraft with a body, two thrusters, and a forward-fire cannon.",
				capability_selection = "CombatSpacecraft4Capability",
				overall_size_reasoning = "A small combat spacecraft is roughly 10m wide, 4m tall, and 14m long.",
				overall_size_selection = { x = 10.0, y = 4.0, z = 14.0 },
			},
		},
		{
			user = "a combat starfighter with guns",
			assistant = {
				capability_reasoning = "A combat starfighter is an agile single-pilot armed spacecraft. CombatSpacecraft4Capability is the correct choice.",
				capability_selection = "CombatSpacecraft4Capability",
				overall_size_reasoning = "A starfighter is roughly 9m wide, 3m tall, and 13m long.",
				overall_size_selection = { x = 9.0, y = 3.0, z = 13.0 },
			},
		},
	}
end

function CombatSpacecraft4:getConfigureCapabilityExamples()
	return {
		{
			user = "an armed spaceship",
			assistant = {
				capability_parameters_reasoning = "A standard combat spacecraft uses the default agile flight and cannon values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast gunship with rapid-fire cannons",
			assistant = {
				capability_parameters_reasoning = "A gunship pushes top speed above the baseline and fires its cannon much faster.",
				capability_parameters_selection = {
					maxSpeed = 550,
					acceleration = 120,
					turnRate = 130,
					gunFireRate = 900,
				},
			},
		},
	}
end

function CombatSpacecraft4:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("CombatSpacecraft4Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["spacecraft"]
	if not model then
		error("Could not find 'spacecraft' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return CombatSpacecraft4

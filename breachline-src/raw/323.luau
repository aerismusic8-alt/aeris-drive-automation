--[[
CombatPropPlaneSimple3 Capability - Propeller-driven winged aircraft with a forward-fire gun

Composes: AirVehicle Architect (Plane SubType) + Gunnable (newHardpoint, infinite ammo)
Schema: CombatPropPlaneSimple3 (body, propeller, gun)
Optional named children: left landing gear, right landing gear, center landing gear, thruster
]]

local Players = game:GetService("Players")

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)
local Gunnable = require(Behaviors.Gunnable)

local OPTIONAL_CHILDREN = {
	"left landing gear",
	"right landing gear",
	"center landing gear",
}

local DEFAULT_GUN_DAMAGE = 30
local DEFAULT_GUN_FIRE_RATE = 600

local function fillInConfigDefaults(config)
	config.gunDamage = config.gunDamage or DEFAULT_GUN_DAMAGE
	config.gunFireRate = config.gunFireRate or DEFAULT_GUN_FIRE_RATE
end

local function collectChildrenByName(root: Model, name: string): { PVInstance }
	local matches: { PVInstance } = {}
	for _, child in root:GetChildren() do
		if child.Name == name and (child:IsA("Model") or child:IsA("BasePart")) then
			table.insert(matches, child)
		end
	end

	return matches
end

local function bindFirerToPilot(planeModel: Model, controllerHandle)
	local hullRoot = planeModel.PrimaryPart
	if not hullRoot then
		warn("[CombatPropPlaneSimple3] planeModel has no PrimaryPart; cannot bind firer to pilot")
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
	if not body then error("Missing 'body' child in plane model") end

	local propellers = collectChildrenByName(root, "propeller")
	if #propellers == 0 then error("Missing 'propeller' child in plane model") end

	local gunModel = root:FindFirstChild("gun")
	if not gunModel or not (gunModel:IsA("Model") or gunModel:IsA("BasePart")) then
		error("Missing 'gun' child in plane model")
	end

	local thrusters = collectChildrenByName(root, "thruster")

	gunModel.Parent = nil

	local schema: { [string]: any } = {
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
			MaxBankDegrees = 55,
		},
	})

	local planeModel = plane.planeModel

	local controllerHandle = Gunnable.newHardpoint(planeModel, gunModel, {
		FireSequence = "Cycled",
		GunDamage = config.gunDamage,
		GunFireRate = config.gunFireRate,
		GunAmmo = -1,
		GunRange = config.gunRange,
		ProjectileSpeed = config.projectileSpeed,
		ProjectileGravity = 0.2,
		SpreadDegrees = 1,
		ConvergenceRange = (config.gunRange or 800) / 2,
	})

	if controllerHandle then
		bindFirerToPilot(planeModel, controllerHandle)
	else
		warn("[CombatPropPlaneSimple3] Gunnable.newHardpoint returned nil; gun will not fire")
	end

	return planeModel
end

local CombatPropPlaneSimple3 = CapabilityBase.createChild()

function CombatPropPlaneSimple3:getCapabilityDocumentation()
	return [[
The CombatPropPlaneSimple3Capability creates a functional propeller-driven aircraft with a fixed forward-fire gun and infinite ammo. Mount with E (PC) or ButtonX (Gamepad). Mouse / right thumbstick controls pitch and rotation; W or ButtonA increases throttle while held, S or ButtonB decreases it. The plane flies straight in its facing direction; lift fades below StallSpeed. Pitch is clamped to plus or minus 85 degrees. Diving boosts speed; climbing reduces it. The propeller spins visually proportional to current speed and is decorated with a semi-transparent blur disk. The mounted pilot is automatically authorised to fire; LMB / R2 fires all gun barrels simultaneously. Ammunition never depletes and there is no reload. Landing gear, if present, is welded along with the body. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function CombatPropPlaneSimple3:getModelSpecs()
	return {
		{
			name = "plane",
			modelSchema = "CombatPropPlaneSimple3",
			description = "a propeller-driven combat plane with a body, a propeller, and a forward-fire gun; landing gear and thrusters are not part of the schema but are honoured if present as optional named children",
		},
	}
end

function CombatPropPlaneSimple3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeed", {
			type = "number",
			default = 150,
			description = "Maximum target speed in studs per second",
		})
		:addOptionalArgument("stallSpeed", {
			type = "number",
			default = 25,
			description = "Speed below which lift begins to fade, in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 35,
			description = "How quickly current speed ramps toward effective target, in studs per second squared",
		})
		:addOptionalArgument("pitchRate", {
			type = "number",
			default = 30,
			description = "Pitch rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("turnRate", {
			type = "number",
			default = 50,
			description = "Heading rotation rate at maximum input, in degrees per second",
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

function CombatPropPlaneSimple3:getCapabilitySelectionExamples()
	return {
		{
			user = "a propeller plane with a gun",
			assistant = {
				capability_reasoning = "The user wants an armed propeller-driven aircraft. CombatPropPlaneSimple3Capability creates a pilotable propeller aircraft with a body, a spinning propeller, and a forward-fire gun with infinite ammo.",
				capability_selection = "CombatPropPlaneSimple3Capability",
				overall_size_reasoning = "A small armed propeller plane is roughly 10m wide (wingspan), 3m tall, and 8m long.",
				overall_size_selection = { x = 10.0, y = 3.0, z = 8.0 },
			},
		},
		{
			user = "a fighter biplane",
			assistant = {
				capability_reasoning = "A fighter biplane is a propeller-driven aircraft with mounted guns. CombatPropPlaneSimple3Capability is the correct choice; the biplane visual is handled by model generation.",
				capability_selection = "CombatPropPlaneSimple3Capability",
				overall_size_reasoning = "A compact fighter biplane is roughly 8m wide, 3m tall, and 7m long.",
				overall_size_selection = { x = 8.0, y = 3.0, z = 7.0 },
			},
		},
	}
end

function CombatPropPlaneSimple3:getConfigureCapabilityExamples()
	return {
		{
			user = "a propeller plane with a gun",
			assistant = {
				capability_parameters_reasoning = "A standard armed propeller plane uses default speed and gun values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast fighter plane with a hard-hitting cannon",
			assistant = {
				capability_parameters_reasoning = "A fighter should turn and pitch quickly with a higher top speed and a slower-firing high-damage cannon.",
				capability_parameters_selection = {
					maxSpeed = 160,
					pitchRate = 45,
					turnRate = 75,
					acceleration = 50,
					gunDamage = 60,
					gunFireRate = 240,
					projectileSpeed = 350,
				},
			},
		},
	}
end

function CombatPropPlaneSimple3:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("CombatPropPlaneSimple3Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["plane"]
	if not model then
		error("Could not find 'plane' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return CombatPropPlaneSimple3

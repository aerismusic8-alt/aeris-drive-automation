--[[
CombatJetPlane3 Capability - Jet aircraft with a forward-fire gun

Composes: AirVehicle Architect (Plane SubType) + Gunnable (newHardpoint, infinite ammo)
Schema: CombatJetPlane3 (body, thruster, center/right/left landing gear, gun)
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
		warn("[CombatJetPlane3] planeModel has no PrimaryPart; cannot bind firer to pilot")
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
	if not body then error("Missing 'body' child in jet plane model") end

	local thrusters = collectChildrenByName(root, "thruster")
	if #thrusters == 0 then error("Missing 'thruster' child in jet plane model") end

	local gunModel = root:FindFirstChild("gun")
	if not gunModel or not (gunModel:IsA("Model") or gunModel:IsA("BasePart")) then
		error("Missing 'gun' child in jet plane model")
	end

	gunModel.Parent = nil

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
			MaxBankDegrees = 85,
		},
	})

	local planeModel = plane.planeModel

	local controllerHandle = Gunnable.newHardpoint(planeModel, gunModel, {
		FireSequence = "Simultaneous",
		GunDamage = config.gunDamage,
		GunFireRate = config.gunFireRate,
		GunAmmo = -1,
		GunRange = config.gunRange,
		ProjectileSpeed = config.projectileSpeed,
		SpreadDegrees = 1,
		ConvergenceRange = (config.gunRange or 800) / 2,
	})

	if controllerHandle then
		bindFirerToPilot(planeModel, controllerHandle)
	else
		warn("[CombatJetPlane3] Gunnable.newHardpoint returned nil; gun will not fire")
	end

	return planeModel
end

local CombatJetPlane3 = CapabilityBase.createChild()

function CombatJetPlane3:getCapabilityDocumentation()
	return [[
The CombatJetPlane3Capability creates a functional jet aircraft with a fixed forward-fire gun and infinite ammo. Mount with E (PC) or ButtonX (Gamepad). Mouse / right thumbstick controls pitch and rotation; W or ButtonA increases throttle while held, S or ButtonB decreases it. The plane flies straight in its facing direction; lift fades below StallSpeed. Pitch is clamped to plus or minus 85 degrees. The mounted pilot is automatically authorised to fire; LMB / R2 fires all gun barrels simultaneously. Ammunition never depletes and there is no reload. Landing gear is welded along with the body. Thrusters are tracked for forward-axis detection only; jet thrust visuals are not yet implemented. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function CombatJetPlane3:getModelSpecs()
	return {
		{
			name = "plane",
			modelSchema = "CombatJetPlane3",
			description = "a jet-powered combat plane with a body, one or more thrusters, three landing gear pieces, and a forward-fire gun",
		},
	}
end

function CombatJetPlane3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeed", {
			type = "number",
			default = 240,
			description = "Maximum target speed in studs per second",
		})
		:addOptionalArgument("stallSpeed", {
			type = "number",
			default = 40,
			description = "Speed below which lift begins to fade, in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 50,
			description = "How quickly current speed ramps toward effective target, in studs per second squared",
		})
		:addOptionalArgument("pitchRate", {
			type = "number",
			default = 40,
			description = "Pitch rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("turnRate", {
			type = "number",
			default = 55,
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

function CombatJetPlane3:getCapabilitySelectionExamples()
	return {
		{
			user = "a fighter jet",
			assistant = {
				capability_reasoning = "The user wants an armed jet aircraft. CombatJetPlane3Capability creates a pilotable jet aircraft with a body, thruster, landing gear, and a forward-fire gun with infinite ammo.",
				capability_selection = "CombatJetPlane3Capability",
				overall_size_reasoning = "A standard fighter jet is roughly 10m wide (wingspan), 3m tall, and 14m long.",
				overall_size_selection = { x = 10.0, y = 3.0, z = 14.0 },
			},
		},
		{
			user = "an interceptor plane",
			assistant = {
				capability_reasoning = "An interceptor is a fast jet-powered combat aircraft. CombatJetPlane3Capability covers the role; tune speeds via parameters.",
				capability_selection = "CombatJetPlane3Capability",
				overall_size_reasoning = "An interceptor is roughly 9m wide, 3m tall, and 13m long.",
				overall_size_selection = { x = 9.0, y = 3.0, z = 13.0 },
			},
		},
	}
end

function CombatJetPlane3:getConfigureCapabilityExamples()
	return {
		{
			user = "a fighter jet",
			assistant = {
				capability_parameters_reasoning = "A standard fighter jet uses default jet speed and gun values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a high-speed interceptor with rapid-fire cannons",
			assistant = {
				capability_parameters_reasoning = "An interceptor needs much higher top speed plus a faster gun fire rate.",
				capability_parameters_selection = {
					maxSpeed = 220,
					acceleration = 60,
					pitchRate = 40,
					turnRate = 70,
					gunFireRate = 900,
					projectileSpeed = 400,
				},
			},
		},
	}
end

function CombatJetPlane3:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("CombatJetPlane3Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["plane"]
	if not model then
		error("Could not find 'plane' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return CombatJetPlane3

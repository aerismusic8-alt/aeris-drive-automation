--[[
CombatHelicopterSimple3 Capability - Rotor-driven aircraft (helicopter / drone) with a forward-fire gun

Composes: AirVehicle Architect (Rotor SubType) + Gunnable (newHardpoint, infinite ammo)
Schema: CombatHelicopterSimple3 (body, main rotor blade, gun)
Pilot-only shooting (no gunner seat).
]]

local Players = game:GetService("Players")

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)
local Gunnable = require(Behaviors.Gunnable)

local DEFAULT_GUN_DAMAGE = 30
local DEFAULT_GUN_FIRE_RATE = 600

local function fillInConfigDefaults(config: { [string]: any })
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

local function bindFirerToPilot(rotorModel: Model, controllerHandle)
	local hullRoot = rotorModel.PrimaryPart
	if not hullRoot then
		warn("[CombatHelicopterSimple3] rotorModel has no PrimaryPart; cannot bind firer to pilot")
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
	if not body then error("Missing 'body' child in helicopter model") end

	local mainRotors = collectChildrenByName(root, "main rotor blade")
	if #mainRotors == 0 then error("Missing 'main rotor blade' child in helicopter model") end

	local gunModel = root:FindFirstChild("gun")
	if not gunModel or not (gunModel:IsA("Model") or gunModel:IsA("BasePart")) then
		error("Missing 'gun' child in helicopter model")
	end

	gunModel.Parent = nil

	local schema: { [string]: any } = {
		Body = body,
		MainRotors = mainRotors,
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

	local rotorModel = rotor.rotorModel

	local controllerHandle = Gunnable.newHardpoint(rotorModel, gunModel, {
		FireSequence = "Cycled",
		GunDamage = config.gunDamage,
		GunFireRate = config.gunFireRate,
		GunAmmo = -1,
		GunRange = config.gunRange,
		ProjectileSpeed = config.projectileSpeed,
		ConvergenceRange = (config.gunRange or 800) / 2,
	})

	if controllerHandle then
		bindFirerToPilot(rotorModel, controllerHandle)
	else
		warn("[CombatHelicopterSimple3] Gunnable.newHardpoint returned nil; gun will not fire")
	end

	return rotorModel
end

local CombatHelicopterSimple3 = CapabilityBase.createChild()

function CombatHelicopterSimple3:getCapabilityDocumentation()
	return [[
The CombatHelicopterSimple3Capability creates a functional rotor-driven aircraft with an arcade flight model and a fixed forward-fire gun with infinite ammo. The player triggers a ProximityPrompt (E on PC, ButtonX on Gamepad) to mount the helicopter and the same key to dismount. The craft hovers in place with no input, climbs / descends with Space / Left Control (Right Stick Up / Down on Gamepad), translates forward / back / left / right with WASD (Left Stick on Gamepad), and yaws with Mouse X (Right Stick X on Gamepad). Mobile uses the default thumbstick for forward + yaw (no strafe) plus Ascend / Descend / Exit context buttons. Holding right mouse button (or pressing Right Stick R3 on Gamepad to toggle) frees the camera to orbit around the craft; releasing returns the camera smoothly to the chase position. The mounted pilot is automatically authorised to fire; LMB / R2 fires gun barrels in a round-robin gatling cycle. Ammunition never depletes and there is no reload. There is no gunner seat. Main rotor blades spin on top and decorate with semi-transparent blur disks at speed. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function CombatHelicopterSimple3:getModelSpecs()
	return {
		{
			name = "helicopter",
			modelSchema = "CombatHelicopterSimple3",
			description = "a rotor-driven combat helicopter with a body, one or more main rotor blades on top, and a forward-fire gun",
		},
	}
end

function CombatHelicopterSimple3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeedLateral", {
			type = "number",
			default = 150,
			description = "Maximum forward / backward speed in studs per second",
		})
		:addOptionalArgument("maxSpeedStrafe", {
			type = "number",
			default = 80,
			description = "Maximum left / right strafe speed in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 20,
			description = "How quickly current translation speed ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("maxCollective", {
			type = "number",
			default = 20,
			description = "Maximum altitude change rate in studs per second",
		})
		:addOptionalArgument("collectiveRate", {
			type = "number",
			default = 15,
			description = "How quickly altitude rate ramps toward target, in studs per second squared",
		})
		:addOptionalArgument("yawRate", {
			type = "number",
			default = 40,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("cameraDistance", {
			type = "number",
			default = 25,
			description = "Distance behind the helicopter for the chase camera, in studs",
		})
		:addOptionalArgument("cameraHeight", {
			type = "number",
			default = 6,
			description = "Vertical offset above the helicopter root for the chase camera, in studs",
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

function CombatHelicopterSimple3:getCapabilitySelectionExamples()
	return {
		{
			user = "an attack helicopter",
			assistant = {
				capability_reasoning = "The user wants an armed rotor-driven aircraft. CombatHelicopterSimple3Capability creates a pilotable helicopter with a body, a top main rotor, and a forward-fire gun with infinite ammo.",
				capability_selection = "CombatHelicopterSimple3Capability",
				overall_size_reasoning = "An attack helicopter is roughly 6m wide, 4m tall, and 14m long.",
				overall_size_selection = { x = 6.0, y = 4.0, z = 14.0 },
			},
		},
		{
			user = "a combat drone with a gun",
			assistant = {
				capability_reasoning = "An armed quadcopter-style drone is a rotor-driven aircraft with a fixed gun. CombatHelicopterSimple3Capability covers the role; multiple main rotors are handled by model generation.",
				capability_selection = "CombatHelicopterSimple3Capability",
				overall_size_reasoning = "A combat drone is roughly 1.5m wide, 0.5m tall, and 1.5m long.",
				overall_size_selection = { x = 1.5, y = 0.5, z = 1.5 },
			},
		},
	}
end

function CombatHelicopterSimple3:getConfigureCapabilityExamples()
	return {
		{
			user = "an attack helicopter",
			assistant = {
				capability_parameters_reasoning = "A standard attack helicopter uses default speed and gun values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast gunship with rapid-fire cannons",
			assistant = {
				capability_parameters_reasoning = "A gunship should translate and yaw quickly with a hard-hitting rapid-fire gun.",
				capability_parameters_selection = {
					maxSpeedLateral = 220,
					maxSpeedStrafe = 120,
					acceleration = 35,
					yawRate = 70,
					gunDamage = 45,
					gunFireRate = 900,
					projectileSpeed = 350,
				},
			},
		},
	}
end

function CombatHelicopterSimple3:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("CombatHelicopterSimple3Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["helicopter"]
	if not model then
		error("Could not find 'helicopter' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return CombatHelicopterSimple3

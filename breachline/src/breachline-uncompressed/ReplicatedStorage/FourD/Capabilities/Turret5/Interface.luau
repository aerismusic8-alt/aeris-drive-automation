--[[
Turret5 Capability - Fixed-mount, single-player-controllable turret

Composes: Gunnable (newTurret, DriverSeat-only "solo" mode)
Schema: Turret5 (tripod base + swivel mount + gun body + barrel + shield plate)

The base is anchored and immovable. The operator sits in a seat, aims the gun
by looking around (camera screen-center), and fires with left-click.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Gunnable = require(Behaviors.Gunnable)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

local DEFAULT_GUN_DAMAGE = 35
local DEFAULT_GUN_FIRE_RATE = 700
local DEFAULT_GUN_AMMO = 150
local DEFAULT_GUN_RELOAD_TIME = 3
local DEFAULT_GUN_RANGE = 600
local DEFAULT_PROJECTILE_SPEED = 400
local DEFAULT_SPREAD_DEGREES = 0.75
local DEFAULT_PITCH_UP = 60
local DEFAULT_PITCH_DOWN = 20

local function anchorAll(instance: Instance): ()
	for _, part in ipairs(GeometryUtils.getInstanceParts(instance)) do
		part.Anchored = true
	end
end

local function unanchorAll(instance: Instance): ()
	for _, part in ipairs(GeometryUtils.getInstanceParts(instance)) do
		part.Anchored = false
	end
end

local function attachScripts(turretModel: Model)
	for _, scriptName in ipairs({ "MountPrompt", "TurretExit", "SwivelDrive" }) do
		local template = script.Parent:FindFirstChild(scriptName)
		if template then
			local clone = template:Clone()
			if clone:IsA("BaseScript") then
				clone.Enabled = true
			end
			clone.Parent = turretModel
		end
	end
end

local function makeFunctional(
	turretModel: Model,
	tripodBase: Instance,
	swivelMount: Instance,
	gunBody: Instance,
	barrel: Instance,
	shieldPlate: Instance,
	config: { [string]: any }
): Model
	local chassis = GeometryUtils.getOrSetPrimaryPart(tripodBase)
	if not chassis then
		error("Turret5Capability: 'tripod base' contains no BasePart")
	end

	chassis.Name = "Chassis"
	turretModel.PrimaryPart = chassis

	local forward = chassis.CFrame.LookVector

	anchorAll(tripodBase)
	for _, part in ipairs(GeometryUtils.getInstanceParts(tripodBase)) do
		if part ~= chassis then
			ConstructionHelpers.makeWeld(chassis, part)
		end
	end

	local swivelCenter = GeometryUtils.getInstanceCFrame(swivelMount).Position
	local swivelPivotCFrame = CFrame.lookAt(swivelCenter, swivelCenter + forward)

	local swivelMountPart = Instance.new("Part")
	swivelMountPart.Name = "SwivelMount"
	swivelMountPart.Size = Vector3.new(0.5, 0.5, 0.5)
	swivelMountPart.Transparency = 1
	swivelMountPart.CanCollide = false
	swivelMountPart.Massless = true
	swivelMountPart.Anchored = false
	swivelMountPart.CFrame = swivelPivotCFrame
	swivelMountPart.Parent = turretModel

	local swivelBaseC0 = chassis.CFrame:Inverse() * swivelPivotCFrame

	local swivelMotor = Instance.new("Motor6D")
	swivelMotor.Name = "SwivelMotor"
	swivelMotor.Part0 = chassis
	swivelMotor.Part1 = swivelMountPart
	swivelMotor.C0 = swivelBaseC0
	swivelMotor.Parent = chassis

	local swivelBaseC0Value = Instance.new("CFrameValue")
	swivelBaseC0Value.Name = "SwivelBaseC0"
	swivelBaseC0Value.Value = swivelBaseC0
	swivelBaseC0Value.Parent = turretModel

	for _, part in ipairs(GeometryUtils.getInstanceParts(swivelMount)) do
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true

		local weld = Instance.new("Weld")
		weld.Part0 = swivelMountPart
		weld.Part1 = part
		weld.C0 = swivelMountPart.CFrame:Inverse() * part.CFrame
		weld.Parent = swivelMountPart
	end

	local gunModel = Instance.new("Model")
	gunModel.Name = "gun"
	gunBody.Parent = gunModel
	barrel.Parent = gunModel
	shieldPlate.Parent = gunModel
	unanchorAll(gunModel)
	gunModel.PrimaryPart = GeometryUtils.getOrSetPrimaryPart(gunBody)
	gunModel.Parent = turretModel

	local gunCFrame, gunSize = gunModel:GetBoundingBox()
	local pivotCFrame = CFrame.lookAt(gunCFrame.Position, gunCFrame.Position + forward)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.Anchored = false
	seat.CFrame = pivotCFrame * CFrame.new(0, -gunSize.Y * 0.5, gunSize.Z * 0.8 + 1)
	seat.Parent = turretModel
	ConstructionHelpers.makeWeld(chassis, seat)

	local mountPrompt = Instance.new("ProximityPrompt")
	mountPrompt.Name = "MountPrompt"
	mountPrompt.ActionText = "Operate Turret"
	mountPrompt.ObjectText = "Turret"
	mountPrompt.HoldDuration = 0
	mountPrompt.RequiresLineOfSight = false
	mountPrompt.MaxActivationDistance = math.max(chassis.Size.X, chassis.Size.Z) * 1.5 + 6
	mountPrompt.Parent = seat

	local turretHandle = Gunnable.newTurret(turretModel, gunModel, {
		DriverSeat = seat,
		GunnerPitchUp = config.pitchUp,
		GunnerPitchDown = config.pitchDown,
		FirstPerson = true,
	})

	if turretHandle then
		local muzzle = Gunnable.detectMuzzle(turretModel, gunModel)
		local hardpointHandle = if muzzle
			then Gunnable.newHardpoint(turretModel, { muzzle }, {
				GunDamage = config.gunDamage,
				GunFireRate = config.gunFireRate,
				GunAmmo = config.gunAmmo,
				GunReloadTime = config.gunReloadTime,
				GunRange = config.gunRange,
				ProjectileSpeed = config.projectileSpeed,
				ProjectileName = config.projectileName,
				SpreadDegrees = config.spreadDegrees,
				ReticleLerp = true,
			})
			else nil

		if hardpointHandle then
			turretHandle:BindWeapon(hardpointHandle)
		else
			warn("[Turret5] Could not rig turret hardpoint; gun will not fire")
		end
	end

	attachScripts(turretModel)

	return turretModel
end

local Turret5 = CapabilityBase.createChild()

function Turret5:getCapabilityDocumentation()
	return [[
The Turret5Capability creates a fixed, immovable single-operator turret.
The turret is bolted in place and cannot be driven or moved. One player sits at
the turret, aims the gun by looking around (the gun follows the camera), and
fires by left-clicking.
Use this for any stationary mounted weapon: defensive emplacements, anti-air
guns, sentry guns, mounted machine guns on a tripod, watchtower guns, etc.
Anything that is a single weapon fixed to the ground and operated by one player
should use Turret5Capability.
]]
end

function Turret5:getModelSpecs()
	return {
		{
			name = "turret",
			modelSchema = "Turret5",
			description = "a fixed-mount turret with a tripod base, swivel mount, gun body, barrel, and shield plate",
		},
	}
end

function Turret5:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("gunDamage", {
			type = "number",
			default = DEFAULT_GUN_DAMAGE,
			minimum = 1,
			description = "Damage per projectile hit",
		})
		:addOptionalArgument("gunFireRate", {
			type = "number",
			default = DEFAULT_GUN_FIRE_RATE,
			minimum = 30,
			maximum = 1200,
			description = "Rate of fire in rounds per minute (RPM). 600 RPM = 10 shots/second",
		})
		:addOptionalArgument("gunAmmo", {
			type = "number",
			default = DEFAULT_GUN_AMMO,
			description = "Magazine size before a reload is needed. Use -1 for infinite ammo (no reload)",
		})
		:addOptionalArgument("gunReloadTime", {
			type = "number",
			default = DEFAULT_GUN_RELOAD_TIME,
			minimum = 0.5,
			description = "Time in seconds to reload the gun",
		})
		:addOptionalArgument("gunRange", {
			type = "number",
			default = DEFAULT_GUN_RANGE,
			minimum = 50,
			description = "Maximum effective range of the gun in studs",
		})
		:addOptionalArgument("projectileSpeed", {
			type = "number",
			default = DEFAULT_PROJECTILE_SPEED,
			minimum = 50,
			description = "Speed of the projectile in studs per second",
		})
		:addOptionalArgument("projectileName", {
			type = "string",
			default = "",
			description = "Name of a projectile template in ReplicatedStorage.FourD.Projectiles. Empty means no custom projectile model (beam tracer + trail only).",
		})
		:addOptionalArgument("spreadDegrees", {
			type = "number",
			default = DEFAULT_SPREAD_DEGREES,
			minimum = 0,
			maximum = 45,
			description = "Cone half-angle of shot spread in degrees. 0 is pinpoint accurate.",
		})
		:addOptionalArgument("pitchUp", {
			type = "number",
			default = DEFAULT_PITCH_UP,
			minimum = 0,
			maximum = 89,
			description = "Maximum upward aim angle in degrees",
		})
		:addOptionalArgument("pitchDown", {
			type = "number",
			default = DEFAULT_PITCH_DOWN,
			minimum = 0,
			maximum = 89,
			description = "Maximum downward aim angle in degrees",
		})
		:build()
end

function Turret5:getCapabilitySelectionExamples()
	return {
		{
			user = "a mounted machine gun on a tripod",
			assistant = {
				capability_reasoning = 'The user wants a "mounted machine gun on a tripod" which is a stationary weapon operated by a single player. This maps to Turret5Capability, which creates a fixed, immovable turret a player sits at and aims by looking around.',
				capability_selection = "Turret5Capability",
				overall_size_reasoning = "A tripod-mounted machine gun is compact, roughly 2 meters wide, 1.8 meters tall, and 2 meters deep including the barrel and tripod legs.",
				overall_size_selection = { x = 2, y = 1.8, z = 2 },
			},
		},
		{
			user = "a stationary anti-air gun emplacement",
			assistant = {
				capability_reasoning = 'The user wants a "stationary anti-air gun emplacement" - a fixed defensive weapon controlled by one operator. Turret5Capability is the right choice: it creates an immovable turret that a single player aims and fires.',
				capability_selection = "Turret5Capability",
				overall_size_reasoning = "An anti-air gun emplacement is a larger turret, roughly 3.5 meters wide, 3 meters tall, and 3.5 meters deep to accommodate the long barrel and heavy mount.",
				overall_size_selection = { x = 3.5, y = 3, z = 3.5 },
			},
		},
	}
end

function Turret5:getModelPlanningExamples()
	return {
		{
			user = "a sentry gun emplacement",
			assistant = {
				size_reasoning = "The tripod base needs to be wide and stable enough to anchor the turret, about 2m wide and 1m tall. The swivel mount sits on top of the base. The gun body, barrel, and shield plate make up the rotating weapon, with the barrel being the longest component at roughly 2m.",
				turret = {
					description = "a stationary sentry gun: a wide three-legged tripod base, a circular swivel mount, a boxy gun body with an ammo feed, a long barrel, and an angular protective shield plate",
					size = { x = 2.2, y = 2.2, z = 2.4 },
				},
			},
		},
	}
end

function Turret5:getConfigureCapabilityExamples()
	return {
		{
			user = "a rapid-fire sentry turret",
			assistant = {
				capability_parameters_reasoning = "The user wants a rapid-fire sentry turret. This calls for a high fire rate (900 RPM), moderate damage (25), a large magazine (250), fast projectiles (450 studs/s), and minimal spread for accuracy.",
				capability_parameters_selection = {
					gunDamage = 25,
					gunFireRate = 900,
					gunAmmo = 250,
					gunReloadTime = 4,
					gunRange = 700,
					projectileSpeed = 450,
					spreadDegrees = 1,
				},
			},
		},
	}
end

function Turret5:bind(generatedModels: { [string]: Instance }, parameters: { [string]: any }): Model
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Turret5Capability configuration error: " .. tostring(errorMsg))
	end

	local turretModel = generatedModels["turret"]
	if not turretModel then
		error("Turret5Capability: could not find 'turret' model in generatedModels")
	end

	local tripodBase = turretModel:FindFirstChild("tripod base")
	local swivelMount = turretModel:FindFirstChild("swivel mount")
	local gunBody = turretModel:FindFirstChild("gun body")
	local barrel = turretModel:FindFirstChild("barrel")
	local shieldPlate = turretModel:FindFirstChild("shield plate")

	if not tripodBase then error("Turret5Capability: could not find 'tripod base'") end
	if not swivelMount then error("Turret5Capability: could not find 'swivel mount'") end
	if not gunBody then error("Turret5Capability: could not find 'gun body'") end
	if not barrel then error("Turret5Capability: could not find 'barrel'") end
	if not shieldPlate then error("Turret5Capability: could not find 'shield plate'") end

	return makeFunctional(turretModel, tripodBase, swivelMount, gunBody, barrel, shieldPlate, parameters)
end

return Turret5

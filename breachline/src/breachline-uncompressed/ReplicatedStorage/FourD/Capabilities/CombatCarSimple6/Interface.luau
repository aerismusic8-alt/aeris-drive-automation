local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local Gunnable = require(Behaviors.Gunnable)
local GeometryUtils = require(FourD.Common.GeometryUtils)

local DEFAULT_GUN_DAMAGE = 30
local DEFAULT_GUN_FIRE_RATE = 600
local DEFAULT_GUN_AMMO = 100
local DEFAULT_GUN_RELOAD_TIME = 3
local DEFAULT_PROJECTILE_SPEED = 200

local function fillInConfigDefaults(config)
	if config.seatPosition == nil or (config.seatPosition ~= "inside" and config.seatPosition ~= "ontop") then
		config.seatPosition = "ontop"
	end

	config.gunDamage = config.gunDamage or DEFAULT_GUN_DAMAGE
	config.gunFireRate = config.gunFireRate or DEFAULT_GUN_FIRE_RATE
	config.gunAmmo = config.gunAmmo or DEFAULT_GUN_AMMO
	config.gunReloadTime = config.gunReloadTime or DEFAULT_GUN_RELOAD_TIME
	config.projectileSpeed = config.projectileSpeed or DEFAULT_PROJECTILE_SPEED
	if config.projectileName == nil then config.projectileName = "" end
end

local function makeFunctional(
	root, frontLeftWheel, frontRightWheel, rearLeftWheel, rearRightWheel,
	body, gunModel, config
)
	fillInConfigDefaults(config)

	local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
	local bodyCF = bodyAnchor.CFrame
	local gunPartRelativeCFs = {}
	for _, part in ipairs(GeometryUtils.getInstanceParts(gunModel)) do
		gunPartRelativeCFs[part] = bodyCF:ToObjectSpace(part.CFrame)
	end

	gunModel.Parent = nil

	local vehicle = WheeledVehicleArchitect.build4Wheel(body, {
		Schema = {
			WheelFL = frontLeftWheel,
			WheelFR = frontRightWheel,
			WheelRL = rearLeftWheel,
			WheelRR = rearRightWheel,
		},
		SeatPosition = config.seatPosition,
		Performance = { HasNitro = true },
	})
	local assembledCar = vehicle.vehicleModel

	gunModel.Parent = assembledCar
	local newBodyCF = bodyAnchor.CFrame
	for part, relativeCF in pairs(gunPartRelativeCFs) do
		part.CFrame = newBodyCF:ToWorldSpace(relativeCF)
	end

	local driverSeat = assembledCar:FindFirstChildWhichIsA("VehicleSeat", true)

	local turretHandle = Gunnable.newTurret(assembledCar, gunModel, {
		DriverSeat = driverSeat,
	})

	if turretHandle then
		local muzzle = Gunnable.detectMuzzle(assembledCar, gunModel)
		local hardpointHandle = if muzzle
			then Gunnable.newHardpoint(assembledCar, { muzzle }, {
				GunDamage = config.gunDamage,
				GunFireRate = config.gunFireRate,
				GunAmmo = config.gunAmmo,
				GunReloadTime = config.gunReloadTime,
				ProjectileSpeed = config.projectileSpeed,
				ProjectileName = config.projectileName,
				SpreadDegrees = 0.5,
				ReticleLerp = true,
			})
			else nil

		if hardpointHandle then
			turretHandle:BindWeapon(hardpointHandle)
		else
			warn("[CombatCarSimple6] Could not rig turret hardpoint; gun will not fire")
		end
	end

	return assembledCar
end

local CombatCarSimple6 = CapabilityBase.createChild()

function CombatCarSimple6:getCapabilityDocumentation()
	return [[
The CombatCarSimple6Capability creates a drivable four-wheeled vehicle with a roof-mounted stationary gun.
The driver controls the car with standard driving inputs and fires the gun by left-clicking.
The gun is fixed to the car body and fires in the direction the car is facing.
Use this for any armed ground vehicle: gun trucks, tactical SUVs, technicals, armored cars, etc.
Anything with four wheels AND a weapon should use CombatCarSimple6Capability.
]]
end

function CombatCarSimple6:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "CombatCarSimple6",
			description = "a driveable combat vehicle with four wheels, a body, and a gun",
		},
	}
end

function CombatCarSimple6:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "ontop",
			description = "Position of the driver seat relative to the car body",
		})
		:addOptionalArgument("gunDamage", {
			type = "number",
			default = 30,
			minimum = 1,
			description = "Damage per projectile hit",
		})
		:addOptionalArgument("gunFireRate", {
			type = "number",
			default = 600,
			minimum = 30,
			maximum = 1200,
			description = "Rate of fire in rounds per minute (RPM). 600 RPM = 10 shots/second",
		})
		:addOptionalArgument("gunAmmo", {
			type = "number",
			default = 100,
			minimum = 1,
			description = "Magazine size before reload is needed",
		})
		:addOptionalArgument("gunReloadTime", {
			type = "number",
			default = 3,
			minimum = 0.5,
			description = "Time in seconds to reload the gun",
		})
		:addOptionalArgument("projectileSpeed", {
			type = "number",
			default = 200,
			minimum = 50,
			description = "Speed of the projectile in studs per second",
		})
		:addOptionalArgument("projectileName", {
			type = "string",
			default = "",
			description = "Name of a projectile template in ReplicatedStorage.FourD.Projectiles. Empty means no custom projectile model (beam tracer + trail only).",
		})
		:build()
end

function CombatCarSimple6:getCapabilitySelectionExamples()
	return {
		{
			user = "a tactical SUV with a gun",
			assistant = {
				capability_reasoning = 'The user wants a "tactical SUV with a gun" which is an armed ground vehicle. This clearly maps to CombatCarSimple6Capability which creates a drivable four-wheeled car with a roof-mounted gun. The vehicle needs four wheels for driving and a weapon system.',
				capability_selection = "CombatCarSimple6Capability",
				overall_size_reasoning = "A tactical SUV is larger than a standard car, roughly 5 meters long, 2.2 meters wide, and 2.5 meters tall (including the roof-mounted weapon). The weapon adds about 0.5m of height on top of the cabin.",
				overall_size_selection = { x = 2.2, y = 2.5, z = 5 },
			},
		},
		{
			user = "a military humvee with a turret",
			assistant = {
				capability_reasoning = 'The user wants a "military humvee with a turret" which is an armed military ground vehicle. CombatCarSimple6Capability is the right choice as it creates a drivable car with a roof-mounted weapon, perfect for a humvee-style combat vehicle.',
				capability_selection = "CombatCarSimple6Capability",
				overall_size_reasoning = "A military humvee is a large vehicle, approximately 4.6 meters long, 2.2 meters wide, and 2.8 meters tall including the turret mount. These are bulky, armored vehicles designed for combat.",
				overall_size_selection = { x = 2.2, y = 2.8, z = 4.6 },
			},
		},
	}
end

function CombatCarSimple6:getModelPlanningExamples()
	return {
		{
			user = "a gun truck",
			assistant = {
				size_reasoning = "The car body needs to be a full-sized truck large enough for a Roblox avatar (1.5m tall) to sit in, approximately 5m long and 2m wide. The roof-mounted gun should be compact, roughly 1.5m long and 0.5m wide, sitting on top of the cabin roof.",
				car = {
					description = "a rugged military truck with a flat roof suitable for mounting a weapon, armored body panels, and heavy-duty off-road tires",
					size = { x = 2, y = 2, z = 5 },
				},
				gun = {
					description = "a compact roof-mounted machine gun turret with an ammo box and angular protective shield",
					size = { x = 0.5, y = 0.6, z = 1.5 },
				},
			},
		},
	}
end

function CombatCarSimple6:getConfigureCapabilityExamples()
	return {
		{
			user = "a tactical SUV with a machine gun",
			assistant = {
				capability_parameters_reasoning = 'The user wants a tactical SUV with a machine gun. The driver should sit inside the cabin (seatPosition = "ontop" since the seat placement works better for SUVs). For a vehicle-mounted machine gun: high fire rate (800 RPM), moderate damage (30), large ammo capacity (200), and fast projectiles (250 studs/s).',
				capability_parameters_selection = {
					seatPosition = "ontop",
					gunDamage = 30,
					gunFireRate = 800,
					gunAmmo = 200,
					gunReloadTime = 4,
					projectileSpeed = 250,
				},
			},
		},
	}
end

function CombatCarSimple6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("CombatCarSimple6Capability configuration error: " .. errorMsg)
	end

	local carModel = generatedModels["car"]
	if not carModel then
		error("Could not find 'car' model in generatedModels")
	end

	local frontLeftWheel = carModel:FindFirstChild("left front wheel")
	local frontRightWheel = carModel:FindFirstChild("right front wheel")
	local rearLeftWheel = carModel:FindFirstChild("left rear wheel")
	local rearRightWheel = carModel:FindFirstChild("right rear wheel")
	local body = carModel:FindFirstChild("body")
	local gunModel = carModel:FindFirstChild("gun")

	if not frontLeftWheel then error("Could not find 'left front wheel'") end
	if not frontRightWheel then error("Could not find 'right front wheel'") end
	if not rearLeftWheel then error("Could not find 'left rear wheel'") end
	if not rearRightWheel then error("Could not find 'right rear wheel'") end
	if not body then error("Could not find 'body'") end
	if not gunModel then error("Could not find 'gun'") end

	return makeFunctional(
		carModel, frontLeftWheel, frontRightWheel, rearLeftWheel, rearRightWheel,
		body, gunModel, parameters
	)
end

return CombatCarSimple6

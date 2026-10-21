--[[
CombatMotorboatSimple3 Capability - Drivable combat motorboat with buoyancy, thrust, and a forward-fixed cannon

Composes: WaterVehicle2 Architect + Gunnable (Hardpoint)
Schema: CombatMotorboatSimple3 (body, motor, cannon)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WaterVehicle2Architect = require(FourD.Architects.WaterVehicle2)
local Gunnable = require(FourD.Behaviors.Gunnable)
local HelpUI = require(FourD.Common.HelpUI)

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local body = root:FindFirstChild("body")
	local motor = root:FindFirstChild("motor")
	local cannon = root:FindFirstChild("cannon")

	if not body then error("Missing 'body' child in combatmotorboat model") end
	if not motor then error("Missing 'motor' child in combatmotorboat model") end
	if not cannon then error("Missing 'cannon' child in combatmotorboat model") end

	local vessel = WaterVehicle2Architect.build(root, {
		SternReference = motor,
		MaxForwardSpeed = config.maxForwardSpeed,
		MaxReverseSpeed = config.maxReverseSpeed,
		Acceleration = config.acceleration,
		MaxTurnSpeed = config.maxTurnSpeed,
		TurnAcceleration = config.turnAcceleration,
		Draft = 0.5,
	})

	local boat = vessel.vesselModel
	local driverSeat = vessel.driverSeat
	local barrelAttachments = Gunnable.detectHardpoints(cannon, driverSeat.CFrame.LookVector)

	Gunnable.newHardpoint(boat, barrelAttachments, {
		Seat = driverSeat,
		FireSequence = "Cycled",
		GunDamage = 25,
		GunFireRate = 450,
		GunAmmo = -1,
		GunRange = 800,
		ProjectileSpeed = 650,
		ProjectileGravity = 0,
		SpreadDegrees = 0.25,
		ConvergenceRange = 400,
	})

	HelpUI.registerState(boat, "CombatMotorboatSimple3_Driver", {
		Sources = {
			{ Type = "Set", SetId = "WaterVehicle2" },
			{ Type = "Set", SetId = "Gunnable.Hardpoint" },
		},
	})
	boat:SetAttribute("HelpUI_DriverState", "CombatMotorboatSimple3_Driver")

	return boat
end

local CombatMotorboatSimple3 = CapabilityBase.createChild()

function CombatMotorboatSimple3:getCapabilityDocumentation()
	return [[
The CombatMotorboatSimple3Capability creates a functional combat motorboat that floats on water. The player sits in a driver seat and controls the boat with WASD: W/S for throttle forward and reverse, A/D for steering. Buoyancy is simulated with a spring-damper system that keeps the hull at the water surface. While seated, the pilot fires the boat's forward-fixed cannons with the left mouse button. The cannons always fire straight ahead, and their projectiles pass harmlessly through the boat itself.
]]
end

function CombatMotorboatSimple3:getModelSpecs()
	return {
		{
			name = "combatmotorboat",
			modelSchema = "CombatMotorboatSimple3",
			description = "a combat motorboat with a hull body, outboard motor, and mounted cannons",
		},
	}
end

function CombatMotorboatSimple3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxForwardSpeed", {
			type = "number",
			default = 40,
			description = "Maximum forward speed in studs/sec",
		})
		:addOptionalArgument("maxReverseSpeed", {
			type = "number",
			default = 20,
			description = "Maximum reverse speed in studs/sec",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 6,
			description = "Surge acceleration rate in studs/sec^2",
		})
		:addOptionalArgument("maxTurnSpeed", {
			type = "number",
			default = 40,
			description = "Maximum yaw rate in degrees/sec",
		})
		:addOptionalArgument("turnAcceleration", {
			type = "number",
			default = 20,
			description = "Yaw acceleration rate in degrees/sec^2",
		})
		:build()
end

function CombatMotorboatSimple3:getCapabilitySelectionExamples()
	return {
		{
			user = "a combat motorboat",
			assistant = {
				capability_reasoning = "The user wants a combat motorboat, which is a water vehicle with an engine and mounted cannons. CombatMotorboatSimple3Capability creates a functional motorboat with buoyancy, thrust, steering, and functional forward-firing cannons.",
				capability_selection = "CombatMotorboatSimple3Capability",
				overall_size_reasoning = "A combat motorboat is heavier and more armored than a standard motorboat, roughly 2.0m wide, 1.6m tall, and 5m long.",
				overall_size_selection = { x = 2.0, y = 1.6, z = 5.0 },
			},
		},
		{
			user = "a military patrol boat",
			assistant = {
				capability_reasoning = "A military patrol boat is a combat-capable watercraft with mounted weapons. CombatMotorboatSimple3Capability is the correct choice for any armed motor-driven boat.",
				capability_selection = "CombatMotorboatSimple3Capability",
				overall_size_reasoning = "A patrol boat is longer and wider than a civilian motorboat, roughly 2.5m wide, 1.8m tall, and 6m long.",
				overall_size_selection = { x = 2.5, y = 1.8, z = 6.0 },
			},
		},
	}
end

function CombatMotorboatSimple3:getConfigureCapabilityExamples()
	return {
		{
			user = "a combat motorboat",
			assistant = {
				capability_parameters_reasoning = "A standard combat motorboat uses default thrust and steering values.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast combat motorboat",
			assistant = {
				capability_parameters_reasoning = "A fast combat motorboat should have a higher top speed.",
				capability_parameters_selection = {
					maxForwardSpeed = 55,
					maxReverseSpeed = 28,
				},
			},
		},
	}
end

function CombatMotorboatSimple3:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("CombatMotorboatSimple3Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["combatmotorboat"]
	if not model then
		error("Could not find 'combatmotorboat' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return CombatMotorboatSimple3
3
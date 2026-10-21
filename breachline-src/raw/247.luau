local Constants = require(script.Parent.Constants)
local Units = require(script.Parent.Units)

local car = script.Parent.Parent
local vehicleModel = car:FindFirstAncestorOfClass("Model")
local chassis = car.Chassis
local inputs = car.Inputs
local engine = car.Engine
local steering = car.Steering
local wheels = car.Wheels

local wheelMotors = {
	{ Part = wheels.WheelFR.Wheel, Motor = engine.WheelFRMotor, Direction = 1, IsRear = false },
	{ Part = wheels.WheelFL.Wheel, Motor = engine.WheelFLMotor, Direction = -1, IsRear = false },
	{ Part = wheels.WheelRR.Wheel, Motor = engine.WheelRRMotor, Direction = 1, IsRear = true },
	{ Part = wheels.WheelRL.Wheel, Motor = engine.WheelRLMotor, Direction = -1, IsRear = true },
}

for _, wheelMotor in wheelMotors do
	wheelMotor.Radius = wheelMotor.Part.Size.Y / 2
end

local engineParameters: { [string]: number } = {
	forwardMaxSpeed = 0,
	reverseMaxSpeed = 0,
	acceleration = 0,
	deceleration = 0,
	braking = 0,
	engineSpeedCorrection = 0,
	minSpeedTorque = 0,
	maxSpeedTorque = 0,
	handBrakeTorque = 0,
	nitroTorque = 0,
	nitroTime = 0,
	nitroRechargeTime = 0,
	nitroMaxSpeed = 0,
	nitroAcceleration = 100,
	tractionControl = 0,
	tractionSlipTolerance = 0,
}

local steeringParameters: { [string]: number } = {
	steeringReduction = 0,
}

local wheelParameters: { [string]: number } = {
	density = 0, -- Wheel density
	elasticity = 0, -- Wheel elasticity
	staticFriction = 0, -- Wheel friction while it is not sliding
	kineticFriction = 0, -- Wheel friction while it is sliding
	slipThreshold = 0, -- Threshold for the wheel to start sliding
}

local TOW_GRIP_FRICTION_MULTIPLIER = 2
local TOW_GRIP_FRICTION_WEIGHT = 10
local MAX_FRICTION = 2

-- Return the current chassis speed on the local Z axis in miles per hour
local function getChassisForwardSpeed(): number
	local relativeVelocity = chassis.CFrame:VectorToObjectSpace(chassis.AssemblyLinearVelocity)
	local milesPerHour = Units.studsPerSecondToMilesPerHour(-relativeVelocity.Z)
	return milesPerHour
end

-- Update the amount of nitro available
local function updateNitro(deltaTime: number)
	local nitroUsable = car:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE)
	if not nitroUsable then return end

	local nitroInput = inputs:GetAttribute(Constants.NITRO_INPUT_ATTRIBUTE)
	local engineNitro = engine:GetAttribute(Constants.ENGINE_NITRO_ATTRIBUTE)
	local isNitroEnabled = nitroInput and engineNitro > 0
	-- If the nitro input is enabled, lower the nitro level
	if isNitroEnabled then
		local amount = 1 / engineParameters.nitroTime
		engineNitro = math.max(engineNitro - amount * deltaTime, 0)
		-- If the nitro level reaches 0, disable the nitro input
		if engineNitro == 0 then
			inputs:SetAttribute(Constants.NITRO_INPUT_ATTRIBUTE, false)
			nitroInput = false
		end
	else
		-- Recharge the nitro level
		local amount = 1 / engineParameters.nitroRechargeTime
		engineNitro = math.min(engineNitro + amount * deltaTime, 1)
	end
	engine:SetAttribute(Constants.ENGINE_NITRO_ATTRIBUTE, engineNitro)

	engine:SetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE, isNitroEnabled)

	-- Update the nitro constraint
	engine.NitroVelocity.Enabled = isNitroEnabled
	engine.NitroVelocity.VectorVelocity = Vector3.new(0, 0, -engineParameters.nitroMaxSpeed)
end

-- Update the car's target speed and wheel motors' torque and angular velocity
local function updateEngine(deltaTime: number)
	local handBrakeInput = inputs:GetAttribute(Constants.HAND_BRAKE_INPUT_ATTRIBUTE)
	local throttleInput = math.clamp(inputs:GetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE), -1, 1)
	local throttleDirection = math.sign(throttleInput)
	local engineSpeed = engine:GetAttribute(Constants.ENGINE_SPEED_ATTRIBUTE)
	local isNitroEnabled = engine:GetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE)
	local maxSpeed = math.max(engineParameters.forwardMaxSpeed, engineParameters.reverseMaxSpeed)
	local targetSpeed = throttleInput
		* (if throttleDirection >= 0 then engineParameters.forwardMaxSpeed else engineParameters.reverseMaxSpeed)
	local forwardSpeed = getChassisForwardSpeed()
	local isBraking = throttleDirection ~= 0
		and math.abs(forwardSpeed) > 1
		and throttleDirection ~= math.sign(forwardSpeed)
	local acceleration = engineParameters.acceleration

	-- Adjust the acceleration based on whether the car is using nitro, braking, or slowing down
	if isNitroEnabled then
		acceleration = engineParameters.nitroAcceleration
		targetSpeed = engineParameters.nitroMaxSpeed
	elseif isBraking then
		-- When the car is switching directions, we apply braking until it comes to a stop.
		-- This is essentially engine braking, and accelerates the engine speed to 0.
		acceleration = engineParameters.braking
		targetSpeed = 0
	elseif math.abs(targetSpeed) < math.abs(engineSpeed) then
		-- When the car is slowing down in either direction, we use a separate deceleration
		-- parameter to slow the car down slowly, rather than using the higher acceleration value.
		-- This allows the car to glide to a stop when releasing the throttle.
		acceleration = engineParameters.deceleration
	end

	-- Proportionally adjust the engine speed towards the car's actual speed. This prevents the
	-- wheels from continuing to spin after e.g. the car runs into a wall and stops suddenly.
	engineSpeed = math.lerp(engineSpeed, forwardSpeed, math.min(deltaTime * engineParameters.engineSpeedCorrection, 1))
	if targetSpeed > engineSpeed then
		engineSpeed = math.min(engineSpeed + acceleration * deltaTime, targetSpeed)
	else
		engineSpeed = math.max(engineSpeed - acceleration * deltaTime, targetSpeed)
	end
	engine:SetAttribute(Constants.ENGINE_SPEED_ATTRIBUTE, engineSpeed)

	-- Calculate the torque and angular velocity required to reach the target linear velocity
	local chassisSpeed = getChassisForwardSpeed()
	local torqueAlpha = math.min(chassisSpeed, maxSpeed) / maxSpeed
	local torque = math.lerp(engineParameters.minSpeedTorque, engineParameters.maxSpeedTorque, torqueAlpha)
	if isNitroEnabled then
		torque = engineParameters.nitroTorque
	end
	local studsSpeed = Units.milesPerHourToStudsPerSecond(engineSpeed)
	local groundStudsSpeed = math.abs(Units.milesPerHourToStudsPerSecond(chassisSpeed))

	-- Update the wheel motor constraints
	for _, wheelMotor in wheelMotors do
		if wheelMotor.IsRear and handBrakeInput then
			wheelMotor.Motor.AngularVelocity = 0
			wheelMotor.Motor.MotorMaxTorque = engineParameters.handBrakeTorque
			continue
		end

		local angularVelocity = studsSpeed / wheelMotor.Radius
		if engineParameters.tractionControl >= 1 then
			local slipCeiling = (groundStudsSpeed + engineParameters.tractionSlipTolerance) / wheelMotor.Radius
			angularVelocity = math.clamp(angularVelocity, -slipCeiling, slipCeiling)
		end

		wheelMotor.Motor.AngularVelocity = angularVelocity * wheelMotor.Direction
		wheelMotor.Motor.MotorMaxTorque = torque
	end
end

-- Update the steering rack position based on the steering input and current speed of the car
local function updateSteering()
	local steeringInput = math.clamp(inputs:GetAttribute(Constants.STEERING_INPUT_ATTRIBUTE), -1, 1)
	local maxSpeed = math.max(engineParameters.forwardMaxSpeed, engineParameters.reverseMaxSpeed)
	local speed = math.min(getChassisForwardSpeed(), maxSpeed)
	-- Steering is reduced at higher speeds to provide smoother handling
	local steeringFactor = math.max(1 - (speed / maxSpeed) * steeringParameters.steeringReduction, 0)
	local steeringAmount = steeringInput * steeringFactor

	if steeringAmount > 0 then
		steering.SteeringRack.TargetPosition = steeringAmount * steering.SteeringRack.LowerLimit
	else
		steering.SteeringRack.TargetPosition = -steeringAmount * steering.SteeringRack.UpperLimit
	end
end

local function updateWheelFriction()
	local towedMass = if vehicleModel then vehicleModel:GetAttribute(Constants.TOWED_MASS_ATTRIBUTE) or 0 else 0
	local isTowing = towedMass > 0
	for _, wheelMotor in wheelMotors do
		-- Find the difference between the wheel's actual linear speed and the speed it should be moving
		-- based on its current angular velocity.
		local wheelPart = wheelMotor.Part
		local speed = wheelPart.AssemblyLinearVelocity.Magnitude
		local angularVelocity = wheelPart.AssemblyAngularVelocity
		local targetSpeed = wheelMotor.Radius * angularVelocity.Magnitude
		local speedDiff = math.abs(speed - targetSpeed)

		local isKineticFriction = speedDiff > wheelParameters.slipThreshold
		local friction = if isKineticFriction then wheelParameters.kineticFriction else wheelParameters.staticFriction
		local frictionWeight = 1
		if isTowing then
			friction = math.min(friction * TOW_GRIP_FRICTION_MULTIPLIER, MAX_FRICTION)
			frictionWeight = TOW_GRIP_FRICTION_WEIGHT
		end

		wheelPart.CustomPhysicalProperties = PhysicalProperties.new(
			wheelParameters.density,
			friction,
			wheelParameters.elasticity,
			frictionWeight,
			1
		)
	end
end

local function initialize()
	-- Cache all parameters in tables and update them when the corresponding Attribute updates.
	-- Parameters aren't going to change very often so there's no reason to call :GetAttribute() constantly.
	for parameter in engineParameters do
		engine:GetAttributeChangedSignal(parameter):Connect(function()
			engineParameters[parameter] = engine:GetAttribute(parameter)
		end)
		engineParameters[parameter] = engine:GetAttribute(parameter)
	end

	for parameter in steeringParameters do
		steering:GetAttributeChangedSignal(parameter):Connect(function()
			steeringParameters[parameter] = steering:GetAttribute(parameter)
		end)
		steeringParameters[parameter] = steering:GetAttribute(parameter)
	end

	for parameter in wheelParameters do
		wheels:GetAttributeChangedSignal(parameter):Connect(function()
			wheelParameters[parameter] = wheels:GetAttribute(parameter)
		end)
		wheelParameters[parameter] = wheels:GetAttribute(parameter)
	end
end

local Controller = {}

function Controller:Reset()
	-- Reset engine attributes
	engine:SetAttribute(Constants.ENGINE_SPEED_ATTRIBUTE, 0)
	engine:SetAttribute(Constants.ENGINE_NITRO_ATTRIBUTE, 1)
	-- Reset motors
	engine.WheelFRMotor.AngularVelocity = 0
	engine.WheelFRMotor.MotorMaxTorque = engineParameters.minSpeedTorque
	engine.WheelFLMotor.AngularVelocity = 0
	engine.WheelFLMotor.MotorMaxTorque = engineParameters.minSpeedTorque
	engine.WheelRRMotor.AngularVelocity = 0
	engine.WheelRRMotor.MotorMaxTorque = engineParameters.minSpeedTorque
	engine.WheelRLMotor.AngularVelocity = 0
	engine.WheelRLMotor.MotorMaxTorque = engineParameters.minSpeedTorque
	-- Reset nitro
	engine.NitroVelocity.Enabled = false
	-- Reset steering
	steering.SteeringRack.TargetPosition = 0
	-- Reset wheel friction
	for _, wheelMotor in wheelMotors do
		wheelMotor.Part.CustomPhysicalProperties =
			PhysicalProperties.new(wheelParameters.density, wheelParameters.staticFriction, wheelParameters.elasticity)
	end
end

function Controller:Update(deltaTime: number)
	updateNitro(deltaTime)
	updateEngine(deltaTime)
	updateSteering()
	updateWheelFriction()
end

initialize()

return Controller

local Constants = require(script.Parent.Constants)
local Units = require(script.Parent.Units)

local bike = script.Parent.Parent
local chassis = bike.Chassis
local inputs = bike.Inputs
local engine = bike.Engine
local steering = bike.Steering
local wheels = bike.Wheels

local wheelParts = {
	wheels.WheelF.Wheel,
	wheels.WheelR.Wheel,
}

local engineParameters: { [string]: number } = {
	forwardMaxSpeed = 0,
	reverseMaxSpeed = 0,
	acceleration = 0,
	deceleration = 0,
	braking = 0,
	engineSpeedCorrection = 0,
	minSpeedTorque = 0,
	maxSpeedTorque = 0,
	nitroTorque = 0,
	nitroTime = 0,
	nitroRechargeTime = 0,
	nitroMaxSpeed = 0,
	nitroAcceleration = 100,
}

local steeringParameters: { [string]: number } = {
	steeringReduction = 0,
	maxSteerDegrees = 30,
}

local chassisParameters: { [string]: number } = {
	maxLeanDegrees = 25,
	leanGain = 1.0,
	leanCompensation = 1.0,
	balanceStrength = 1200,
	balanceDamping = 140,
	yawStrength = 18,
	maxYawRate = 2.0,
	maxLateralAccel = 150,
	brakeBias = 0.65,
	maxInclineDegrees = 42,
	jumpImpulse = 35,
}

local wheelParameters: { [string]: number } = {
	density = 0,
	elasticity = 0,
	staticFriction = 0,
	kineticFriction = 0,
	slipThreshold = 0,
}

local wheelRadius = wheelParts[1].Size.Y / 2

local GROUND_RAY_LENGTH = 12
local FORK_VISUAL_STEER_FACTOR = 0.5
local FORK_STEER_SMOOTHING = 8
local LEAN_SMOOTHING = 6
local LEAN_RETURN_SMOOTHING = 3
local FRONT_TURN_GRIP_FALLOFF = 0.75
local JUMP_COOLDOWN = 0.5

local lastJumpTime = -math.huge

local forkMotor = chassis:FindFirstChild("ForkMotor")
local balanceTorque = chassis:FindFirstChild("BalanceTorque")
local currentForkAngle = 0
local currentLeanAmount = 0
local assemblyRoot = bike.Parent

local groundRaycastParams = RaycastParams.new()
groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
groundRaycastParams.IgnoreWater = true
-- One RaycastParams drives both the chassis lean and the jump gate, so without
-- this the bike could lean to the normal of a decal it drives through.
groundRaycastParams.RespectCanCollide = true
groundRaycastParams.FilterDescendantsInstances = { assemblyRoot }

local function getChassisForwardSpeed(): number
	local relativeVelocity = chassis.CFrame:VectorToObjectSpace(chassis.AssemblyLinearVelocity)
	return Units.studsPerSecondToMilesPerHour(-relativeVelocity.Z)
end

local function updateNitro(deltaTime: number)
	local nitroUsable = bike:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE)
	if not nitroUsable then return end

	local nitroInput = inputs:GetAttribute(Constants.NITRO_INPUT_ATTRIBUTE)
	local engineNitro = engine:GetAttribute(Constants.ENGINE_NITRO_ATTRIBUTE)
	local isNitroEnabled = nitroInput and engineNitro > 0

	if isNitroEnabled then
		local amount = 1 / engineParameters.nitroTime
		engineNitro = math.max(engineNitro - amount * deltaTime, 0)
		if engineNitro == 0 then
			inputs:SetAttribute(Constants.NITRO_INPUT_ATTRIBUTE, false)
			nitroInput = false
		end

	else
		local amount = 1 / engineParameters.nitroRechargeTime
		engineNitro = math.min(engineNitro + amount * deltaTime, 1)
	end
	engine:SetAttribute(Constants.ENGINE_NITRO_ATTRIBUTE, engineNitro)
	engine:SetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE, isNitroEnabled)

	engine.NitroVelocity.Enabled = isNitroEnabled
	engine.NitroVelocity.VectorVelocity = Vector3.new(0, 0, -engineParameters.nitroMaxSpeed)
end

local function updateEngine(deltaTime: number)
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

	if isNitroEnabled then
		acceleration = engineParameters.nitroAcceleration
		targetSpeed = engineParameters.nitroMaxSpeed
	elseif isBraking then
		acceleration = engineParameters.braking
		targetSpeed = 0
	elseif math.abs(targetSpeed) < math.abs(engineSpeed) then
		acceleration = engineParameters.deceleration
	end

	if not isBraking then
		engineSpeed = math.lerp(engineSpeed, forwardSpeed, math.min(deltaTime * engineParameters.engineSpeedCorrection, 1))
	end

	if targetSpeed > engineSpeed then
		engineSpeed = math.min(engineSpeed + acceleration * deltaTime, targetSpeed)
	else
		engineSpeed = math.max(engineSpeed - acceleration * deltaTime, targetSpeed)
	end

	engine:SetAttribute(Constants.ENGINE_SPEED_ATTRIBUTE, engineSpeed)

	local chassisSpeed = math.abs(getChassisForwardSpeed())
	local torqueAlpha = math.min(chassisSpeed, maxSpeed) / maxSpeed
	local torque = math.lerp(engineParameters.minSpeedTorque, engineParameters.maxSpeedTorque, torqueAlpha)
	if isNitroEnabled then
		torque = engineParameters.nitroTorque
	end

	local studsSpeed = Units.milesPerHourToStudsPerSecond(engineSpeed)
	local angularVelocity = studsSpeed / wheelRadius

	if isBraking then
		local brakeBias = math.clamp(chassisParameters.brakeBias, 0, 1)
		engine.WheelFMotor.AngularVelocity = -angularVelocity
		engine.WheelFMotor.MotorMaxTorque = torque * brakeBias
		engine.WheelRMotor.AngularVelocity = -angularVelocity
		engine.WheelRMotor.MotorMaxTorque = torque * (1 - brakeBias)
	else
		engine.WheelFMotor.AngularVelocity = 0
		engine.WheelFMotor.MotorMaxTorque = 0
		engine.WheelRMotor.AngularVelocity = -angularVelocity
		engine.WheelRMotor.MotorMaxTorque = torque
	end
end

local function updateSteeringAndLean(deltaTime: number)
	local steeringInput = math.clamp(inputs:GetAttribute(Constants.STEERING_INPUT_ATTRIBUTE), -1, 1)
	local maxSpeed = math.max(engineParameters.forwardMaxSpeed, engineParameters.reverseMaxSpeed)
	local forwardSpeed = getChassisForwardSpeed()
	local speedNorm = math.clamp(math.abs(forwardSpeed) / maxSpeed, 0, 1)

	local steeringFactor = math.max(1 - speedNorm * steeringParameters.steeringReduction, 0)
	if forkMotor then
		local targetForkAngle = -steeringInput
			* steeringFactor
			* steeringParameters.maxSteerDegrees
			* FORK_VISUAL_STEER_FACTOR
		currentForkAngle = math.lerp(currentForkAngle, targetForkAngle, math.min(deltaTime * FORK_STEER_SMOOTHING, 1))
		forkMotor.Transform = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(currentForkAngle))
	end

	if not balanceTorque or not balanceTorque.Enabled then
		return
	end

	local cframe = chassis.CFrame
	local up = cframe.UpVector
	local rightVector = cframe.RightVector
	local mass = chassis.AssemblyMass
	local angularVelocity = chassis.AssemblyAngularVelocity

	local desiredUp = Vector3.yAxis
	local rayResult = workspace:Raycast(cframe.Position, Vector3.new(0, -GROUND_RAY_LENGTH, 0), groundRaycastParams)
	if rayResult then
		local incline = math.acos(math.clamp(rayResult.Normal:Dot(Vector3.yAxis), -1, 1))
		if incline <= math.rad(chassisParameters.maxInclineDegrees) then
			local heading = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
			if heading.Magnitude > 1e-3 then
				local lateralAxis = Vector3.yAxis:Cross(heading.Unit)
				local pitchedUp = rayResult.Normal - lateralAxis * rayResult.Normal:Dot(lateralAxis)
				if pitchedUp.Magnitude > 1e-3 then
					desiredUp = pitchedUp.Unit
				end

			else
				desiredUp = rayResult.Normal
			end
		end
	end

	local yawRate = angularVelocity:Dot(Vector3.yAxis)
	local reverseSign = if forwardSpeed < 0 then -1 else 1
	local forwardStuds = Units.milesPerHourToStudsPerSecond(forwardSpeed)
	local targetYawRate = -steeringInput * speedNorm * chassisParameters.maxYawRate * reverseSign

	local speedMagnitude = math.abs(forwardStuds)
	if speedMagnitude > 1 then
		local yawRateCap = chassisParameters.maxLateralAccel / speedMagnitude
		targetYawRate = math.clamp(targetYawRate, -yawRateCap, yawRateCap)
	end

	local gravity = workspace.Gravity
	local lateralAccel = -targetYawRate * forwardStuds
	local maxLeanTan = math.tan(math.rad(chassisParameters.maxLeanDegrees))
	local targetLeanAmount = math.clamp((lateralAccel / gravity) * chassisParameters.leanGain, -maxLeanTan, maxLeanTan)
	local leanRate = if math.abs(targetLeanAmount) < math.abs(currentLeanAmount)
		then LEAN_RETURN_SMOOTHING
		else LEAN_SMOOTHING
	currentLeanAmount = math.lerp(currentLeanAmount, targetLeanAmount, math.min(deltaTime * leanRate, 1))
	desiredUp = (desiredUp + rightVector * currentLeanAmount).Unit

	local correctionAxis = up:Cross(desiredUp)
	local levelingRate = angularVelocity - Vector3.yAxis * yawRate
	local levelTorque = correctionAxis * chassisParameters.balanceStrength
		- levelingRate * chassisParameters.balanceDamping

	local rollFeedForward = Vector3.zero
	if rayResult then
		local comHeight = math.max((chassis.AssemblyCenterOfMass - rayResult.Position):Dot(up), 0)
		rollFeedForward = cframe.LookVector * (lateralAccel * comHeight * chassisParameters.leanCompensation)
	end

	local yawTorque = Vector3.yAxis * ((targetYawRate - yawRate) * chassisParameters.yawStrength)

	balanceTorque.Torque = (levelTorque + rollFeedForward + yawTorque) * mass
end

local function updateWheelFriction()
	local steeringInput = math.abs(math.clamp(inputs:GetAttribute(Constants.STEERING_INPUT_ATTRIBUTE), -1, 1))
	local maxSpeed = math.max(engineParameters.forwardMaxSpeed, engineParameters.reverseMaxSpeed)
	local speedNorm = math.clamp(math.abs(getChassisForwardSpeed()) / maxSpeed, 0, 1)
	local frontGripFactor = math.lerp(1, FRONT_TURN_GRIP_FALLOFF, steeringInput * speedNorm)

	for index, wheelPart in wheelParts do
		local speed = wheelPart.AssemblyLinearVelocity.Magnitude
		local angularVelocity = wheelPart.AssemblyAngularVelocity
		local targetSpeed = wheelRadius * angularVelocity.Magnitude
		local speedDiff = math.abs(speed - targetSpeed)

		local isKineticFriction = speedDiff > wheelParameters.slipThreshold
		local friction = if isKineticFriction then wheelParameters.kineticFriction else wheelParameters.staticFriction

		if index == 1 then
			friction *= frontGripFactor
		end

		wheelPart.CustomPhysicalProperties =
			PhysicalProperties.new(wheelParameters.density, friction, wheelParameters.elasticity)
	end
end

local function initialize()
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
		local current = steering:GetAttribute(parameter)
		if current ~= nil then
			steeringParameters[parameter] = current
		end
	end

	for parameter in chassisParameters do
		chassis:GetAttributeChangedSignal(parameter):Connect(function()
			chassisParameters[parameter] = chassis:GetAttribute(parameter)
		end)
		local current = chassis:GetAttribute(parameter)
		if current ~= nil then
			chassisParameters[parameter] = current
		end
	end

	for parameter in wheelParameters do
		wheels:GetAttributeChangedSignal(parameter):Connect(function()
			wheelParameters[parameter] = wheels:GetAttribute(parameter)
		end)
		wheelParameters[parameter] = wheels:GetAttribute(parameter)
	end
end

local Controller = {}

function Controller:reset()
	engine:SetAttribute(Constants.ENGINE_SPEED_ATTRIBUTE, 0)
	engine:SetAttribute(Constants.ENGINE_NITRO_ATTRIBUTE, 1)
	engine.WheelFMotor.AngularVelocity = 0
	engine.WheelFMotor.MotorMaxTorque = 0
	engine.WheelRMotor.AngularVelocity = 0
	engine.WheelRMotor.MotorMaxTorque = engineParameters.minSpeedTorque
	engine.NitroVelocity.Enabled = false
	currentForkAngle = 0
	currentLeanAmount = 0
	if forkMotor then
		forkMotor.Transform = CFrame.identity
	end

	if balanceTorque then
		balanceTorque.Torque = Vector3.zero
	end

	for _, wheelPart in wheelParts do
		wheelPart.CustomPhysicalProperties =
			PhysicalProperties.new(wheelParameters.density, wheelParameters.staticFriction, wheelParameters.elasticity)
	end
end

function Controller:jump()
	if os.clock() - lastJumpTime < JUMP_COOLDOWN then
		return
	end

	local origin = chassis.CFrame.Position
	local rayResult = workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_LENGTH, 0), groundRaycastParams)
	if not rayResult then
		return
	end

	lastJumpTime = os.clock()
	chassis:ApplyImpulse(Vector3.yAxis * chassisParameters.jumpImpulse * chassis.AssemblyMass)
end

function Controller:update(deltaTime: number)
	updateNitro(deltaTime)
	updateEngine(deltaTime)
	updateSteeringAndLean(deltaTime)
	updateWheelFriction()
end

initialize()

return Controller

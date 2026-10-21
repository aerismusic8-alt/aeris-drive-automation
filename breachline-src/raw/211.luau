--[[
	File: Controller.luau

	Client-side drive logic. Runs on the rider's client (which holds network
	ownership of the chassis). Reads input attributes written by Input/*,
	performs ground raycasts to detect airborne state, and writes hinge motor
	target velocities and steer angular velocity directly.
]]--

-- Root

local Controller = {}

-- Roblox Services

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Constants

local WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }

-- Public Functions

function Controller.start(boardRig: Model, ownerCharacter: Model): () -> ()
	local localPlayer = Players.LocalPlayer
	local chassis = boardRig:WaitForChild("Chassis")
	local wheelsFolder = boardRig:WaitForChild("Wheels")
	local steerAngularVelocity = chassis:WaitForChild("SteerAngularVelocity")
	local stabilityGyro = chassis:WaitForChild("StabilityGyro")
	local ownerValue = boardRig:WaitForChild(Constants.OWNER_VALUE_NAME)
	local config = boardRig.Parent and boardRig.Parent:FindFirstChild("BoardConfig")
	local airborne = false

	local hinges: { HingeConstraint } = {}
	local wheels: { BasePart } = {}
	for _, wheelName in WHEEL_NAMES do
		local wheelPart = (wheelsFolder:WaitForChild(wheelName)):WaitForChild("Wheel")
		local hinge = wheelPart:FindFirstChildOfClass("HingeConstraint")
		assert(hinge, `Board: {wheelName} missing HingeConstraint`)
		table.insert(wheels, wheelPart)
		table.insert(hinges, hinge)
	end

	local function getNumberValue(name: string): NumberValue?
		if not config then return nil end

		local child = config:FindFirstChild(name)
		if child and child:IsA("NumberValue") then
			return child
		end

		return nil
	end

	local function readNumber(numberValue: NumberValue?, fallback: number): number
		return if numberValue then numberValue.Value else fallback
	end

	local wheelRadiusVal = getNumberValue("WheelRadius")
	local maxSpeedVal = getNumberValue("MaxSpeed")
	local turnSpeedVal = getNumberValue("TurnSpeed")
	local turnSpeedAirMultVal = getNumberValue("TurnSpeedAirMult")
	local motorMaxTorqueVal = getNumberValue("MotorMaxTorque")
	local accelerationSpeedVal = getNumberValue("AccelerationSpeed")
	local inertiaFactorVal = getNumberValue("SteerAuthorityInertiaFactor")
	local frictionFactorVal = getNumberValue("SteerAuthorityFrictionFactor")
	local safetyFactorVal = getNumberValue("SteerAuthoritySafetyFactor")
	local airFactorVal = getNumberValue("SteerAuthorityAirFactor")
	local frictionCoefficientVal = getNumberValue("SteerFrictionCoefficient")
	local spinUpTimeVal = getNumberValue("SteerSpinUpTime")
	local inputDeadzoneVal = getNumberValue("SteerInputDeadzone")
	local ollieImpulseVal = getNumberValue("OllieImpulse")
	local stabilizeTorqueFactorVal = getNumberValue("StabilizeTorqueFactor")
	local stabilizeLandingGraceVal = getNumberValue("StabilizeLandingGrace")
	local landedAt = -math.huge
	local wasAirborne = false

	local assemblyMass = chassis.AssemblyMass
	local chassisX = chassis.Size.X
	local chassisZ = chassis.Size.Z
	local inertiaY = assemblyMass * (chassisX * chassisX + chassisZ * chassisZ) / 12
	local leverArm = math.sqrt((chassisX * 0.5) ^ 2 + (chassisZ * 0.5) ^ 2)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { boardRig.Parent, ownerCharacter }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	local function resetOutputs()
		for _, hinge in hinges do
			hinge.AngularVelocity = 0
		end

		steerAngularVelocity.AngularVelocity = Vector3.zero
		steerAngularVelocity.MaxTorque = Vector3.zero
		stabilityGyro.MaxTorque = Vector3.zero
	end

	local conn = RunService.Heartbeat:Connect(function(_)
		if not boardRig.Parent then return end
		if not config then return end
		if ownerValue.Value ~= localPlayer then
			resetOutputs()
			return
		end

		local wheelRadius = readNumber(wheelRadiusVal, 0.5)
		local rayLength = wheelRadius * Constants.GROUND_RAYCAST_LENGTH_MULT
		local touchedCount = 0

		for _, wheel in wheels do
			local result = workspace:Raycast(wheel.Position, Vector3.new(0, -rayLength, 0), raycastParams)
			if result then
				touchedCount += 1
			end
		end

		airborne = touchedCount == 0
		boardRig:SetAttribute(Constants.AIRBORNE_ATTRIBUTE, airborne)

		if wasAirborne and not airborne then
			landedAt = os.clock()
		end
		wasAirborne = airborne

		local stabilizeGrace = readNumber(stabilizeLandingGraceVal, 0.2)
		if airborne or (os.clock() - landedAt) < stabilizeGrace then
			local stabilizeFactor = readNumber(stabilizeTorqueFactorVal, 0.5)
			local stabilizeCap = assemblyMass * workspace.Gravity * leverArm * stabilizeFactor
			stabilityGyro.MaxTorque = Vector3.new(stabilizeCap, 0, stabilizeCap)
		else
			stabilityGyro.MaxTorque = Vector3.zero
		end

		local throttle = boardRig:GetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE) or 0
		local steering = boardRig:GetAttribute(Constants.STEERING_INPUT_ATTRIBUTE) or 0

		local maxSpeed = readNumber(maxSpeedVal, 60)
		local turnSpeed = readNumber(turnSpeedVal, 90)
		local turnSpeedAirMult = readNumber(turnSpeedAirMultVal, 1.5)
		local motorMaxTorque = readNumber(motorMaxTorqueVal, 0)
		local accelerationSpeed = readNumber(accelerationSpeedVal, 35)
		local inertiaFactor = readNumber(inertiaFactorVal, 4)
		local frictionFactor = readNumber(frictionFactorVal, 4)
		local safetyFactor = readNumber(safetyFactorVal, 5)
		local airFactor = readNumber(airFactorVal, 0.25)
		local frictionCoefficient = readNumber(frictionCoefficientVal, 1.5)
		local spinUpTime = readNumber(spinUpTimeVal, 0.15)
		local inputDeadzone = readNumber(inputDeadzoneVal, 0.05)
		local motorMaxAcceleration = accelerationSpeed / wheelRadius

		local desiredAngularVelocity = (throttle * maxSpeed) / wheelRadius
		if airborne then
			desiredAngularVelocity = 0
		end

		for _, hinge in hinges do
			hinge.AngularVelocity = desiredAngularVelocity
			hinge.MotorMaxTorque = if airborne then 0 else motorMaxTorque / 4
			hinge.MotorMaxAcceleration = motorMaxAcceleration
		end

		local turnSpeedRad = math.rad(turnSpeed)
		local airMult = if airborne then turnSpeedAirMult else 1
		local desiredYawRate = -steering * turnSpeedRad * airMult

		local yawAccel = turnSpeedRad / math.max(spinUpTime, 1e-3)
		local inertialBudget = inertiaY * yawAccel * inertiaFactor
		local frictionBudget = frictionCoefficient * assemblyMass * workspace.Gravity * leverArm * frictionFactor
		local cap = math.max(inertialBudget, frictionBudget) * safetyFactor
		if airborne then
			cap *= airFactor
		end
		if math.abs(steering) < inputDeadzone then
			cap = 0
		end

		local upVector = chassis.CFrame.UpVector
		steerAngularVelocity.AngularVelocity = upVector * desiredYawRate
		steerAngularVelocity.MaxTorque = Vector3.new(math.abs(upVector.X), math.abs(upVector.Y), math.abs(upVector.Z)) * cap
	end)

	local ollieConn = boardRig:GetAttributeChangedSignal(Constants.LAST_OLLIE_ATTRIBUTE):Connect(function()
		if ownerValue.Value ~= localPlayer then return end
		if airborne then return end

		local ollieImpulse = readNumber(ollieImpulseVal, 30)
		chassis:ApplyImpulse(chassis.CFrame.UpVector * ollieImpulse * chassis.AssemblyMass)
	end)

	return function()
		ollieConn:Disconnect()
		conn:Disconnect()
		resetOutputs()
	end
end

-- Return

return Controller
OB
-- GENERATED WRAPPER around upstream WaterVehicle2Client.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: WaterVehicle2Client (init.server.luau)
	Client-side physics controller for WaterVehicle2 rigs (RunContext = Client).
	Activated when the local player sits in the DriverSeat.
	Manages surge, yaw, banking tilt, and ballast buoyancy via velocity constraints.
	Player input (throttle, steering) is owned by the Input subsystem.
]]--

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD", 5)
local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
local HelpUI = require(FourD.Common.HelpUI)
local WaterUtils = require(Shared.Utils.WaterUtils)
local Input = require(script:WaitForChild("Input"))

-- Constants

local BALLAST_KP = 4
local MAX_VERTICAL_SPEED = 20
local PLOP_THRESHOLD = 30
local MAX_TILT_ANGLE = math.rad(10)
local TILT_SMOOTH_RATE = math.rad(15)
local ROLL_KP = 6
local ROLL_DAMPING = 1.5
local ROTOR_MAX_SPEED = 20
local MAX_RUDDER_ANGLE = math.rad(35)
local RUDDER_SMOOTH_RATE = math.rad(180)

-- References

local model = script.Parent
local player = Players.LocalPlayer

local hull = model.PrimaryPart
if not hull then return end

local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
if not seat then
	-- Dispatched from a scan, so this body can run before the rest
	-- of the model replicates. Returning here is permanent: the
	-- dispatcher starts a host once and never revisits it.
	local seatDeadline = os.clock() + 10
	repeat
		task.wait()
		seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	until seat or os.clock() >= seatDeadline
end
if not seat then return end

local surgeVelocity = hull:FindFirstChild("SurgeVelocity")
local yawVelocity = hull:FindFirstChild("YawVelocity")
if not surgeVelocity or not yawVelocity then return end

local rotorMotors: { Motor6D } = {}
for _, child in hull:GetChildren() do
	if child:IsA("Motor6D") and string.sub(child.Name, 1, 10) == "RotorMotor" then
		table.insert(rotorMotors, child)
	end
end

local rotorsAreWheels = hull:GetAttribute("RotorsAreWheels") == true
local rotorWheelRadii: { number } = {}
if rotorsAreWheels then
	for i, motor in rotorMotors do
		rotorWheelRadii[i] = motor:GetAttribute("WheelRadius") or 1
	end
end

local rudderMotor: Motor6D? = hull:FindFirstChild("RudderMotor")

local ballastFolder = model:FindFirstChild("Ballasts")
if not ballastFolder then return end

local ballasts: { BasePart } = {}
for _, child in ballastFolder:GetChildren() do
	if child:IsA("BasePart") then
		table.insert(ballasts, child)
	end
end
table.sort(ballasts, function(a, b) return a.Name < b.Name end)

local ballastVelocities: { LinearVelocity } = {}
for i, ballast in ballasts do
	ballastVelocities[i] = ballast:FindFirstChild("BuoyancyVelocity")
end

-- Config from Attributes

local maxForwardSpeed = hull:GetAttribute("MaxForwardSpeed") or 40
local maxReverseSpeed = hull:GetAttribute("MaxReverseSpeed") or 20
local acceleration = hull:GetAttribute("Acceleration") or 8
local maxTurnSpeed = math.rad(hull:GetAttribute("MaxTurnSpeed") or 45)
local turnAcceleration = math.rad(hull:GetAttribute("TurnAcceleration") or 60)
local draftOffset = hull:GetAttribute("DraftOffset") or 0
local spinAxis: Vector3 = if #rotorMotors > 0
	then Vector3.new(
		hull:GetAttribute("SpinAxisX") or 0,
		hull:GetAttribute("SpinAxisY") or 0,
		hull:GetAttribute("SpinAxisZ") or 0
	)
	else Vector3.zero

-- State

local currentSurgeSpeed = 0
local currentYawSpeed = 0
local currentTargetTilt = 0
local rollRate = 0
local rotorAngle = 0
local currentRudderAngle = 0
local heartbeatConn: RBXScriptConnection? = nil

-- Local Functions

local function isDriver(): boolean
	if not seat.Occupant then return false end
	return seat.Occupant.Parent == player.Character
end

local function ramp(current: number, target: number, rate: number, dt: number): number
	return current + math.clamp(target - current, -rate * dt, rate * dt)
end

local function updateBallasts()
	for i, ballast in ballasts do
		local velocity = ballastVelocities[i]
		if not velocity then continue end

		local waterLevelY = WaterUtils.getWaterLevel(ballast.Position)
		if not waterLevelY then
			velocity.VectorVelocity = Vector3.zero
			continue
		end

		local draftError = (waterLevelY + draftOffset) - ballast.Position.Y
		if draftError <= -PLOP_THRESHOLD then
			velocity.VectorVelocity = Vector3.zero
			continue
		end

		local vy = math.clamp(draftError * BALLAST_KP, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)
		velocity.VectorVelocity = Vector3.new(0, vy, 0)
	end
end

local function update(dt: number)
	updateBallasts()

	if not isDriver() then
		surgeVelocity.VectorVelocity = Vector3.zero
		yawVelocity.AngularVelocity = Vector3.zero
		if rudderMotor then
			currentRudderAngle = ramp(currentRudderAngle, 0, RUDDER_SMOOTH_RATE, dt)
			rudderMotor.Transform = CFrame.Angles(0, currentRudderAngle, 0)
		end
		return
	end

	local state = Input.poll()
	local throttle = state.Throttle
	local steering = state.Steering

	local targetSurge = if throttle >= 0 then throttle * maxForwardSpeed else throttle * maxReverseSpeed
	currentSurgeSpeed = ramp(currentSurgeSpeed, targetSurge, acceleration, dt)
	surgeVelocity.VectorVelocity = Vector3.new(0, 0, -currentSurgeSpeed)

	local targetYaw = -steering * maxTurnSpeed
	currentYawSpeed = ramp(currentYawSpeed, targetYaw, turnAcceleration, dt)

	local speedFactor = math.clamp(math.abs(currentSurgeSpeed) / maxForwardSpeed, 0, 1)
	local desiredTilt = steering * MAX_TILT_ANGLE * speedFactor
	currentTargetTilt = ramp(currentTargetTilt, desiredTilt, TILT_SMOOTH_RATE, dt)

	local _, _, actualRoll = hull.CFrame:ToOrientation()
	local rollAccel = (currentTargetTilt - actualRoll) * ROLL_KP - rollRate * ROLL_DAMPING
	rollRate += rollAccel * dt

	yawVelocity.AngularVelocity = Vector3.new(0, currentYawSpeed, rollRate)

	if rudderMotor then
		local targetRudder = steering * MAX_RUDDER_ANGLE
		currentRudderAngle = ramp(currentRudderAngle, targetRudder, RUDDER_SMOOTH_RATE, dt)
		rudderMotor.Transform = CFrame.Angles(0, currentRudderAngle, 0)
	end

	if #rotorMotors > 0 then
		if rotorsAreWheels then
			for i, motor in rotorMotors do
				local radius = rotorWheelRadii[i]
				local angle = (currentSurgeSpeed / radius) * dt
				motor.Transform = motor.Transform * CFrame.Angles(
					spinAxis.X * angle,
					spinAxis.Y * angle,
					spinAxis.Z * angle
				)
			end
		else
			rotorAngle += math.abs(throttle) * ROTOR_MAX_SPEED * dt
			for _, motor in rotorMotors do
				motor.Transform = CFrame.Angles(
					spinAxis.X * rotorAngle,
					spinAxis.Y * rotorAngle,
					spinAxis.Z * rotorAngle
				)
			end
		end
	end
end

local function deactivate()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	Input.disable()

	surgeVelocity.VectorVelocity = Vector3.zero
	yawVelocity.AngularVelocity = Vector3.zero

	for _, velocity in ballastVelocities do
		velocity.VectorVelocity = Vector3.zero
	end

	if rudderMotor then
		currentRudderAngle = 0
		rudderMotor.Transform = CFrame.identity
	end

	currentSurgeSpeed = 0
	currentYawSpeed = 0
	currentTargetTilt = 0
	rollRate = 0

	HelpUI.clearRole(model)
end

local function activate()
	if heartbeatConn then return end

	currentSurgeSpeed = 0
	currentYawSpeed = 0
	currentTargetTilt = 0
	rollRate = 0
	currentRudderAngle = 0

	Input.enable(seat)

	heartbeatConn = RunService.Heartbeat:Connect(update)

	HelpUI.applyRole(model, "WaterVehicle2", "HelpUI_DriverState")
end

local function onOccupantChanged()
	if isDriver() then
		activate()
	else
		deactivate()
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
onOccupantChanged()

end

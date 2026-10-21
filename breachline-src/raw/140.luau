-- GENERATED WRAPPER around upstream WaterSubmersibleClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: WaterSubmersibleClient (init.server.luau)
	Client-side physics controller for WaterSubmersible rigs (RunContext = Client).
	Activated when the local player sits in the DriverSeat.
	Manages surge, yaw, and depth via velocity constraints. Player input (throttle,
	steering, dive/surface) is owned by the Input subsystem.
]]--

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD", 5)
local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
local WaterUtils = require(Shared.Utils.WaterUtils)
local HelpUI = require(FourD.Common.HelpUI)
local Input = require(script:WaitForChild("Input"))

-- Constants

local DEPTH_KP = 4
local ROTOR_MAX_SPEED = 20
local ROTOR_ANGLE_WRAP = 2 * math.pi
local MAX_PITCH_ANGLE = math.rad(5)
local PITCH_SMOOTH_RATE = math.rad(8)
local PITCH_KP = 3
local ROLL_KP = 1
local SURGE_DEADBAND = 1

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
local depthVelocity = hull:FindFirstChild("DepthVelocity")
if not surgeVelocity or not yawVelocity or not depthVelocity then return end

local rotorEntries: { { Motor: Motor6D, Axis: Vector3 } } = {}
for _, child in hull:GetChildren() do
	if child:IsA("Motor6D") and string.sub(child.Name, 1, 10) == "RotorMotor" then
		local ax = child:GetAttribute("SpinAxisX") or 0
		local ay = child:GetAttribute("SpinAxisY") or 0
		local az = child:GetAttribute("SpinAxisZ") or 0
		table.insert(rotorEntries, { Motor = child, Axis = Vector3.new(ax, ay, az) })
	end
end

-- Config from Attributes

local maxForwardSpeed: number = hull:GetAttribute("MaxForwardSpeed") or 40
local maxReverseSpeed: number = hull:GetAttribute("MaxReverseSpeed") or 20
local acceleration: number = hull:GetAttribute("Acceleration") or 8
local maxTurnSpeed: number = math.rad(hull:GetAttribute("MaxTurnSpeed") or 45)
local turnAcceleration: number = math.rad(hull:GetAttribute("TurnAcceleration") or 60)
local depthChangeSpeed: number = hull:GetAttribute("DepthChangeSpeed") or 15

-- State

local currentSurgeSpeed = 0
local currentYawSpeed = 0
local currentTargetPitch = 0
local targetDepthY = hull.Position.Y
local rotorAngle = 0
local heartbeatConn: RBXScriptConnection? = nil

-- Local Functions

local function isDriver(): boolean
	if not seat.Occupant then return false end
	return seat.Occupant.Parent == player.Character
end

local function ramp(current: number, target: number, rate: number, dt: number): number
	return current + math.clamp(target - current, -rate * dt, rate * dt)
end

local function update(dt: number)
	local state = Input.poll()
	local throttle = state.Throttle
	local steering = state.Steering

	local targetSurge = if throttle >= 0 then throttle * maxForwardSpeed else throttle * maxReverseSpeed
	currentSurgeSpeed = ramp(currentSurgeSpeed, targetSurge, acceleration, dt)
	surgeVelocity.VectorVelocity = Vector3.new(0, 0, -currentSurgeSpeed)

	local targetYaw = -steering * maxTurnSpeed
	currentYawSpeed = ramp(currentYawSpeed, targetYaw, turnAcceleration, dt)

	local desiredPitch = 0
	if state.IsDiving ~= state.IsSurfacing then
		local movingForward = currentSurgeSpeed > SURGE_DEADBAND
		local movingBackward = currentSurgeSpeed < -SURGE_DEADBAND
		if state.IsDiving and movingForward then
			desiredPitch = -MAX_PITCH_ANGLE
		elseif state.IsDiving and movingBackward then
			desiredPitch = MAX_PITCH_ANGLE
		elseif state.IsSurfacing and movingForward then
			desiredPitch = MAX_PITCH_ANGLE
		elseif state.IsSurfacing and movingBackward then
			desiredPitch = -MAX_PITCH_ANGLE
		end
	end

	currentTargetPitch = ramp(currentTargetPitch, desiredPitch, PITCH_SMOOTH_RATE, dt)
	local actualPitch = math.asin(math.clamp(hull.CFrame.LookVector.Y, -1, 1))
	local pitchRate = (currentTargetPitch - actualPitch) * PITCH_KP

	local _, _, actualRoll = hull.CFrame:ToOrientation()
	local rollRate = -actualRoll * ROLL_KP

	yawVelocity.AngularVelocity = Vector3.new(pitchRate, currentYawSpeed, rollRate)

	-- Depth
	if state.IsDiving and not state.IsSurfacing then
		targetDepthY -= depthChangeSpeed * dt
	elseif state.IsSurfacing and not state.IsDiving then
		targetDepthY += depthChangeSpeed * dt
	end

	local waterY = WaterUtils.getWaterLevel(hull.Position)
	if waterY then
		targetDepthY = math.min(targetDepthY, waterY)
	end

	local vy = math.clamp((targetDepthY - hull.Position.Y) * DEPTH_KP, -depthChangeSpeed, depthChangeSpeed)
	depthVelocity.VectorVelocity = Vector3.new(0, vy, 0)

	-- Rotors
	if #rotorEntries > 0 then
		rotorAngle = (rotorAngle + math.abs(throttle) * ROTOR_MAX_SPEED * dt) % ROTOR_ANGLE_WRAP
		for _, entry in rotorEntries do
			local axis = entry.Axis
			entry.Motor.Transform = CFrame.Angles(axis.X * rotorAngle, axis.Y * rotorAngle, axis.Z * rotorAngle)
		end
	end
end

local function deactivate()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	Input.disable()

	HelpUI.clearRole(model)

	surgeVelocity.VectorVelocity = Vector3.zero
	yawVelocity.AngularVelocity = Vector3.zero
	depthVelocity.VectorVelocity = Vector3.zero
	currentSurgeSpeed = 0
	currentYawSpeed = 0
	currentTargetPitch = 0
end

local function activate()
	if heartbeatConn then return end

	currentSurgeSpeed = 0
	currentYawSpeed = 0
	currentTargetPitch = 0
	targetDepthY = hull.Position.Y

	Input.enable(seat, model)

	HelpUI.applyRole(model, "WaterSubmersible", "HelpUI_DriverState")

	heartbeatConn = RunService.Heartbeat:Connect(update)
end

local function onOccupantChanged()
	if isDriver() then
		activate()
	else
		deactivate()
	end
end

-- Init

seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
onOccupantChanged()

end
`
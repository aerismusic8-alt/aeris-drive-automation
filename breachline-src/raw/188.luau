--[[
	File: Physics.luau
]]--

-- Root

local Physics = {}

-- Roblox Services

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Constants

local PITCH_TARGET_BOOST = 0.5
local MAX_TARGET_RATIO = 1.5
local THROTTLE_RAMP_FRACTION = 0.25
local GROUND_CLEARANCE_RAYCAST_LENGTH = 20
local ANTI_STALL_SPEED_BUFFER = 5

-- Module State

local active = false
local targetSpeed = 0
local currentSpeed = 0
local cachedRoot: BasePart? = nil
local cachedSurge: LinearVelocity? = nil
local cachedLift: VectorForce? = nil
local cachedOrientation: AngularVelocity? = nil
local cachedPerformance: { [string]: number }? = nil
local cachedPlaneModel: Model? = nil

-- Public Functions

function Physics.enable(
	root: BasePart,
	planeModel: Model,
	surgeVelocity: LinearVelocity,
	liftForce: VectorForce,
	orientationAngularVelocity: AngularVelocity,
	performance: { [string]: number }
)
	if active then return end
	active = true

	cachedRoot = root
	cachedPlaneModel = planeModel
	cachedSurge = surgeVelocity
	cachedLift = liftForce
	cachedOrientation = orientationAngularVelocity
	cachedPerformance = performance
	targetSpeed = 0
	currentSpeed = 0
end

function Physics.disable()
	if not active then return end
	active = false

	if cachedSurge then
		cachedSurge.MaxAxesForce = Vector3.zero
		cachedSurge.VectorVelocity = Vector3.zero
	end

	if cachedOrientation then
		cachedOrientation.MaxTorque = 0
		cachedOrientation.AngularVelocity = Vector3.zero
	end

	if cachedLift then
		cachedLift.Force = Vector3.zero
	end

	targetSpeed = 0
	currentSpeed = 0
	cachedRoot = nil
	cachedPlaneModel = nil
	cachedSurge = nil
	cachedLift = nil
	cachedOrientation = nil
	cachedPerformance = nil
end

function Physics.adjustTargetSpeed(delta: number)
	if not cachedPerformance then return end
	local maxSpeed = cachedPerformance.MaxSpeed
	targetSpeed = math.clamp(targetSpeed + delta, 0, maxSpeed)
end

function Physics.step(dt: number, inputs: InputState): (number, number)
	if not active then return 0, 0 end
	if dt <= 0 then return 0, 0 end

	local root = cachedRoot
	local surgeVelocity = cachedSurge
	local liftForce = cachedLift
	local orientationAngularVelocity = cachedOrientation
	local perf = cachedPerformance
	if not root or not surgeVelocity or not liftForce or not orientationAngularVelocity or not perf then
		return 0, 0
	end

	local pitchAlpha = inputs.PitchAlpha
	local rotAlpha = inputs.RotAlpha

	if not inputs.IsTouchCategory then
		local rampDelta = perf.MaxSpeed * THROTTLE_RAMP_FRACTION * dt
		if inputs.ThrottleUp then
			targetSpeed = math.min(perf.MaxSpeed, targetSpeed + rampDelta)
		elseif inputs.ThrottleDown then
			targetSpeed = math.max(0, targetSpeed - rampDelta)
		end
	end

	local pitchClampRad = math.rad(perf.PitchClampDegrees)
	local lookY = math.clamp(root.CFrame.LookVector.Y, -1, 1)
	local currentPitch = math.asin(lookY)
	if currentPitch >= pitchClampRad and pitchAlpha > 0 then
		pitchAlpha = 0
	elseif currentPitch <= -pitchClampRad and pitchAlpha < 0 then
		pitchAlpha = 0
	end

	local pitchFactor = -lookY
	local effectiveTarget = math.clamp(
		targetSpeed + pitchFactor * perf.MaxSpeed * PITCH_TARGET_BOOST,
		0,
		perf.MaxSpeed * MAX_TARGET_RATIO
	)

	local highClearance = false
	local planeModel = cachedPlaneModel
	if planeModel then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local filter: { Instance } = { planeModel }
		local localPlayer = Players.LocalPlayer
		local character = if localPlayer then localPlayer.Character else nil
		if character then
			table.insert(filter, character)
		end

		params.FilterDescendantsInstances = filter
		params.IgnoreWater = false
		-- A non-collidable overlay is not terrain the plane can hit, so letting one
		-- register as ground here would cancel anti-stall while genuinely high up.
		params.RespectCanCollide = true
		local hit = Workspace:Raycast(
			root.Position,
			Vector3.new(0, -GROUND_CLEARANCE_RAYCAST_LENGTH, 0),
			params
		)
		highClearance = hit == nil
	end

	if highClearance then
		local minSpeed = perf.StallSpeed + ANTI_STALL_SPEED_BUFFER
		targetSpeed = math.max(targetSpeed, minSpeed)
		effectiveTarget = math.max(effectiveTarget, minSpeed)
		currentSpeed = math.max(currentSpeed, minSpeed)
	end

	local speedDelta = perf.Acceleration * dt
	if currentSpeed < effectiveTarget then
		currentSpeed = math.min(effectiveTarget, currentSpeed + speedDelta)
	elseif currentSpeed > effectiveTarget then
		currentSpeed = math.max(effectiveTarget, currentSpeed - speedDelta)
	end

	local stallSpeed = perf.StallSpeed
	local halfStall = stallSpeed * 0.5
	local stallFactor: number
	if currentSpeed >= stallSpeed then
		stallFactor = 1
	elseif currentSpeed >= halfStall then
		stallFactor = (currentSpeed - halfStall) / math.max(halfStall, 1e-3)
	else
		stallFactor = 0
	end

	local lookV = root.CFrame.LookVector
	local yForce = if stallFactor >= 1 then math.huge else 0
	surgeVelocity.MaxAxesForce = Vector3.new(math.huge, yForce, math.huge)
	surgeVelocity.VectorVelocity = lookV * currentSpeed

	orientationAngularVelocity.MaxTorque = if stallFactor > 0 then math.huge else 0
	local pitchRate = pitchAlpha * math.rad(perf.PitchRate) * stallFactor
	local yawRate = rotAlpha * math.rad(perf.TurnRate)
	local desiredRightY = math.sin(rotAlpha * math.rad(perf.MaxBankDegrees))
	local rollRate = (desiredRightY - root.CFrame.RightVector.Y) * Constants.ROLL_LEVEL_GAIN * stallFactor
	local worldYaw = Vector3.yAxis * yawRate
	local horizontalRight = lookV:Cross(Vector3.yAxis)
	local pitchAxis = if horizontalRight.Magnitude > 1e-3 then horizontalRight.Unit else root.CFrame.RightVector
	local worldPitch = pitchAxis * pitchRate
	local worldRoll = -root.CFrame.LookVector * rollRate
	orientationAngularVelocity.AngularVelocity = worldYaw + worldPitch + worldRoll

	local mass = root.AssemblyMass
	local gravity = Workspace.Gravity
	local speedAboveStall = math.max(0, currentSpeed - stallSpeed)
	local speedRange = math.max(perf.MaxSpeed - stallSpeed, 1e-3)
	local pitchCurve = lookY * lookY * lookY
	local pitchLiftAdjust = pitchCurve * (speedAboveStall / speedRange) * Constants.PITCH_LIFT_MULTIPLIER
	liftForce.Force = Vector3.new(0, mass * gravity * (stallFactor + pitchLiftAdjust), 0)

	local maxSpeed = math.max(perf.MaxSpeed, 1e-3)
	local speedRatio = currentSpeed / maxSpeed
	local throttleRatio = targetSpeed / maxSpeed
	root:SetAttribute("Throttle", throttleRatio)
	return speedRatio, throttleRatio
end

-- Types

export type InputState = {
	PitchAlpha: number,
	RotAlpha: number,
	ThrottleUp: boolean,
	ThrottleDown: boolean,
	IsTouchCategory: boolean,
}

-- Return

return Physics

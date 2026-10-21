--[[
	File: Physics.luau
]]--

-- Root

local Physics = {}

-- Dependencies

local Constants = require(script.Parent.Constants)
local Camera = require(script.Parent.Camera)

-- Constants

local INPUT_EPSILON = 1e-3

-- Module State

local active = false
local cachedRoot: BasePart? = nil
local cachedBodyVelocity: LinearVelocity? = nil
local cachedBodyOrientation: AlignOrientation? = nil
local cachedPerformance: { [string]: number }? = nil

local headingFrame = CFrame.identity
local forwardCurrent = 0
local strafeCurrent = 0
local visualPitch = 0
local visualRoll = 0
local targetY = 0

-- Local Functions

local function rampToward(current: number, target: number, rate: number, dt: number): number
	local delta = rate * dt
	if current < target then
		return math.min(target, current + delta)
	elseif current > target then
		return math.max(target, current - delta)
	end
	return current
end

local function lerpAngle(current: number, target: number, rate: number, dt: number): number
	local alpha = 1 - math.exp(-rate * dt)
	return current + (target - current) * alpha
end

local function capCombined(forwardTarget: number, strafeTarget: number, cap: number): (number, number)
	local mag = math.sqrt(forwardTarget * forwardTarget + strafeTarget * strafeTarget)
	if mag <= cap or mag < INPUT_EPSILON then
		return forwardTarget, strafeTarget
	end
	local scale = cap / mag
	return forwardTarget * scale, strafeTarget * scale
end

local function buildHeadingFrame(lookV: Vector3): CFrame
	local yaw = math.atan2(-lookV.X, -lookV.Z)
	local pitch = math.asin(math.clamp(lookV.Y, -1, 1))
	return CFrame.fromAxisAngle(Vector3.yAxis, yaw) * CFrame.fromAxisAngle(Vector3.xAxis, pitch)
end

local function slerpToward(current: CFrame, target: CFrame, maxRad: number): CFrame
	if maxRad <= 0 then return current end
	local delta = current:Inverse() * target
	local _, angle = delta:ToAxisAngle()
	if angle < 1e-4 then return target end
	local t = math.min(1, maxRad / angle)
	return current:Lerp(target, t)
end

-- Public Functions

function Physics.enable(
	root: BasePart,
	bodyVelocity: LinearVelocity,
	bodyOrientation: AlignOrientation,
	performance: { [string]: number }
)
	if active then return end
	active = true

	cachedRoot = root
	cachedBodyVelocity = bodyVelocity
	cachedBodyOrientation = bodyOrientation
	cachedPerformance = performance

	headingFrame = buildHeadingFrame(root.CFrame.LookVector)
	forwardCurrent = 0
	strafeCurrent = 0
	visualPitch = 0
	visualRoll = 0
	targetY = root.Position.Y
end

function Physics.disable()
	if not active then return end
	active = false

	cachedRoot = nil
	cachedBodyVelocity = nil
	cachedBodyOrientation = nil
	cachedPerformance = nil

	headingFrame = CFrame.identity
	forwardCurrent = 0
	strafeCurrent = 0
	visualPitch = 0
	visualRoll = 0
	targetY = 0
end

function Physics.step(dt: number, inputs: InputState): (number, number)
	if not active then return 0, 0 end
	if dt <= 0 then return 0, 0 end

	local root = cachedRoot
	local bodyVelocity = cachedBodyVelocity
	local bodyOrientation = cachedBodyOrientation
	local perf = cachedPerformance
	if not root or not bodyVelocity or not bodyOrientation or not perf then
		return 0, 0
	end

	local forwardInput = math.clamp(inputs.ForwardInput, -1, 1)
	local strafeInput = math.clamp(inputs.StrafeInput, -1, 1)
	local collectiveInput = math.clamp(inputs.CollectiveInput, -1, 1)

	local targetYaw, targetPitch = Camera.getDesiredHeading()
	local flatLook = Vector3.new(-math.sin(targetYaw), 0, -math.cos(targetYaw)).Unit
	local right = flatLook:Cross(Vector3.yAxis)
	if right.Magnitude > 1e-4 then
		right = right.Unit
	else
		right = Vector3.xAxis
	end

	local forwardTarget = forwardInput * perf.MaxSpeed
	local strafeTarget = strafeInput * perf.MaxSpeed

	if math.abs(forwardInput) > INPUT_EPSILON and math.abs(strafeInput) > INPUT_EPSILON then
		forwardTarget, strafeTarget = capCombined(forwardTarget, strafeTarget, perf.MaxSpeed)
	end

	forwardCurrent = rampToward(forwardCurrent, forwardTarget, perf.Acceleration, dt)
	strafeCurrent = rampToward(strafeCurrent, strafeTarget, perf.Acceleration, dt)

	targetY += collectiveInput * perf.AltitudeChangeRate * dt
	local altitudeMaxVel = perf.AltitudeChangeRate * Constants.ALTITUDE_MAX_VEL_MULT
	local verticalError = targetY - root.Position.Y
	local vy = math.clamp(verticalError * Constants.ALTITUDE_HOLD_GAIN, -altitudeMaxVel, altitudeMaxVel)

	bodyVelocity.VectorVelocity = flatLook * forwardCurrent + right * strafeCurrent + Vector3.yAxis * vy

	local targetFrame = CFrame.fromAxisAngle(Vector3.yAxis, targetYaw)
		* CFrame.fromAxisAngle(Vector3.xAxis, targetPitch)
	local maxRad = math.rad(perf.LookRate) * dt
	headingFrame = slerpToward(headingFrame, targetFrame, maxRad)

	local pitchScale = 1 - math.abs(targetPitch) / (math.pi * 0.5)
	pitchScale = math.clamp(pitchScale, 0, 1)

	local maxTiltRad = math.rad(Constants.MAX_TILT_DEGREES)
	local pitchTarget = -(forwardCurrent / math.max(perf.MaxSpeed, 1e-3)) * maxTiltRad * pitchScale
	local rollTarget = -(strafeCurrent / math.max(perf.MaxSpeed, 1e-3)) * maxTiltRad
	visualPitch = lerpAngle(visualPitch, pitchTarget, Constants.TILT_LERP_RATE, dt)
	visualRoll = lerpAngle(visualRoll, rollTarget, Constants.TILT_LERP_RATE, dt)

	bodyOrientation.CFrame = headingFrame * CFrame.Angles(visualPitch, 0, visualRoll)

	local horizontalSpeed = math.sqrt(forwardCurrent * forwardCurrent + strafeCurrent * strafeCurrent)
	local speedRatio = math.clamp(horizontalSpeed / math.max(perf.MaxSpeed, 1e-3), 0, 1)

	local intensityRatio = math.max(
		math.abs(forwardCurrent) / math.max(perf.MaxSpeed, 1e-3),
		math.abs(strafeCurrent) / math.max(perf.MaxSpeed, 1e-3),
		math.abs(vy) / math.max(altitudeMaxVel, 1e-3)
	)
	intensityRatio = math.clamp(intensityRatio, 0, 1)

	return intensityRatio, speedRatio
end

-- Types

export type InputState = {
	ForwardInput: number,
	StrafeInput: number,
	CollectiveInput: number,
	IsTouchCategory: boolean,
}

-- Return

return Physics

--[[
	File: Physics.luau
]]--

-- Root

local Physics = {}

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Constants

local INPUT_EPSILON = 1e-3

-- Module State

local active = false
local cachedRoot: BasePart? = nil
local cachedBodyVelocity: LinearVelocity? = nil
local cachedBodyOrientation: AlignOrientation? = nil
local cachedPerformance: { [string]: number }? = nil

local headingYaw = 0
local headingPitch = 0
local forwardCurrent = 0
local strafeCurrent = 0
local verticalCurrent = 0
local visualPitch = 0
local visualRoll = 0

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

local function readHeadingFromRoot(root: BasePart): number
	local lookV = root.CFrame.LookVector
	return math.atan2(-lookV.X, -lookV.Z)
end

local function readPitchFromRoot(root: BasePart): number
	local lookV = root.CFrame.LookVector
	return math.asin(math.clamp(lookV.Y, -1, 1))
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

	headingYaw = readHeadingFromRoot(root)
	headingPitch = readPitchFromRoot(root)
	forwardCurrent = 0
	strafeCurrent = 0
	verticalCurrent = 0
	visualPitch = 0
	visualRoll = 0
end

function Physics.disable()
	if not active then return end
	active = false

	cachedRoot = nil
	cachedBodyVelocity = nil
	cachedBodyOrientation = nil
	cachedPerformance = nil

	headingYaw = 0
	headingPitch = 0
	forwardCurrent = 0
	strafeCurrent = 0
	verticalCurrent = 0
	visualPitch = 0
	visualRoll = 0
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
	local yawAlpha = math.clamp(inputs.YawAlpha, -1, 1)
	local pitchAlpha = math.clamp(inputs.PitchAlpha, -1, 1)

	local forwardTarget = forwardInput * perf.MaxSpeedLateral
	local strafeTarget = strafeInput * perf.MaxSpeedStrafe
	local verticalTarget = collectiveInput * perf.MaxCollective

	if math.abs(forwardInput) > INPUT_EPSILON and math.abs(strafeInput) > INPUT_EPSILON then
		local combinedCap = (perf.MaxSpeedLateral + perf.MaxSpeedStrafe) * 0.5
		forwardTarget, strafeTarget = capCombined(forwardTarget, strafeTarget, combinedCap)
	end

	forwardCurrent = rampToward(forwardCurrent, forwardTarget, perf.Acceleration, dt)
	strafeCurrent = rampToward(strafeCurrent, strafeTarget, perf.Acceleration, dt)
	verticalCurrent = rampToward(verticalCurrent, verticalTarget, perf.CollectiveRate, dt)

	headingYaw += yawAlpha * math.rad(perf.YawRate) * dt

	local headingFrame = CFrame.fromAxisAngle(Vector3.yAxis, headingYaw)
	local headingForward = headingFrame.LookVector
	local headingRight = headingForward:Cross(Vector3.yAxis)
	if headingRight.Magnitude > 1e-4 then
		headingRight = headingRight.Unit
	else
		headingRight = Vector3.xAxis
	end

	local rollTarget = -(strafeCurrent / math.max(perf.MaxSpeedStrafe, 1e-3)) * math.rad(perf.MaxVisualRollDegrees)
	visualRoll = lerpAngle(visualRoll, rollTarget, Constants.TILT_LERP_RATE, dt)

	if perf.PitchFollow then
		local maxPitch = math.rad(perf.MaxPitchFollowDegrees)
		headingPitch = math.clamp(headingPitch + pitchAlpha * math.rad(perf.PitchRate) * dt, -maxPitch, maxPitch)

		local orientFrame = headingFrame * CFrame.fromAxisAngle(Vector3.xAxis, headingPitch)
		local flightForward = orientFrame.LookVector

		bodyVelocity.VectorVelocity = flightForward * forwardCurrent
			+ headingRight * strafeCurrent
			+ Vector3.yAxis * verticalCurrent

		bodyOrientation.CFrame = orientFrame * CFrame.Angles(0, 0, visualRoll)
	else
		local pitchTarget = -(forwardCurrent / math.max(perf.MaxSpeedLateral, 1e-3)) * math.rad(perf.MaxVisualPitchDegrees)
		visualPitch = lerpAngle(visualPitch, pitchTarget, Constants.TILT_LERP_RATE, dt)

		bodyVelocity.VectorVelocity = headingForward * forwardCurrent
			+ headingRight * strafeCurrent
			+ Vector3.yAxis * verticalCurrent

		bodyOrientation.CFrame = headingFrame * CFrame.Angles(visualPitch, 0, visualRoll)
	end

	local horizontalSpeed = math.sqrt(forwardCurrent * forwardCurrent + strafeCurrent * strafeCurrent)
	local maxHorizontal = math.max(perf.MaxSpeedLateral, perf.MaxSpeedStrafe, 1e-3)
	local speedRatio = math.clamp(horizontalSpeed / maxHorizontal, 0, 1)

	local intensityRatio = math.max(
		math.abs(forwardCurrent) / math.max(perf.MaxSpeedLateral, 1e-3),
		math.abs(strafeCurrent) / math.max(perf.MaxSpeedStrafe, 1e-3),
		math.abs(verticalCurrent) / math.max(perf.MaxCollective, 1e-3),
		math.abs(yawAlpha)
	)
	intensityRatio = math.clamp(intensityRatio, 0, 1)

	return intensityRatio, speedRatio
end

-- Types

export type InputState = {
	ForwardInput: number,
	StrafeInput: number,
	CollectiveInput: number,
	YawAlpha: number,
	PitchAlpha: number,
	IsTouchCategory: boolean,
}

-- Return

return Physics

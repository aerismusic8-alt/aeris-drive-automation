--[[
	File: Camera.luau

	Shared chase camera used by Plane and Rotor SubType controllers. Only one
	vehicle can be mounted at a time, so the module-level state is safe to share
	between the two cloned-script controllers.
]]--

-- Root

local Camera = {}

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local GeometryUtils = require(FourD.Common.GeometryUtils)
local InputConstants = require(script.Parent.InputConstants)

-- Constants

local FOCUS_FORWARD_OFFSET = 5
local CAMERA_BIND_NAME = "AirVehicleCameraStep"
local BASE_FOV = 70
local MAX_SPEED_EXTRA_FOV = 10
local FOV_SPEED_RATIO_START = 0.25
local FOV_SPEED_RATIO_END = 1.0
local FOV_LERP_RATE = 6

-- Module State

local active = false
local renderStepBound = false
local cameraYaw = 0
local cameraPitch = 0
local cameraInitialized = false
local freeRotateActive = false
local freeRotateYawTarget = 0
local freeRotatePitchTarget = 0
local freeRotateYawCurrent = 0
local freeRotatePitchCurrent = 0
local cachedPerformance: { [string]: number }? = nil
local cachedRoot: BasePart? = nil
local cachedBackExtent = 0
local previousCameraType: Enum.CameraType? = nil
local cameraZoomBase = 0
local cameraZoomMax = 0
local cameraZoomCurrent = 0
local cachedSpeedRatio = 0
local fovCurrent = BASE_FOV
local previousFov: number? = nil

-- Local Functions

local function expDecay(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function clampAngle(value: number, maxRad: number): number
	return math.clamp(value, -maxRad, maxRad)
end

local function updateStep(dt: number)
	if not active then return end
	if not cachedRoot then return end
	if not cachedPerformance then return end

	local root = cachedRoot
	local perf = cachedPerformance
	local lookV = root.CFrame.LookVector
	local targetYaw = math.atan2(-lookV.X, -lookV.Z)
	local targetPitch = math.asin(math.clamp(lookV.Y, -1, 1))

	if not cameraInitialized then
		cameraYaw = targetYaw
		cameraPitch = targetPitch
		cameraInitialized = true
	else
		local yawDelta = ((targetYaw - cameraYaw + math.pi) % (2 * math.pi)) - math.pi
		local yawAlpha = expDecay(InputConstants.CAMERA_YAW_SMOOTH_RATE, dt)
		local pitchAlpha = expDecay(InputConstants.CAMERA_PITCH_SMOOTH_RATE, dt)
		cameraYaw += yawDelta * yawAlpha
		cameraPitch += (targetPitch - cameraPitch) * pitchAlpha
	end

	if not freeRotateActive then
		local returnAlpha = expDecay(InputConstants.FREE_ROTATE_RETURN_RATE, dt)
		freeRotateYawTarget += (0 - freeRotateYawTarget) * returnAlpha
		freeRotatePitchTarget += (0 - freeRotatePitchTarget) * returnAlpha
	end

	local smoothAlpha = expDecay(InputConstants.FREE_ROTATE_INPUT_SMOOTH_RATE, dt)
	freeRotateYawCurrent += (freeRotateYawTarget - freeRotateYawCurrent) * smoothAlpha
	freeRotatePitchCurrent += (freeRotatePitchTarget - freeRotatePitchCurrent) * smoothAlpha

	local orbitYaw = cameraYaw + freeRotateYawCurrent
	local orbitPitch = cameraPitch + freeRotatePitchCurrent

	local chaseCFrame = CFrame.new(root.Position)
		* CFrame.fromAxisAngle(Vector3.yAxis, orbitYaw)
		* CFrame.fromAxisAngle(Vector3.xAxis, orbitPitch)
	local lookOffset = chaseCFrame.LookVector
	local camera = Workspace.CurrentCamera
	local camPos = chaseCFrame.Position
		- lookOffset * (cameraZoomCurrent + cachedBackExtent)
		+ Vector3.new(0, perf.CameraHeight, 0)
	local focusPoint = root.Position + lookOffset * (cachedBackExtent + FOCUS_FORWARD_OFFSET)
	camera.CFrame = CFrame.lookAt(camPos, focusPoint)

	local mapped = (cachedSpeedRatio - FOV_SPEED_RATIO_START)
		/ (FOV_SPEED_RATIO_END - FOV_SPEED_RATIO_START)
	mapped = math.clamp(mapped, 0, 1)
	local fovTarget = math.clamp(
		BASE_FOV + MAX_SPEED_EXTRA_FOV * mapped,
		BASE_FOV,
		BASE_FOV + MAX_SPEED_EXTRA_FOV
	)
	local fovAlpha = expDecay(FOV_LERP_RATE, dt)
	fovCurrent += (fovTarget - fovCurrent) * fovAlpha
	camera.FieldOfView = fovCurrent
end

-- Public Functions

function Camera.enable(vehicleModel: Model, root: BasePart, performance: { [string]: number })
	if active then return end
	active = true

	local _, bodySize = GeometryUtils.getBodyBounds(vehicleModel)
	cachedBackExtent = bodySize.Z * 0.5
	cachedRoot = root
	cachedPerformance = performance
	cameraZoomBase = performance.CameraDistance
	cameraZoomMax = performance.CameraDistance * 1.5
	cameraZoomCurrent = cameraZoomBase
	cameraInitialized = false
	freeRotateActive = false
	freeRotateYawTarget = 0
	freeRotatePitchTarget = 0
	freeRotateYawCurrent = 0
	freeRotatePitchCurrent = 0

	local camera = Workspace.CurrentCamera
	previousCameraType = camera.CameraType
	previousFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	cachedSpeedRatio = 0
	fovCurrent = BASE_FOV
	camera.FieldOfView = BASE_FOV

	RunService:BindToRenderStep(CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, updateStep)
	renderStepBound = true
end

function Camera.disable()
	if not active then return end
	active = false

	if renderStepBound then
		RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
		renderStepBound = false
	end

	local camera = Workspace.CurrentCamera
	camera.CameraType = previousCameraType or Enum.CameraType.Custom
	camera.FieldOfView = previousFov or BASE_FOV
	previousCameraType = nil
	previousFov = nil
	cachedSpeedRatio = 0

	cachedRoot = nil
	cachedPerformance = nil
	freeRotateActive = false
end

function Camera.setFreeRotateActive(value: boolean)
	freeRotateActive = value
end

function Camera.isFreeRotateActive(): boolean
	return freeRotateActive
end

function Camera.applyManualRotateDelta(yawDeltaRad: number, pitchDeltaRad: number)
	if not freeRotateActive then return end
	local maxYaw = math.rad(InputConstants.FREE_ROTATE_MAX_YAW_DEGREES)
	local maxPitch = math.rad(InputConstants.FREE_ROTATE_MAX_PITCH_DEGREES)
	freeRotateYawTarget = clampAngle(freeRotateYawTarget + yawDeltaRad, maxYaw)
	freeRotatePitchTarget = clampAngle(freeRotatePitchTarget + pitchDeltaRad, maxPitch)
end

function Camera.applyZoomDelta(scrollDelta: number)
	if not active then return end
	if cameraZoomBase <= 0 then return end
	local step = cameraZoomBase * InputConstants.MOUSE_WHEEL_ZOOM_FRACTION
	cameraZoomCurrent = math.clamp(
		cameraZoomCurrent - scrollDelta * step,
		cameraZoomBase,
		cameraZoomMax
	)
end

function Camera.setSpeedRatio(speedRatio: number)
	cachedSpeedRatio = math.clamp(speedRatio, 0, 1)
end

Players.LocalPlayer.CharacterAdded:Connect(function()
	Camera.disable()
end)

-- Return

return Camera

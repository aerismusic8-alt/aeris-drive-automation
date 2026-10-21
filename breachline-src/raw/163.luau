--[[
	File: Camera.luau

	Jetpack-specific chase camera. The camera is mouse-driven the entire time
	the jetpack is mounted; the body slerps toward `getDesiredHeading()` at
	`LookRate` deg/s. Holding the free-rotate bind freezes the body heading
	while the camera continues to rotate with input; releasing it springs the
	camera back to align with the frozen body heading.
]]--

-- Root

local Camera = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local GeometryUtils = require(FourD.Common.GeometryUtils)

local Constants = require(script.Parent.Constants)

-- Constants

local FOCUS_FORWARD_OFFSET = 5
local MAX_PITCH_RAD = math.rad(Constants.MAX_PITCH_DEGREES)
local SPRING_EPSILON = 1e-3

-- Module State

local active = false
local renderStepBound = false
local cachedRoot: BasePart? = nil
local cachedBackExtent = 0
local previousCameraType: Enum.CameraType? = nil
local previousMouseIconEnabled: boolean? = nil

local cameraYaw = 0
local cameraPitch = 0

local bodyDecoupled = false
local decoupleBodyYaw = 0
local decoupleBodyPitch = 0

local springing = false
local springTargetYaw = 0
local springTargetPitch = 0

local cameraZoomBase = 0
local cameraZoomMax = 0
local cameraZoomCurrent = 0

-- Local Functions

local function expDecay(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function shortestYawDelta(target: number, current: number): number
	return ((target - current + math.pi) % (2 * math.pi)) - math.pi
end

local function seedFromRoot(root: BasePart)
	local lookV = root.CFrame.LookVector
	cameraYaw = math.atan2(-lookV.X, -lookV.Z)
	cameraPitch = math.asin(math.clamp(lookV.Y, -1, 1))
end

local function updateStep(dt: number)
	if not active then return end
	if not cachedRoot then return end

	local root = cachedRoot

	if springing then
		local alpha = expDecay(Constants.FREE_ROTATE_RETURN_RATE, dt)
		local yawDelta = shortestYawDelta(springTargetYaw, cameraYaw)
		local pitchDelta = springTargetPitch - cameraPitch
		cameraYaw += yawDelta * alpha
		cameraPitch += pitchDelta * alpha
		if math.abs(yawDelta) < SPRING_EPSILON and math.abs(pitchDelta) < SPRING_EPSILON then
			cameraYaw = springTargetYaw
			cameraPitch = springTargetPitch
			springing = false
		end
	end

	cameraPitch = math.clamp(cameraPitch, -MAX_PITCH_RAD, MAX_PITCH_RAD)

	local chaseCFrame = CFrame.new(root.Position)
		* CFrame.fromAxisAngle(Vector3.yAxis, cameraYaw)
		* CFrame.fromAxisAngle(Vector3.xAxis, cameraPitch)
	local lookOffset = chaseCFrame.LookVector
	local camera = Workspace.CurrentCamera
	local camPos = chaseCFrame.Position
		- lookOffset * (cameraZoomCurrent + cachedBackExtent)
	local focusPoint = root.Position + lookOffset * (cachedBackExtent + FOCUS_FORWARD_OFFSET)
	camera.CFrame = CFrame.lookAt(camPos, focusPoint)
end

-- Public Functions

function Camera.enable(vehicleModel: Model, root: BasePart, performance: { [string]: number })
	if active then return end
	active = true

	local _, bodySize = GeometryUtils.getBodyBounds(vehicleModel)
	cachedBackExtent = bodySize.Z * 0.5
	cachedRoot = root
	cameraZoomBase = performance.CameraDistance
	cameraZoomMax = performance.CameraDistance * 1.5
	cameraZoomCurrent = cameraZoomBase

	seedFromRoot(root)
	bodyDecoupled = false
	decoupleBodyYaw = cameraYaw
	decoupleBodyPitch = cameraPitch
	springing = false
	springTargetYaw = 0
	springTargetPitch = 0

	local camera = Workspace.CurrentCamera
	previousCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable

	previousMouseIconEnabled = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false

	RunService:BindToRenderStep(Constants.CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, updateStep)
	renderStepBound = true
end

function Camera.disable()
	if not active then return end
	active = false

	if renderStepBound then
		RunService:UnbindFromRenderStep(Constants.CAMERA_BIND_NAME)
		renderStepBound = false
	end

	local camera = Workspace.CurrentCamera
	camera.CameraType = previousCameraType or Enum.CameraType.Custom

	if previousMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = previousMouseIconEnabled
		previousMouseIconEnabled = nil
	end

	cachedRoot = nil
	bodyDecoupled = false
	springing = false
end

function Camera.applyLookDelta(yawDeltaRad: number, pitchDeltaRad: number)
	if not active then return end
	cameraYaw += yawDeltaRad
	cameraPitch = math.clamp(cameraPitch + pitchDeltaRad, -MAX_PITCH_RAD, MAX_PITCH_RAD)
end

function Camera.setBodyDecoupled(value: boolean)
	if not active then return end
	if value == bodyDecoupled then return end

	if value then
		decoupleBodyYaw = cameraYaw
		decoupleBodyPitch = cameraPitch
		springing = false
		bodyDecoupled = true
	else
		springTargetYaw = decoupleBodyYaw
		springTargetPitch = decoupleBodyPitch
		springing = true
		bodyDecoupled = false
	end
end

function Camera.isBodyDecoupled(): boolean
	return bodyDecoupled
end

function Camera.getDesiredHeading(): (number, number)
	if bodyDecoupled then
		return decoupleBodyYaw, decoupleBodyPitch
	end
	return cameraYaw, cameraPitch
end

function Camera.applyZoomDelta(scrollDelta: number)
	if not active then return end
	if cameraZoomBase <= 0 then return end
	local step = cameraZoomBase * Constants.MOUSE_WHEEL_ZOOM_FRACTION
	cameraZoomCurrent = math.clamp(
		cameraZoomCurrent - scrollDelta * step,
		cameraZoomBase,
		cameraZoomMax
	)
end

-- Return

return Camera

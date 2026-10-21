--[[
	File: ClientCamera.luau
]]--

-- Root

local ClientCamera = {}
ClientCamera.__index = ClientCamera

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local Constants = require(Firearm2.Common.Constants)
local Dumpster = require(FourD.Libs.Dumpster)

-- Constants

local GAMEPAD_DEAD_ZONE = 0.2
local GAMEPAD_RAD_PER_SECOND = 3.5
local HEAD_OFFSET_Y = 1.5
local RAD_PER_PIXEL = 0.005
local RENDER_STEP_NAME = "Firearm2_ClientCamera"

-- Local Functions

local function applyGamepadDeadZone(value: number): number
	if math.abs(value) < GAMEPAD_DEAD_ZONE then return 0 end
	local sign = if value < 0 then -1 else 1
	local rescaled = (math.abs(value) - GAMEPAD_DEAD_ZONE) / (1 - GAMEPAD_DEAD_ZONE)
	return sign * rescaled
end

local function pollGamepadDelta(): (number, number)
	local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	for _, input in state do
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			return applyGamepadDeadZone(input.Position.X), applyGamepadDeadZone(input.Position.Y)
		end
	end

	return 0, 0
end

-- Public Methods

function ClientCamera:SetAdsTarget(target: number)
	self._adsTarget = math.clamp(target, 0, 1)
end

function ClientCamera:GetAdsT(): number
	return self._adsT
end

function ClientCamera:SetRecoilOffset(pitch: number, yaw: number)
	self._recoilPitch = pitch
	self._recoilYaw = yaw
end

function ClientCamera:Step(deltaTime: number)
	if not self._dumpster then return end

	local isScopeMode = self._params.AimMode == Constants.AIM_MODE_SCOPE

	local aimSpeed = math.max(self._params.AimSpeed, Constants.MIN_AIM_SPEED)
	local step = deltaTime / aimSpeed
	if self._adsTarget > self._adsT then
		self._adsT = math.min(self._adsT + step, 1)
	elseif self._adsTarget < self._adsT then
		self._adsT = math.max(self._adsT - step, 0)
	end

	local mouseDelta = UserInputService:GetMouseDelta()
	local sensitivity = UserInputService.MouseDeltaSensitivity
	local gamepadX, gamepadY = pollGamepadDelta()
	self._yaw -= mouseDelta.X * sensitivity * RAD_PER_PIXEL
	self._pitch -= mouseDelta.Y * sensitivity * RAD_PER_PIXEL
	self._yaw -= gamepadX * GAMEPAD_RAD_PER_SECOND * deltaTime
	self._pitch -= gamepadY * GAMEPAD_RAD_PER_SECOND * deltaTime
	self._pitch = math.clamp(self._pitch, -Constants.PITCH_LIMIT_RAD, Constants.PITCH_LIMIT_RAD)

	local character = self._player.Character
	if not character then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position) * CFrame.Angles(0, self._yaw, 0)

	local effPitch = self._pitch + self._recoilPitch
	local effYaw = self._yaw + self._recoilYaw
	local headPosition = humanoidRootPart.Position + Vector3.new(0, HEAD_OFFSET_Y, 0)
	local headCF = CFrame.new(headPosition) * CFrame.Angles(0, effYaw, 0) * CFrame.Angles(effPitch, 0, 0)

	local zoom = Constants.OTS_ZOOM_DISTANCE * math.lerp(1, Constants.OTS_ADS_DISTANCE_MULT, self._adsT)
	local otsCF = headCF * CFrame.new(self._params.ShoulderOffset) * CFrame.new(0, 0, zoom)

	if isScopeMode then
		self._camera.CFrame = otsCF:Lerp(headCF, self._adsT)
		self._camera.FieldOfView = if self._adsT >= 1
			then self._originalFov / Constants.SCOPE_ZOOM
			else self._originalFov
		return
	end

	self._camera.CFrame = otsCF
	self._camera.FieldOfView = self._originalFov * math.lerp(1, Constants.OTS_ADS_FOV_MULT, self._adsT)
end

function ClientCamera:Enable()
	if self._dumpster then return end

	local dumpster = Dumpster.new()
	self._dumpster = dumpster

	local camera = workspace.CurrentCamera
	self._camera = camera

	local origCameraType = camera.CameraType
	local origFov = camera.FieldOfView
	local origCameraSubject = camera.CameraSubject
	self._originalFov = origFov
	dumpster:Add(function()
		camera.CameraType = origCameraType
		camera.FieldOfView = origFov
		camera.CameraSubject = origCameraSubject
	end)

	local player = self._player
	local origCameraMode = player.CameraMode
	local origCameraMinZoom = player.CameraMinZoomDistance
	local origCameraMaxZoom = player.CameraMaxZoomDistance
	dumpster:Add(function()
		player.CameraMode = origCameraMode
		player.CameraMinZoomDistance = origCameraMinZoom
		player.CameraMaxZoomDistance = origCameraMaxZoom
	end)

	local origMouseIconEnabled = UserInputService.MouseIconEnabled
	dumpster:Add(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = origMouseIconEnabled
	end)

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local origAutoRotate = humanoid.AutoRotate
			humanoid.AutoRotate = false
			self._humanoid = humanoid
			dumpster:Add(function()
				if humanoid.Parent then
					humanoid.AutoRotate = origAutoRotate
				end
			end)
		end
	end

	local lookVector = camera.CFrame.LookVector
	self._yaw = math.atan2(-lookVector.X, -lookVector.Z)
	self._pitch = math.clamp(
		math.asin(math.clamp(lookVector.Y, -1, 1)),
		-Constants.PITCH_LIMIT_RAD,
		Constants.PITCH_LIMIT_RAD
	)

	camera.CameraType = Enum.CameraType.Scriptable
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = Constants.OTS_ZOOM_DISTANCE
	player.CameraMaxZoomDistance = Constants.OTS_ZOOM_DISTANCE
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	dumpster:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value, function(deltaTime: number)
		if not self._dumpster then return end
		self:Step(deltaTime)
	end)
end

function ClientCamera:Disable()
	if not self._dumpster then return end

	local dumpster = self._dumpster
	self._dumpster = nil
	dumpster:Destroy()
	self._humanoid = nil
	self._recoilPitch = 0
	self._recoilYaw = 0
end

function ClientCamera:Destroy()
	self:Disable()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function ClientCamera.new(params: { [string]: any }): any
	local self = setmetatable({}, ClientCamera)
	self._player = Players.LocalPlayer
	self._params = params
	self._adsT = 0
	self._adsTarget = 0
	self._yaw = 0
	self._pitch = 0
	self._recoilPitch = 0
	self._recoilYaw = 0
	self._dumpster = nil
	self._camera = nil
	self._humanoid = nil
	self._originalFov = nil
	return self
end

-- Return

return ClientCamera

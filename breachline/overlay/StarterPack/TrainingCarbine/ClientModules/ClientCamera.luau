--[[
	File: ClientCamera.luau

	First-person camera for a firearm.

	The rig is unchanged from upstream: the camera and the shot ray share one
	head-centred direction, ADS is a time-lerped 0..1 value, and recoil is an
	offset applied on top. Three things are added for mobile.

	Look sensitivity is per-platform. A mouse and a thumb do not want the same
	number, and a thumb wants a second multiplier on top for the same reason a
	mouse has `MouseDeltaSensitivity` at all.

	Aim assist runs on touch only, and it is applied to the look delta before
	the camera is built, so the shot fired along `LookVector` is the assisted
	direction -- the server's direction check sees what the player sees.

	Crouch lowers the eye height. The flag lives on a player attribute so the
	input module can set it without the camera having to know about input.
]]--

-- Root

local ClientCamera = {}
ClientCamera.__index = ClientCamera

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function menuOpen()
	local match = playerGui:FindFirstChild("MatchHud")
	local buy = playerGui:FindFirstChild("BuyHud")
	local main = match and match:FindFirstChild("MainMenu")
	local shop = buy and buy:FindFirstChild("ShopPanel")
	return (main and main.Visible) or (shop and shop.Visible)
end

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local AimAssist = require(Firearm2.Common.AimAssist)
local Constants = require(Firearm2.Common.Constants)
local Dumpster = require(FourD.Libs.Dumpster)

-- Constants

local GAMEPAD_DEAD_ZONE = 0.2
local GAMEPAD_RAD_PER_SECOND = 3.5
local HEAD_OFFSET_Y = 1.5
local RAD_PER_PIXEL = 0.005
local RENDER_STEP_NAME = "Firearm2_ClientCamera"

-- The band of screen a touch drag steers the camera from: the right side,
-- below the score bar and above the button cluster.
local LOOK_MIN_X_FRACTION = 0.42
local LOOK_TOP_FRACTION = 0.18
local LOOK_BOTTOM_FRACTION = 0.62
local LOOK_TOP_MIN_PIXELS = 105

local DEFAULT_TOUCH_SENSITIVITY = Constants.DEFAULT_TOUCH_SENSITIVITY
local ADS_SENSITIVITY_SCALE = 0.65

local CROUCH_ATTRIBUTE = Constants.CROUCH_ATTRIBUTE
local SCOPE_ATTRIBUTE = "AXScope"

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

---0 when the assist is idle, 1 when it is fully engaged. The crosshair reads
---this to show the player the assist is helping.
function ClientCamera:GetAimFriction(): number
	if not self._assist then return 1 end
	return self._assist:GetFriction()
end

function ClientCamera:SetRecoilOffset(pitch: number, yaw: number)
	self._recoilPitch = pitch
	self._recoilYaw = yaw
end

function ClientCamera:Step(deltaTime: number)
	if not self._dumpster then return end
	if menuOpen() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		self._touchDelta = Vector2.zero
		return
	end
	if not UserInputService.TouchEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end

	local isScopeMode = self._params.AimMode == Constants.AIM_MODE_SCOPE

	local aimSpeed = math.max(self._params.AimSpeed, Constants.MIN_AIM_SPEED)
	local step = deltaTime / aimSpeed
	if self._adsTarget > self._adsT then
		self._adsT = math.min(self._adsT + step, 1)
	elseif self._adsTarget < self._adsT then
		self._adsT = math.max(self._adsT - step, 0)
	end

	local useTouch = UserInputService.TouchEnabled and (not UserInputService.MouseEnabled or self._activeTouch ~= nil)
	local mouseDelta = if useTouch then self._touchDelta else UserInputService:GetMouseDelta()
	self._touchDelta = Vector2.zero

	local sensitivity = UserInputService.MouseDeltaSensitivity
	if useTouch then
		sensitivity *= self._params.TouchSensitivity or DEFAULT_TOUCH_SENSITIVITY
	end
	if self._adsT > 0 then
		sensitivity *= ADS_SENSITIVITY_SCALE
	end

	local gamepadX, gamepadY = pollGamepadDelta()

	-- Look input, before assist. Direction is fixed here; assist only changes
	-- magnitude and then nudges.
	local yawDelta = -mouseDelta.X * sensitivity * RAD_PER_PIXEL
	local pitchDelta = -mouseDelta.Y * sensitivity * RAD_PER_PIXEL

	if self._assist then
		self._assist:Step(deltaTime, self._camera)
		yawDelta, pitchDelta = self._assist:ScaleLook(yawDelta, pitchDelta)

		local pullYaw, pullPitch = self._assist:GetPull(deltaTime, self._camera)
		yawDelta += pullYaw
		pitchDelta += pullPitch
	end

	self._yaw += yawDelta
	self._pitch += pitchDelta
	self._yaw -= gamepadX * GAMEPAD_RAD_PER_SECOND * deltaTime
	self._pitch -= gamepadY * GAMEPAD_RAD_PER_SECOND * deltaTime
	self._pitch = math.clamp(self._pitch, -Constants.PITCH_LIMIT_RAD, Constants.PITCH_LIMIT_RAD)

	local character = self._player.Character
	if not character then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position) * CFrame.Angles(0, self._yaw, 0)

	local eyeHeight = HEAD_OFFSET_Y
	if self._player:GetAttribute(CROUCH_ATTRIBUTE) == 1 then
		eyeHeight = Constants.CROUCH_HEAD_OFFSET_Y
	end

	local effPitch = self._pitch + self._recoilPitch
	local effYaw = self._yaw + self._recoilYaw
	local headPosition = humanoidRootPart.Position + Vector3.new(0, eyeHeight, 0)
	local headCF = CFrame.new(headPosition) * CFrame.Angles(0, effYaw, 0) * CFrame.Angles(effPitch, 0, 0)

	-- Camera and shot ray share the same head-centered direction.
	self._camera.CFrame = headCF

	-- Zoom. A weapon with a real optic magnifies while aiming. A weapon
	-- without one still gets a modest magnification when the player holds the
	-- scope control, which is the difference between an iron-sight carbine and
	-- a rifle you can actually take a long shot with.
	local wantsScope = self._player:GetAttribute(SCOPE_ATTRIBUTE) == 1
	if isScopeMode then
		self._camera.FieldOfView = self._originalFov / math.lerp(1, Constants.SCOPE_ZOOM, self._adsT)
	else
		local zoom = math.lerp(1, Constants.SCOPE_ZOOM_OTS, if wantsScope then self._adsT else 0)
		self._camera.FieldOfView = self._originalFov * math.lerp(1, Constants.OTS_ADS_FOV_MULT, self._adsT) / zoom
	end
end

function ClientCamera:Enable()
	if self._dumpster then return end

	local dumpster = Dumpster.new()
	self._dumpster = dumpster

	local camera = workspace.CurrentCamera
	self._camera = camera
	self._touchDelta = Vector2.zero
	self._activeTouch = nil

	local function touchAllowed(input, processed)
		local viewport = camera.ViewportSize
		local pos = input.Position
		local topEdge = math.min(LOOK_TOP_MIN_PIXELS, viewport.Y * LOOK_TOP_FRACTION)
		return not processed
			and not menuOpen()
			and pos.X > viewport.X * LOOK_MIN_X_FRACTION
			and pos.Y > topEdge
			and pos.Y < viewport.Y * LOOK_BOTTOM_FRACTION
	end

	dumpster:Add(UserInputService.TouchStarted:Connect(function(input, processed)
		if not self._activeTouch and touchAllowed(input, processed) then
			self._activeTouch = input
			self._lastTouch = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	dumpster:Add(UserInputService.TouchMoved:Connect(function(input)
		if input ~= self._activeTouch or menuOpen() then return end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		self._touchDelta += pos - self._lastTouch
		self._lastTouch = pos
	end))
	dumpster:Add(UserInputService.TouchEnded:Connect(function(input)
		if input == self._activeTouch then self._activeTouch = nil end
	end))

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
			local hidden = {}
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and (part.Name == "Head" or part:FindFirstAncestorOfClass("Accessory")) then
					hidden[part] = part.LocalTransparencyModifier
					part.LocalTransparencyModifier = 1
				end
			end
			dumpster:Add(function()
				for part, transparency in pairs(hidden) do
					if part.Parent then part.LocalTransparencyModifier = transparency end
				end
			end)
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
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
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

	-- Aim assist is a thumb affordance; a mouse or a stick does not want it.
	local assistParams = table.clone(params)
	if assistParams.AimAssist == nil then
		assistParams.AimAssist = UserInputService.TouchEnabled
	end
	self._assist = AimAssist.new(assistParams)
	return self
end

-- Return

return ClientCamera

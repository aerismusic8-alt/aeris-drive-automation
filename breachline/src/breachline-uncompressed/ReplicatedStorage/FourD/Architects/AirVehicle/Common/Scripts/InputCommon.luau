--[[
	File: InputCommon.luau

	Shared input helpers used by both Plane and Rotor SubType controllers:
	- pure deadzone + input-category helpers,
	- RMB-driven mouse free-rotate connections (yaw/pitch delta -> Camera),
	- gamepad-stick free-rotate (toggle button + RS-stick delta -> Camera).

	Module-level connection state is safe to share because only one vehicle can
	be mounted at a time.
]]--

-- Root

local InputCommon = {}

-- Roblox Services

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local UserSettingsService = UserSettings()

local userGameSettings = UserSettingsService:GetService("UserGameSettings")

-- Dependencies

local InputConstants = require(script.Parent.InputConstants)
local Camera = require(script.Parent.Camera)

-- Mouse Free-Rotate State

local mouseEnabled = false
local rmbDown = false
local previousMouseBehavior: Enum.MouseBehavior? = nil
local mouseInputBeganConnection: RBXScriptConnection? = nil
local mouseInputEndedConnection: RBXScriptConnection? = nil
local mouseInputChangedConnection: RBXScriptConnection? = nil

-- Gamepad Free-Rotate State

local gamepadEnabled = false
local gamepadInputBeganConnection: RBXScriptConnection? = nil
local gamepadSteppedConnection: RBXScriptConnection? = nil

-- Pure Helpers

function InputCommon.applyDeadzone(value: number, deadzone: number): number
	if math.abs(value) < deadzone then return 0 end
	local sign = math.sign(value)
	return sign * ((math.abs(value) - deadzone) / (1 - deadzone))
end

function InputCommon.categorizeInputType(inputType: Enum.UserInputType): string
	if string.find(inputType.Name, "Gamepad") then
		return InputConstants.INPUT_GAMEPAD
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return InputConstants.INPUT_KEYBOARD
	elseif inputType == Enum.UserInputType.Touch then
		return InputConstants.INPUT_TOUCH
	end

	return InputConstants.INPUT_UNKNOWN
end

function InputCommon.getDefaultInputCategory(): string
	local lastInput = InputCommon.categorizeInputType(UserInputService:GetLastInputType())
	if lastInput ~= InputConstants.INPUT_UNKNOWN then return lastInput end

	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return InputConstants.INPUT_TOUCH
	elseif UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		return InputConstants.INPUT_KEYBOARD
	elseif UserInputService.GamepadEnabled then
		return InputConstants.INPUT_GAMEPAD
	end

	return InputConstants.INPUT_UNKNOWN
end

-- Mouse Free-Rotate

local function setMouseLocked(locked: boolean)
	if locked then
		if previousMouseBehavior == nil then
			previousMouseBehavior = UserInputService.MouseBehavior
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	else
		if previousMouseBehavior then
			UserInputService.MouseBehavior = previousMouseBehavior
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		previousMouseBehavior = nil
	end
end

local function activateMouseFreeRotate()
	if rmbDown then return end
	rmbDown = true
	Camera.setFreeRotateActive(true)
	setMouseLocked(true)
end

local function deactivateMouseFreeRotate()
	if not rmbDown then return end
	rmbDown = false
	Camera.setFreeRotateActive(false)
	setMouseLocked(false)
end

local function onMouseInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		activateMouseFreeRotate()
	end
end

local function onMouseInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		deactivateMouseFreeRotate()
	end
end

local function onMouseInputChanged(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		Camera.applyZoomDelta(input.Position.Z)
		return
	end
	if not rmbDown then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	local delta = input.Delta
	local sensitivity = userGameSettings.MouseSensitivity
	local yawDelta = -delta.X * InputConstants.FREE_ROTATE_SENSITIVITY_YAW * sensitivity
	local pitchDelta = -delta.Y * InputConstants.FREE_ROTATE_SENSITIVITY_PITCH * sensitivity
	Camera.applyManualRotateDelta(yawDelta, pitchDelta)
end

function InputCommon.enableMouseFreeRotate()
	if mouseEnabled then return end
	mouseEnabled = true

	mouseInputBeganConnection = UserInputService.InputBegan:Connect(onMouseInputBegan)
	mouseInputEndedConnection = UserInputService.InputEnded:Connect(onMouseInputEnded)
	mouseInputChangedConnection = UserInputService.InputChanged:Connect(onMouseInputChanged)
end

function InputCommon.disableMouseFreeRotate()
	if not mouseEnabled then return end
	mouseEnabled = false

	if mouseInputBeganConnection then
		mouseInputBeganConnection:Disconnect()
		mouseInputBeganConnection = nil
	end
	if mouseInputEndedConnection then
		mouseInputEndedConnection:Disconnect()
		mouseInputEndedConnection = nil
	end
	if mouseInputChangedConnection then
		mouseInputChangedConnection:Disconnect()
		mouseInputChangedConnection = nil
	end

	deactivateMouseFreeRotate()
end

-- Gamepad Free-Rotate

local function readThumbstick(currentGamepad: Enum.UserInputType, key: Enum.KeyCode): (number, number)
	local state = UserInputService:GetGamepadState(currentGamepad)
	for _, inputObject in state do
		if inputObject.KeyCode == key then
			return inputObject.Position.X, inputObject.Position.Y
		end
	end
	return 0, 0
end

local function onGamepadInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.KeyCode == InputConstants.FREE_ROTATE_GAMEPAD_KEY then
		Camera.setFreeRotateActive(not Camera.isFreeRotateActive())
	end
end

local function onGamepadStepped(_time: number, dt: number)
	if not Camera.isFreeRotateActive() then return end

	local stickX, stickY = readThumbstick(Enum.UserInputType.Gamepad1, Enum.KeyCode.Thumbstick2)
	local deadzonedX = InputCommon.applyDeadzone(stickX, InputConstants.GAMEPAD_DEADZONE)
	local deadzonedY = InputCommon.applyDeadzone(stickY, InputConstants.GAMEPAD_DEADZONE)
	if deadzonedX == 0 and deadzonedY == 0 then return end

	local sensitivity = userGameSettings.GamepadCameraSensitivity
	local yawDelta = -deadzonedX * InputConstants.FREE_ROTATE_GAMEPAD_RATE_YAW * sensitivity * dt
	local pitchDelta = deadzonedY * InputConstants.FREE_ROTATE_GAMEPAD_RATE_PITCH * sensitivity * dt
	Camera.applyManualRotateDelta(yawDelta, pitchDelta)
end

function InputCommon.enableGamepadFreeRotate()
	if gamepadEnabled then return end
	gamepadEnabled = true

	gamepadInputBeganConnection = UserInputService.InputBegan:Connect(onGamepadInputBegan)
	gamepadSteppedConnection = RunService.Stepped:Connect(onGamepadStepped)
end

function InputCommon.disableGamepadFreeRotate()
	if not gamepadEnabled then return end
	gamepadEnabled = false

	if gamepadInputBeganConnection then
		gamepadInputBeganConnection:Disconnect()
		gamepadInputBeganConnection = nil
	end
	if gamepadSteppedConnection then
		gamepadSteppedConnection:Disconnect()
		gamepadSteppedConnection = nil
	end

	Camera.setFreeRotateActive(false)
end

function InputCommon.readThumbstick(currentGamepad: Enum.UserInputType, key: Enum.KeyCode): (number, number)
	return readThumbstick(currentGamepad, key)
end

-- Return

return InputCommon

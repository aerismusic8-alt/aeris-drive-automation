--[[
	File: KeyboardAndMouse.luau
]]--

-- Root

local KeyboardAndMouse = {}

-- Roblox Services

local UserInputService = game:GetService("UserInputService")
local UserSettingsService = UserSettings()

local userGameSettings = UserSettingsService:GetService("UserGameSettings")

-- Dependencies

local Constants = require(script.Parent.Parent.Constants)
local Camera = require(script.Parent.Parent.Camera)

-- Module State

local enabled = false
local previousMouseBehavior: Enum.MouseBehavior? = nil
local inputBeganConnection: RBXScriptConnection? = nil
local inputEndedConnection: RBXScriptConnection? = nil
local inputChangedConnection: RBXScriptConnection? = nil

-- Local Functions

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		Camera.setBodyDecoupled(true)
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		Camera.setBodyDecoupled(false)
	end
end

local function onInputChanged(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		Camera.applyZoomDelta(input.Position.Z)
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

	local delta = input.Delta
	local sensitivity = userGameSettings.MouseSensitivity
	local yawDelta = -delta.X * Constants.FREE_ROTATE_SENSITIVITY_YAW * sensitivity
	local pitchDelta = -delta.Y * Constants.FREE_ROTATE_SENSITIVITY_PITCH * sensitivity
	Camera.applyLookDelta(yawDelta, pitchDelta)
end

-- Public Functions

function KeyboardAndMouse.enable()
	if enabled then return end
	enabled = true

	previousMouseBehavior = UserInputService.MouseBehavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition

	inputBeganConnection = UserInputService.InputBegan:Connect(onInputBegan)
	inputEndedConnection = UserInputService.InputEnded:Connect(onInputEnded)
	inputChangedConnection = UserInputService.InputChanged:Connect(onInputChanged)
end

function KeyboardAndMouse.disable()
	if not enabled then return end
	enabled = false

	if inputBeganConnection then
		inputBeganConnection:Disconnect()
		inputBeganConnection = nil
	end
	if inputEndedConnection then
		inputEndedConnection:Disconnect()
		inputEndedConnection = nil
	end
	if inputChangedConnection then
		inputChangedConnection:Disconnect()
		inputChangedConnection = nil
	end

	UserInputService.MouseBehavior = previousMouseBehavior or Enum.MouseBehavior.Default
	previousMouseBehavior = nil

	Camera.setBodyDecoupled(false)
end

function KeyboardAndMouse.poll(): (number, number, number)
	local forwardInput = 0
	local strafeInput = 0
	local collectiveInput = 0

	if UserInputService:IsKeyDown(Constants.FORWARD_KEY) then
		forwardInput += 1
	end
	if UserInputService:IsKeyDown(Constants.REVERSE_KEY) then
		forwardInput -= 1
	end
	if UserInputService:IsKeyDown(Constants.STRAFE_RIGHT_KEY) then
		strafeInput += 1
	end
	if UserInputService:IsKeyDown(Constants.STRAFE_LEFT_KEY) then
		strafeInput -= 1
	end
	if UserInputService:IsKeyDown(Constants.ASCEND_KEY) then
		collectiveInput += 1
	end
	if UserInputService:IsKeyDown(Constants.DESCEND_KEY) then
		collectiveInput -= 1
	end

	return forwardInput, strafeInput, collectiveInput
end

-- Return

return KeyboardAndMouse

--[[
	File: Gamepad.luau
]]--

-- Root

local Gamepad = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local UserSettingsService = UserSettings()

local userGameSettings = UserSettingsService:GetService("UserGameSettings")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local InputCommon = require(FourD.Architects.AirVehicle.Common.Scripts.InputCommon)

local Constants = require(script.Parent.Parent.Constants)
local Camera = require(script.Parent.Parent.Camera)

-- Module State

local enabled = false
local inputBeganConnection: RBXScriptConnection? = nil
local steppedConnection: RBXScriptConnection? = nil

-- Local Functions

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.KeyCode == Constants.FREE_ROTATE_GAMEPAD_KEY then
		Camera.setBodyDecoupled(not Camera.isBodyDecoupled())
	end
end

local function onStepped(_time: number, dt: number)
	local stickX, stickY = InputCommon.readThumbstick(Enum.UserInputType.Gamepad1, Enum.KeyCode.Thumbstick2)
	local deadzonedX = InputCommon.applyDeadzone(stickX, Constants.GAMEPAD_DEADZONE)
	local deadzonedY = InputCommon.applyDeadzone(stickY, Constants.GAMEPAD_DEADZONE)
	if deadzonedX == 0 and deadzonedY == 0 then return end

	local sensitivity = userGameSettings.GamepadCameraSensitivity
	local yawDelta = -deadzonedX * Constants.FREE_ROTATE_GAMEPAD_RATE_YAW * sensitivity * dt
	local pitchDelta = deadzonedY * Constants.FREE_ROTATE_GAMEPAD_RATE_PITCH * sensitivity * dt
	Camera.applyLookDelta(yawDelta, pitchDelta)
end

-- Public Functions

function Gamepad.enable()
	if enabled then return end
	enabled = true

	inputBeganConnection = UserInputService.InputBegan:Connect(onInputBegan)
	steppedConnection = RunService.Stepped:Connect(onStepped)
end

function Gamepad.disable()
	if not enabled then return end
	enabled = false

	if inputBeganConnection then
		inputBeganConnection:Disconnect()
		inputBeganConnection = nil
	end
	if steppedConnection then
		steppedConnection:Disconnect()
		steppedConnection = nil
	end

	Camera.setBodyDecoupled(false)
end

function Gamepad.poll(currentGamepad: Enum.UserInputType): (number, number, number)
	local leftX, leftY = InputCommon.readThumbstick(currentGamepad, Enum.KeyCode.Thumbstick1)
	local strafeInput = InputCommon.applyDeadzone(leftX, Constants.GAMEPAD_DEADZONE)
	local forwardInput = InputCommon.applyDeadzone(leftY, Constants.GAMEPAD_DEADZONE)

	local collectiveInput = 0
	if UserInputService:IsKeyDown(Constants.ASCEND_GAMEPAD_KEY) then
		collectiveInput += 1
	end
	if UserInputService:IsKeyDown(Constants.DESCEND_GAMEPAD_KEY) then
		collectiveInput -= 1
	end

	return
		math.clamp(forwardInput, -1, 1),
		math.clamp(strafeInput, -1, 1),
		math.clamp(collectiveInput, -1, 1)
end

-- Return

return Gamepad

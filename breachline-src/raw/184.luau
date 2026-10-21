--[[
	File: Gamepad.luau
]]--

-- Root

local Gamepad = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local InputCommon = require(FourD.Architects.AirVehicle.Common.Scripts.InputCommon)

local Constants = require(script.Parent.Parent.Constants)
local Camera = require(script.Parent.Parent.Camera)

-- Public Functions

function Gamepad.enable()
	InputCommon.enableGamepadFreeRotate()
end

function Gamepad.disable()
	InputCommon.disableGamepadFreeRotate()
end

function Gamepad.poll(currentGamepad: Enum.UserInputType): (number, number)
	local pitchAlpha = 0
	local rotAlpha = 0
	local gamepadState = UserInputService:GetGamepadState(currentGamepad)

	for _, inputObject in gamepadState do
		if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			rotAlpha = InputCommon.applyDeadzone(inputObject.Position.X, Constants.GAMEPAD_DEADZONE)
		elseif inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
			pitchAlpha = InputCommon.applyDeadzone(-inputObject.Position.Y, Constants.GAMEPAD_DEADZONE)
		end
	end

	if Camera.isFreeRotateActive() then
		pitchAlpha = 0
	end

	return math.clamp(pitchAlpha, -1, 1), math.clamp(rotAlpha, -1, 1)
end

-- Return

return Gamepad

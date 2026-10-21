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

function Gamepad.poll(currentGamepad: Enum.UserInputType, pitchFollow: boolean?): (number, number, number, number, number)
	local leftX, leftY = InputCommon.readThumbstick(currentGamepad, Enum.KeyCode.Thumbstick1)
	local strafeInput = InputCommon.applyDeadzone(leftX, Constants.GAMEPAD_DEADZONE)
	local forwardInput = InputCommon.applyDeadzone(leftY, Constants.GAMEPAD_DEADZONE)

	local collectiveInput = 0
	local yawAlpha = 0
	local pitchAlpha = 0

	if pitchFollow then
		if UserInputService:IsKeyDown(Enum.KeyCode.ButtonA) then
			collectiveInput += 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.ButtonB) then
			collectiveInput -= 1
		end

		if not Camera.isFreeRotateActive() then
			local rightX, rightY = InputCommon.readThumbstick(currentGamepad, Enum.KeyCode.Thumbstick2)
			yawAlpha = InputCommon.applyDeadzone(-rightX, Constants.GAMEPAD_DEADZONE)
			pitchAlpha = InputCommon.applyDeadzone(rightY, Constants.GAMEPAD_DEADZONE)
		end
	elseif not Camera.isFreeRotateActive() then
		local rightX, rightY = InputCommon.readThumbstick(currentGamepad, Enum.KeyCode.Thumbstick2)
		yawAlpha = InputCommon.applyDeadzone(-rightX, Constants.GAMEPAD_DEADZONE)
		collectiveInput = InputCommon.applyDeadzone(rightY, Constants.GAMEPAD_DEADZONE)
	end

	return
		math.clamp(forwardInput, -1, 1),
		math.clamp(strafeInput, -1, 1),
		math.clamp(collectiveInput, -1, 1),
		math.clamp(yawAlpha, -1, 1),
		math.clamp(pitchAlpha, -1, 1)
end

-- Return

return Gamepad
S
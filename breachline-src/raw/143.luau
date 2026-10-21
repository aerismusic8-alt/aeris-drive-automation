--[[
	File: KeyboardAndMouse.luau
	Keyboard throttle/steering poll for WaterSubmersible. Mirrors PlayerDrivable._pollKeyboard.
]]--

-- Root

local KeyboardAndMouse = {}

-- Roblox Services

local UserInputService = game:GetService("UserInputService")

-- Constants

local FORWARD_KEYS = { Enum.KeyCode.W, Enum.KeyCode.Up }
local BACK_KEYS = { Enum.KeyCode.S, Enum.KeyCode.Down }
local LEFT_KEYS = { Enum.KeyCode.A, Enum.KeyCode.Left }
local RIGHT_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }

-- Local Functions

local function anyKeyDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- Public Functions

function KeyboardAndMouse.poll(): (number, number)
	local throttle = 0
	local steering = 0

	if anyKeyDown(FORWARD_KEYS) then throttle += 1 end
	if anyKeyDown(BACK_KEYS) then throttle -= 1 end
	if anyKeyDown(RIGHT_KEYS) then steering += 1 end
	if anyKeyDown(LEFT_KEYS) then steering -= 1 end

	return throttle, steering
end

-- Return

return KeyboardAndMouse
!
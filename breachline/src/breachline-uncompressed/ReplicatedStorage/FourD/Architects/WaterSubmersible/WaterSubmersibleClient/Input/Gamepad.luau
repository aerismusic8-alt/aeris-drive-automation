--[[
	File: Gamepad.luau
	Gamepad throttle/steering poll for WaterSubmersible. Mirrors PlayerDrivable._pollGamepad.
]]--

-- Root

local Gamepad = {}

-- Roblox Services

local UserInputService = game:GetService("UserInputService")

-- Constants

local STEERING_DEADZONE = 0.1

-- Public Functions

function Gamepad.poll(currentGamepad: Enum.UserInputType): (number, number)
	local throttle = 0
	local steering = 0
	local gamepadState = UserInputService:GetGamepadState(currentGamepad)

	for _, inputObject in gamepadState do
		if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = inputObject.Position.X
			if math.abs(x) > STEERING_DEADZONE then
				steering = ((math.abs(x) - STEERING_DEADZONE) / (1 - STEERING_DEADZONE)) * math.sign(x)
			end
		elseif inputObject.KeyCode == Enum.KeyCode.ButtonR2 then
			throttle += inputObject.Position.Z
		elseif inputObject.KeyCode == Enum.KeyCode.ButtonL2 then
			throttle -= inputObject.Position.Z
		end
	end

	return throttle, steering
end

-- Return

return Gamepad

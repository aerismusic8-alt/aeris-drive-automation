local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local disconnectAndClear = require(script.Parent.Parent.Parent.disconnectAndClear)

-- These variables have been pulled from the default camera scripts
local ROTATION_SPEED_GAMEPAD = Vector2.new(1, 0.77) * math.rad(240) -- (rad/s)
local THUMBSTICK_CURVATURE = 2 -- Amount of upwards curvature (0 is flat)
local THUMBSTICK_DEADZONE = 0.1 -- Deadzone
local RIGHT_THUMBSTICK = Enum.KeyCode.Thumbstick2

local currentGamepad = Enum.UserInputType.Gamepad1
local enabled = false
local connections = {}

-- This function has been pulled from the default camera scripts
local function thumbstickCurve(x: number): number
	-- Remove sign, apply linear deadzone
	local fDeadzone = (math.abs(x) - THUMBSTICK_DEADZONE) / (1 - THUMBSTICK_DEADZONE)

	-- Apply exponential curve and scale to fit in [0, 1]
	local fCurve = (math.exp(THUMBSTICK_CURVATURE * fDeadzone) - 1) / (math.exp(THUMBSTICK_CURVATURE) - 1)

	-- Reapply sign and clamp
	return math.sign(x) * math.clamp(fCurve, 0, 1)
end

local function onLastInputTypeChanged(inputType: Enum.UserInputType)
	if string.find(inputType.Name, "Gamepad") then
		currentGamepad = inputType
	end
end

local Gamepad = {}

function Gamepad:getInput(deltaTime: number): Vector2
	local inversionVector = Vector2.new(1, UserGameSettings:GetCameraYInvertValue())
	local inputVector = Vector2.zero

	local gamepadState = UserInputService:GetGamepadState(currentGamepad)

	for _, inputObject in gamepadState do
		if inputObject.KeyCode == RIGHT_THUMBSTICK then
			inputVector = Vector2.new(thumbstickCurve(inputObject.Position.X), -thumbstickCurve(inputObject.Position.Y))
		end
	end

	return inputVector * ROTATION_SPEED_GAMEPAD * inversionVector * deltaTime
end

function Gamepad:enable()
	if enabled then
		return
	end
	enabled = true

	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(onLastInputTypeChanged))
end

function Gamepad:disable()
	if not enabled then
		return
	end
	enabled = false

	disconnectAndClear(connections)
end

return Gamepad

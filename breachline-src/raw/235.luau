local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Keybinds = require(FourD.Common.Keybinds)

local Constants = require(script.Parent.Parent.Parent.Constants)
-- Camera cycling disabled (client request); retain for future re-enable.
-- local cycleCameraModeHandler = require(script.Parent.cycleCameraModeHandler)
local exitHandlerAsync = require(script.Parent.exitHandlerAsync)
local nitroHandler = require(script.Parent.nitroHandler)
local handBrakeHandler = require(script.Parent.handBrakeHandler)

local car = script.Parent.Parent.Parent.Parent
local inputs = car.Inputs

local KEYBINDS_SET_ID = "WheeledVehicle.FourWheel"

local LEFT_THUMBSTICK = Enum.KeyCode.Thumbstick1
local RIGHT_TRIGGER = Enum.KeyCode.ButtonR2
local LEFT_TRIGGER = Enum.KeyCode.ButtonL2
local STEERING_DEADZONE = 0.1

local currentGamepad = Enum.UserInputType.Gamepad1
local enabled = false
local lastInputTypeChangedConnection = nil
local nitroUsableConnection = nil
local nitroKeyCode = nil

local function onLastInputTypeChanged(inputType: Enum.UserInputType)
	if string.find(inputType.Name, "Gamepad") then
		currentGamepad = inputType
	end
end

local function updateNitroBinding()
	local nitroUsable = car:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE) == true

	if nitroUsable then
		ContextActionService:BindAction(Constants.GAMEPAD_NITRO_BIND_NAME, nitroHandler, false, nitroKeyCode)
	else
		ContextActionService:UnbindAction(Constants.GAMEPAD_NITRO_BIND_NAME)
	end
end

local Gamepad = {}

function Gamepad:getThrottleAndSteering(): (number, number)
	local throttle = 0
	local steering = 0
	local gamepadState = UserInputService:GetGamepadState(currentGamepad)

	for _, inputObject in gamepadState do
		if inputObject.KeyCode == LEFT_THUMBSTICK then
			local position = inputObject.Position.X
			if math.abs(position) > STEERING_DEADZONE then
				-- Apply deadzone
				steering = ((math.abs(position) - STEERING_DEADZONE) / (1 - STEERING_DEADZONE)) * math.sign(position)
			end
		elseif inputObject.KeyCode == RIGHT_TRIGGER then
			throttle += inputObject.Position.Z
		elseif inputObject.KeyCode == LEFT_TRIGGER then
			throttle -= inputObject.Position.Z
		end
	end

	return throttle, steering
end

function Gamepad:enable()
	if enabled then
		return
	end
	enabled = true

	local exitKeyCode = Keybinds.getGamepadKey(KEYBINDS_SET_ID, "Exit", inputs)
	nitroKeyCode = Keybinds.getGamepadKey(KEYBINDS_SET_ID, "Nitro", inputs)
	local handBrakeKeyCode = Keybinds.getGamepadKey(KEYBINDS_SET_ID, "HandBrake", inputs)

	-- Camera cycling disabled (client request); retain for future re-enable.
	-- local cycleCameraModeKeyCode = Keybinds.getGamepadKey(KEYBINDS_SET_ID, "CycleCamera", inputs)
	-- ContextActionService:BindAction(
	-- 	Constants.GAMEPAD_CYCLE_CAMERA_MODE_BIND_NAME,
	-- 	cycleCameraModeHandler,
	-- 	false,
	-- 	cycleCameraModeKeyCode
	-- )
	ContextActionService:BindAction(Constants.GAMEPAD_EXIT_BIND_NAME, exitHandlerAsync, false, exitKeyCode)
	ContextActionService:BindAction(Constants.GAMEPAD_HAND_BRAKE_BIND_NAME, handBrakeHandler, false, handBrakeKeyCode)

	updateNitroBinding()
	nitroUsableConnection = car:GetAttributeChangedSignal(Constants.NITRO_USABLE_ATTRIBUTE):Connect(updateNitroBinding)

	-- We listen to LastInputTypeChanged so we can specifically check which was the last gamepad being used.
	-- Simply calling GetLastInputType in getThrottleAndSteering would potentially return non-gamepad InputTypes.
	lastInputTypeChangedConnection = UserInputService.LastInputTypeChanged:Connect(onLastInputTypeChanged)

	local lastInputType = UserInputService:GetLastInputType()
	onLastInputTypeChanged(lastInputType)
end

function Gamepad:disable()
	if not enabled then
		return
	end
	enabled = false

	-- Camera cycling disabled (client request); retain for future re-enable.
	-- ContextActionService:UnbindAction(Constants.GAMEPAD_CYCLE_CAMERA_MODE_BIND_NAME)
	ContextActionService:UnbindAction(Constants.GAMEPAD_EXIT_BIND_NAME)
	ContextActionService:UnbindAction(Constants.GAMEPAD_NITRO_BIND_NAME)
	ContextActionService:UnbindAction(Constants.GAMEPAD_HAND_BRAKE_BIND_NAME)

	if lastInputTypeChangedConnection then
		lastInputTypeChangedConnection:Disconnect()
		lastInputTypeChangedConnection = nil
	end

	if nitroUsableConnection then
		nitroUsableConnection:Disconnect()
		nitroUsableConnection = nil
	end
end

return Gamepad

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

local bike = script.Parent.Parent.Parent.Parent
local inputs = bike.Inputs

local KEYBINDS_SET_ID = "WheeledVehicle.TwoWheel"

local FORWARD_KEY = Enum.KeyCode.W
local BACKWARD_KEY = Enum.KeyCode.S
local RIGHT_KEY = Enum.KeyCode.D
local LEFT_KEY = Enum.KeyCode.A
local FORWARD_KEY_ALT = Enum.KeyCode.Up
local BACKWARD_KEY_ALT = Enum.KeyCode.Down
local RIGHT_KEY_ALT = Enum.KeyCode.Right
local LEFT_KEY_ALT = Enum.KeyCode.Left

local enabled = false
local nitroUsableConnection = nil
local nitroKeyCode = nil

local function updateNitroBinding()
	local nitroUsable = bike:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE) == true

	if nitroUsable then
		ContextActionService:BindAction(Constants.KEYBOARD_NITRO_BIND_NAME, nitroHandler, false, nitroKeyCode)
	else
		ContextActionService:UnbindAction(Constants.KEYBOARD_NITRO_BIND_NAME)
	end
end

local KeyboardAndMouse = {}

function KeyboardAndMouse:getThrottleAndSteering(): (number, number)
	local throttle = 0
	local steering = 0

	if UserInputService:IsKeyDown(FORWARD_KEY) or UserInputService:IsKeyDown(FORWARD_KEY_ALT) then
		throttle += 1
	end
	if UserInputService:IsKeyDown(BACKWARD_KEY) or UserInputService:IsKeyDown(BACKWARD_KEY_ALT) then
		throttle -= 1
	end
	if UserInputService:IsKeyDown(RIGHT_KEY) or UserInputService:IsKeyDown(RIGHT_KEY_ALT) then
		steering += 1
	end
	if UserInputService:IsKeyDown(LEFT_KEY) or UserInputService:IsKeyDown(LEFT_KEY_ALT) then
		steering -= 1
	end

	return throttle, steering
end

function KeyboardAndMouse:enable()
	if enabled then
		return
	end
	enabled = true

	local exitKeyCode = Keybinds.getKeyboardKey(KEYBINDS_SET_ID, "Exit", inputs)
	nitroKeyCode = Keybinds.getKeyboardKey(KEYBINDS_SET_ID, "Nitro", inputs)

	-- Camera cycling disabled (client request); retain for future re-enable.
	-- local cycleCameraModeKeyCode = Keybinds.getKeyboardKey(KEYBINDS_SET_ID, "CycleCamera", inputs)
	-- ContextActionService:BindAction(
	-- 	Constants.KEYBOARD_CYCLE_CAMERA_MODE_BIND_NAME,
	-- 	cycleCameraModeHandler,
	-- 	false,
	-- 	cycleCameraModeKeyCode
	-- )
	ContextActionService:BindAction(Constants.KEYBOARD_EXIT_BIND_NAME, exitHandlerAsync, false, exitKeyCode)

	updateNitroBinding()
	nitroUsableConnection = bike:GetAttributeChangedSignal(Constants.NITRO_USABLE_ATTRIBUTE):Connect(updateNitroBinding)
end

function KeyboardAndMouse:disable()
	if not enabled then
		return
	end
	enabled = false

	-- Camera cycling disabled (client request); retain for future re-enable.
	-- ContextActionService:UnbindAction(Constants.KEYBOARD_CYCLE_CAMERA_MODE_BIND_NAME)
	ContextActionService:UnbindAction(Constants.KEYBOARD_EXIT_BIND_NAME)
	ContextActionService:UnbindAction(Constants.KEYBOARD_NITRO_BIND_NAME)

	if nitroUsableConnection then
		nitroUsableConnection:Disconnect()
		nitroUsableConnection = nil
	end
end

return KeyboardAndMouse

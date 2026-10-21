--[[
	File: init.luau
	WaterSubmersible input subsystem. Owns all player input: device categorization,
	throttle/steering polling, reverse-steer invert, touch-controls toggle, and the
	Dive/Surface keybinds. Absorbed from the PlayerDrivable Behavior.
]]--

-- Root

local Input = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Keybinds = require(FourD.Common.Keybinds)

local KeyboardAndMouse = require(script.KeyboardAndMouse)
local Gamepad = require(script.Gamepad)
local Touch = require(script.Touch)

-- Constants

local KEYBINDS_SET_ID = "WaterSubmersible"
local INPUT_KEYBOARD = "KeyboardAndMouse"
local INPUT_GAMEPAD = "Gamepad"
local INPUT_TOUCH = "Touch"
local INPUT_UNKNOWN = "Unknown"

-- Module State

local active = false
local currentCategory = INPUT_UNKNOWN
local currentGamepad: Enum.UserInputType = Enum.UserInputType.Gamepad1
local currentSeat: VehicleSeat? = nil
local isDiving = false
local isSurfacing = false
local lastInputTypeConnection: RBXScriptConnection? = nil
local depthBindHandle: Keybinds.BindActionsHandle? = nil

-- Local Functions

local function categorizeInputType(inputType: Enum.UserInputType): string
	if string.find(inputType.Name, "Gamepad") then
		return INPUT_GAMEPAD
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return INPUT_KEYBOARD
	elseif inputType == Enum.UserInputType.Touch then
		return INPUT_TOUCH
	end
	return INPUT_UNKNOWN
end

local function getDefaultInputCategory(): string
	local lastCategory = categorizeInputType(UserInputService:GetLastInputType())
	if lastCategory ~= INPUT_UNKNOWN then
		return lastCategory
	end

	if UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		return INPUT_KEYBOARD
	elseif UserInputService.TouchEnabled then
		return INPUT_TOUCH
	elseif UserInputService.GamepadEnabled then
		return INPUT_GAMEPAD
	end

	return INPUT_UNKNOWN
end

-- Public Functions

function Input.enable(seat: VehicleSeat, overrideSource: Instance)
	if active then return end
	active = true

	currentSeat = seat
	currentCategory = getDefaultInputCategory()
	currentGamepad = Enum.UserInputType.Gamepad1
	isDiving = false
	isSurfacing = false


	depthBindHandle = Keybinds.bindActions(KEYBINDS_SET_ID, {
		IncreaseDepth = function(state: Enum.UserInputState): Enum.ContextActionResult
			isDiving = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end,
		DecreaseDepth = function(state: Enum.UserInputState): Enum.ContextActionResult
			isSurfacing = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end,
		Exit = function(state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin and currentSeat then
				local occupant = currentSeat.Occupant
				if occupant then
					occupant:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end
			return Enum.ContextActionResult.Sink
		end,
	}, overrideSource, { CreateTouchButton = true })

	lastInputTypeConnection = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local category = categorizeInputType(inputType)
		if category == INPUT_UNKNOWN then return end
		currentCategory = category
		if string.find(inputType.Name, "Gamepad") then
			currentGamepad = inputType
		end
	end)
end

function Input.disable()
	if not active then return end
	active = false

	if lastInputTypeConnection then
		lastInputTypeConnection:Disconnect()
		lastInputTypeConnection = nil
	end

	if depthBindHandle then
		depthBindHandle:Destroy()
		depthBindHandle = nil
	end


	currentSeat = nil
	currentCategory = INPUT_UNKNOWN
	isDiving = false
	isSurfacing = false
end

function Input.poll(): InputState
	local throttle = 0
	local steering = 0

	if currentCategory == INPUT_KEYBOARD then
		throttle, steering = KeyboardAndMouse.poll()
	elseif currentCategory == INPUT_GAMEPAD then
		throttle, steering = Gamepad.poll(currentGamepad)
	elseif currentCategory == INPUT_TOUCH and currentSeat then
		throttle, steering = Touch.poll(currentSeat)
	end

	throttle = math.clamp(throttle, -1, 1)
	steering = math.clamp(steering, -1, 1)

	-- Reverse-steer invert: matches PlayerDrivable so steering stays intuitive while backing up.
	if throttle < 0 then
		steering = -steering
	end

	return {
		Throttle = throttle,
		Steering = steering,
		IsDiving = isDiving,
		IsSurfacing = isSurfacing,
	}
end

-- Types

export type InputState = {
	Throttle: number,
	Steering: number,
	IsDiving: boolean,
	IsSurfacing: boolean,
}

-- Return

return Input

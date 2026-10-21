--[[
	File: init.luau
]]--

-- Root

local Input = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Keybinds = require(FourD.Common.Keybinds)
local InputCommon = require(FourD.Architects.AirVehicle.Common.Scripts.InputCommon)

local Constants = require(script.Parent.Constants)
local KeyboardAndMouse = require(script.KeyboardAndMouse)
local Gamepad = require(script.Gamepad)
local Touch = require(script.Touch)

-- Constants

local KEYBINDS_SET_ID = "AirVehicle.Jetpack"

-- Module State

local active = false
local currentCategory = Constants.INPUT_UNKNOWN
local currentGamepad: Enum.UserInputType = Enum.UserInputType.Gamepad1
local lastInputTypeConnection: RBXScriptConnection? = nil
local exitBindHandle: Keybinds.BindActionsHandle? = nil

-- Public Functions

function Input.enable(unmountRemote: RemoteEvent)
	if active then return end
	active = true

	currentCategory = InputCommon.getDefaultInputCategory()
	currentGamepad = Enum.UserInputType.Gamepad1

	KeyboardAndMouse.enable()
	Gamepad.enable()

	exitBindHandle = Keybinds.bindActions(KEYBINDS_SET_ID, {
		Exit = function(state)
			if state == Enum.UserInputState.Begin then
				unmountRemote:FireServer()
			end
			return nil
		end,
	})

	Touch.bindMobileActions(unmountRemote)

	lastInputTypeConnection = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local category = InputCommon.categorizeInputType(inputType)
		if category == Constants.INPUT_UNKNOWN then return end
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

	if exitBindHandle then
		exitBindHandle:Destroy()
		exitBindHandle = nil
	end
	Touch.unbindMobileActions()
	Touch.reset()

	KeyboardAndMouse.disable()
	Gamepad.disable()
end

function Input.poll(): InputState
	local forwardInput = 0
	local strafeInput = 0
	local collectiveInput = 0

	if currentCategory == Constants.INPUT_KEYBOARD then
		forwardInput, strafeInput, collectiveInput = KeyboardAndMouse.poll()
	elseif currentCategory == Constants.INPUT_GAMEPAD then
		forwardInput, strafeInput, collectiveInput = Gamepad.poll(currentGamepad)
	elseif currentCategory == Constants.INPUT_TOUCH then
		forwardInput, strafeInput, collectiveInput = Touch.poll()
	end

	return {
		ForwardInput = forwardInput,
		StrafeInput = strafeInput,
		CollectiveInput = collectiveInput,
		IsTouchCategory = currentCategory == Constants.INPUT_TOUCH,
	}
end

-- Types

export type InputState = {
	ForwardInput: number,
	StrafeInput: number,
	CollectiveInput: number,
	IsTouchCategory: boolean,
}

-- Return

return Input

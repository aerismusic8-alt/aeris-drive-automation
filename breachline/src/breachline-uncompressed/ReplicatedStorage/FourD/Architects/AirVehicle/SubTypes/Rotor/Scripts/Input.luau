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

local KEYBINDS_SET_ID = "AirVehicle.Rotor"

-- Module State

local active = false
local pitchFollowEnabled = false
local currentCategory = Constants.INPUT_UNKNOWN
local currentGamepad: Enum.UserInputType = Enum.UserInputType.Gamepad1
local lastInputTypeConnection: RBXScriptConnection? = nil
local exitBindHandle: Keybinds.BindActionsHandle? = nil

-- Public Functions

function Input.enable(unmountRemote: RemoteEvent, pitchFollow: boolean?)
	if active then return end
	active = true
	pitchFollowEnabled = pitchFollow == true

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

	Touch.bindMobileActions(unmountRemote, pitchFollowEnabled)

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
	local yawAlpha = 0
	local pitchAlpha = 0

	if currentCategory == Constants.INPUT_KEYBOARD then
		forwardInput, strafeInput, collectiveInput, yawAlpha, pitchAlpha = KeyboardAndMouse.poll(pitchFollowEnabled)
	elseif currentCategory == Constants.INPUT_GAMEPAD then
		forwardInput, strafeInput, collectiveInput, yawAlpha, pitchAlpha = Gamepad.poll(currentGamepad, pitchFollowEnabled)
	elseif currentCategory == Constants.INPUT_TOUCH then
		forwardInput, strafeInput, collectiveInput, yawAlpha, pitchAlpha = Touch.poll()
	end

	return {
		ForwardInput = forwardInput,
		StrafeInput = strafeInput,
		CollectiveInput = collectiveInput,
		YawAlpha = yawAlpha,
		PitchAlpha = pitchAlpha,
		IsTouchCategory = currentCategory == Constants.INPUT_TOUCH,
	}
end

-- Types

export type InputState = {
	ForwardInput: number,
	StrafeInput: number,
	CollectiveInput: number,
	YawAlpha: number,
	PitchAlpha: number,
	IsTouchCategory: boolean,
}

-- Return

return Input

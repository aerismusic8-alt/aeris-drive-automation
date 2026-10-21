local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Constants = require(script.Parent.Parent.Parent.Constants)
local disconnectAndClear = require(script.Parent.Parent.disconnectAndClear)
-- Camera cycling disabled (client request); retain for future re-enable.
-- local cycleCameraModeHandler = require(script.Parent.cycleCameraModeHandler)
local exitHandlerAsync = require(script.Parent.exitHandlerAsync)
local handBrakeHandler = require(script.Parent.handBrakeHandler)
local nitroHandler = require(script.Parent.nitroHandler)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local touchGuiTemplate = script.TouchGui

local car = script.Parent.Parent.Parent.Parent.Parent

local enabled = false
local gui = nil
local connections = {}
local nitroButtonConnection = nil
local throttleAmount = 0
local brakeAmount = 0
local steeringTouchInputObject = nil
local gasPedalInputObject = nil
local brakePedalInputObject = nil
local nitroInputObject = nil
local handBrakeInputObject = nil

-- A single UserInputService.InputEnded connection is used to handle input ending, since
-- lifting a finger after it has moved off a GuiObject will not fire InputEnded on that GuiObject.
local function onInputEnded(inputObject: InputObject)
	inputObject:RemoveTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG)

	if inputObject == steeringTouchInputObject then
		steeringTouchInputObject = nil
	elseif inputObject == gasPedalInputObject then
		gasPedalInputObject = nil
		throttleAmount = 0
	elseif inputObject == brakePedalInputObject then
		brakePedalInputObject = nil
		brakeAmount = 0
	elseif inputObject == nitroInputObject then
		nitroInputObject = nil
		-- Since we are not using the default ContextActionService touch controls, we need to
		-- emulate a ContextActionService call to nitroHandler, passing in the expected parameters.
		nitroHandler(Constants.TOUCH_NITRO_BIND_NAME, Enum.UserInputState.End)
	elseif inputObject == handBrakeInputObject then
		handBrakeInputObject = nil
		-- Emulate a ContextActionService call to handBrakeHandler, passing in the expected parameters
		handBrakeHandler(Constants.TOUCH_HAND_BRAKE_BIND_NAME, Enum.UserInputState.End)
	end
end

-- For each of the UI buttons, we keep track of the InputObject that touched so we
-- can avoid avoid triggering other buttons by sliding over them and accurately tell
-- when the input has stopped.
local function onGasPedalInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	inputObject:AddTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG)
	gasPedalInputObject = inputObject
	throttleAmount = 1
end

local function onBrakePedalInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	inputObject:AddTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG)
	brakePedalInputObject = inputObject
	brakeAmount = 1
end

local function onWheelInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	inputObject:AddTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG)
	-- We keep track of the InputObject that touched the wheel so that we
	-- can check its position later when :getThrottleAndSteering() is called
	steeringTouchInputObject = inputObject
end

local function onNitroButtonInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	inputObject:AddTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG)
	nitroInputObject = inputObject
	-- Emulate a ContextActionService call to nitroHandler, since that is what it expects
	nitroHandler(Constants.TOUCH_NITRO_BIND_NAME, Enum.UserInputState.Begin)
end

local function onHandBrakeInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	inputObject:AddTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG)
	handBrakeInputObject = inputObject
	-- Emulate a ContextActionService call to nitroHandler, since that is what it expects
	handBrakeHandler(Constants.TOUCH_HAND_BRAKE_BIND_NAME, Enum.UserInputState.Begin)
end

local function onExitButtonInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	-- Emulate a ContextActionService call to exitHandlerAsync, since that is what it expects
	exitHandlerAsync(Constants.TOUCH_EXIT_BIND_NAME, Enum.UserInputState.Begin)
end

-- Camera cycling disabled (client request); retain for future re-enable.
-- local function onCycleCameraModeButtonInputBegan(inputObject: InputObject)
-- 	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
-- 		return
-- 	end
-- 	-- Emulate a ContextActionService call to cycleCameraModeHandler, since that is what it expects
-- 	cycleCameraModeHandler(Constants.TOUCH_CYCLE_CAMERA_MODE_BIND_NAME, Enum.UserInputState.Begin)
-- end

local function updateScale()
	-- Update UI size. This is the same logic used by the default touch controls
	local minScreenSize = math.min(gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
	local isSmallScreen = minScreenSize < Constants.UI_SMALL_SCREEN_THRESHOLD
	gui.UIScale.Scale = if isSmallScreen then Constants.UI_SMALL_SCREEN_SCALE else 1
end

local function updateNitroVisibility()
	local nitroUsable = car:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE) == true
	gui.Controls.NitroButton.Visible = nitroUsable

	if nitroUsable and not nitroButtonConnection then
		nitroButtonConnection = gui.Controls.NitroButton.InputBegan:Connect(onNitroButtonInputBegan)
	elseif not nitroUsable and nitroButtonConnection then
		nitroButtonConnection:Disconnect()
		nitroButtonConnection = nil
	end
end

local Touch = {}

function Touch:getThrottleAndSteering(): (number, number)
	local throttle = throttleAmount - brakeAmount
	local steering = 0

	-- If the player is currently touching the steering wheel, set the steering value
	if steeringTouchInputObject then
		local position = steeringTouchInputObject.Position.X
		local center = gui.Wheel.AbsolutePosition.X + gui.Wheel.AbsoluteSize.X / 2
		local offset = position - center
		local offsetAlpha = (offset / gui.Wheel.AbsoluteSize.X) * 2
		steering = math.clamp(offsetAlpha, -1, 1)
	end

	-- Update the steering wheel visual
	gui.Wheel.WheelLabel.Rotation = steering * 90

	return throttle, steering
end

function Touch:enable()
	if enabled then
		return
	end
	enabled = true

	gui = touchGuiTemplate:Clone()
	gui.Parent = playerGui

	-- Setup connections
	table.insert(connections, gui.Wheel.InputButton.InputBegan:Connect(onWheelInputBegan))
	table.insert(connections, gui.Controls.GasButton.InputBegan:Connect(onGasPedalInputBegan))
	table.insert(connections, gui.Controls.BrakeButton.InputBegan:Connect(onBrakePedalInputBegan))
	table.insert(connections, gui.Controls.HandBrakeButton.InputBegan:Connect(onHandBrakeInputBegan))
	table.insert(connections, gui.Misc.ExitButton.InputBegan:Connect(onExitButtonInputBegan))
	-- Camera cycling disabled (client request); retain for future re-enable.
	-- table.insert(connections, gui.Misc.CycleCameraModeButton.InputBegan:Connect(onCycleCameraModeButtonInputBegan))
	gui.Misc.CycleCameraModeButton.Visible = false
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale))

	updateNitroVisibility()
	table.insert(connections, car:GetAttributeChangedSignal(Constants.NITRO_USABLE_ATTRIBUTE):Connect(updateNitroVisibility))

	updateScale()
end

function Touch:disable()
	if not enabled then
		return
	end
	enabled = false

	disconnectAndClear(connections)

	if nitroButtonConnection then
		nitroButtonConnection:Disconnect()
		nitroButtonConnection = nil
	end

	if gui then
		gui:Destroy()
		gui = nil
	end
end

return Touch

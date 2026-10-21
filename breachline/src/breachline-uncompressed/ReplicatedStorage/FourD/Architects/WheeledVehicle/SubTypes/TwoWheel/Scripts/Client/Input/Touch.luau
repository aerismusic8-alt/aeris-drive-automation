local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Constants = require(script.Parent.Parent.Parent.Constants)
local disconnectAndClear = require(script.Parent.Parent.disconnectAndClear)
-- Camera cycling disabled (client request); retain for future re-enable.
-- local cycleCameraModeHandler = require(script.Parent.cycleCameraModeHandler)
local exitHandlerAsync = require(script.Parent.exitHandlerAsync)
local nitroHandler = require(script.Parent.nitroHandler)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local touchGuiTemplate = script.TouchGui

local bike = script.Parent.Parent.Parent.Parent.Parent

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
		nitroHandler(Constants.TOUCH_NITRO_BIND_NAME, Enum.UserInputState.End)
	end
end

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
	steeringTouchInputObject = inputObject
end

local function onNitroButtonInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	inputObject:AddTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG)
	nitroInputObject = inputObject
	nitroHandler(Constants.TOUCH_NITRO_BIND_NAME, Enum.UserInputState.Begin)
end

local function onExitButtonInputBegan(inputObject: InputObject)
	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
		return
	end
	exitHandlerAsync(Constants.TOUCH_EXIT_BIND_NAME, Enum.UserInputState.Begin)
end

-- Camera cycling disabled (client request); retain for future re-enable.
-- local function onCycleCameraModeButtonInputBegan(inputObject: InputObject)
-- 	if inputObject:HasTag(Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG) then
-- 		return
-- 	end
-- 	cycleCameraModeHandler(Constants.TOUCH_CYCLE_CAMERA_MODE_BIND_NAME, Enum.UserInputState.Begin)
-- end

local function updateScale()
	local minScreenSize = math.min(gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
	local isSmallScreen = minScreenSize < Constants.UI_SMALL_SCREEN_THRESHOLD
	gui.UIScale.Scale = if isSmallScreen then Constants.UI_SMALL_SCREEN_SCALE else 1
end

local function updateNitroVisibility()
	local nitroUsable = bike:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE) == true
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

	if steeringTouchInputObject then
		local position = steeringTouchInputObject.Position.X
		local center = gui.Wheel.AbsolutePosition.X + gui.Wheel.AbsoluteSize.X / 2
		local offset = position - center
		local offsetAlpha = (offset / gui.Wheel.AbsoluteSize.X) * 2
		steering = math.clamp(offsetAlpha, -1, 1)
	end

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

	table.insert(connections, gui.Wheel.InputButton.InputBegan:Connect(onWheelInputBegan))
	table.insert(connections, gui.Controls.GasButton.InputBegan:Connect(onGasPedalInputBegan))
	table.insert(connections, gui.Controls.BrakeButton.InputBegan:Connect(onBrakePedalInputBegan))
	table.insert(connections, gui.Misc.ExitButton.InputBegan:Connect(onExitButtonInputBegan))
	-- Camera cycling disabled (client request); retain for future re-enable.
	-- table.insert(connections, gui.Misc.CycleCameraModeButton.InputBegan:Connect(onCycleCameraModeButtonInputBegan))
	gui.Misc.CycleCameraModeButton.Visible = false
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale))

	local handBrakeButton = gui.Controls:FindFirstChild("HandBrakeButton")
	if handBrakeButton then handBrakeButton.Visible = false end

	updateNitroVisibility()
	table.insert(connections, bike:GetAttributeChangedSignal(Constants.NITRO_USABLE_ATTRIBUTE):Connect(updateNitroVisibility))

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

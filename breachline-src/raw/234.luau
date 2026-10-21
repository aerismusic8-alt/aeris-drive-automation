local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Parent.Constants)
local InputCategorizer = require(script.Parent.InputCategorizer)
local InputModules = {
	[InputCategorizer.InputCategory.KeyboardAndMouse] = require(script.KeyboardAndMouse),
	[InputCategorizer.InputCategory.Gamepad] = require(script.Gamepad),
	[InputCategorizer.InputCategory.Touch] = require(script.Touch),
}
local disconnectAndClear = require(script.Parent.disconnectAndClear)

local car = script.Parent.Parent.Parent
local inputs = car.Inputs

local currentInputCategory = InputCategorizer.getLastInputCategory()
local enabled = false
local connections = {}

local function onLastInputCategoryChanged(lastInputCategory)
	currentInputCategory = lastInputCategory

	for inputCategory, module in InputModules do
		if inputCategory == lastInputCategory then
			module:enable()
		else
			module:disable()
		end
	end
end

local function update()
	local inputModule = InputModules[currentInputCategory]
	if not inputModule then
		return
	end

	local throttle, steering = inputModule:getThrottleAndSteering()
	inputs:SetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE, throttle)
	inputs:SetAttribute(Constants.STEERING_INPUT_ATTRIBUTE, steering)
end

local Input = {}

function Input:enable()
	if enabled then
		return
	end
	enabled = true

	-- Disable touch controls
	GuiService.TouchControlsEnabled = false

	table.insert(connections, InputCategorizer.lastInputCategoryChanged:Connect(onLastInputCategoryChanged))
	table.insert(connections, RunService.Stepped:Connect(update))

	onLastInputCategoryChanged(InputCategorizer.getLastInputCategory())
end

function Input:disable()
	if not enabled then
		return
	end
	enabled = false

	-- Reenable touch controls
	GuiService.TouchControlsEnabled = true

	-- Disable all input modules
	for _, module in InputModules do
		module:disable()
	end

	-- Disconnect all connections
	disconnectAndClear(connections)
end

return Input

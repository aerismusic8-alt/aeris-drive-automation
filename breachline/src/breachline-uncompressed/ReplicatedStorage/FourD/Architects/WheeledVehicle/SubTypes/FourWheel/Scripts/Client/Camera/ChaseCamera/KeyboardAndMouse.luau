local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local disconnectAndClear = require(script.Parent.Parent.Parent.disconnectAndClear)

local MOUSE_DRAG_INPUT_TYPE = Enum.UserInputType.MouseButton2
-- These variables have been pulled from the default camera scripts
local ROTATION_SPEED_MOUSE = Vector2.new(1, 0.77) * math.rad(0.5) -- (rad/s)
local ROTATION_SPEED_POINTERACTION = Vector2.new(1, 0.77) * math.rad(7) -- (rad/s)

local enabled = false
local dragging = false
local connections = {}
local mouseMovement = Vector2.zero
local panMovement = Vector2.zero

local function resetInput()
	mouseMovement = Vector2.zero
	panMovement = Vector2.zero
end

local function onInputChanged(inputObject: InputObject)
	if inputObject.UserInputType == Enum.UserInputType.MouseMovement then
		if dragging then
			mouseMovement = Vector2.new(inputObject.Delta.X, inputObject.Delta.Y)
		end
	end
end

local function onInputBegan(inputObject: InputObject, processed: boolean)
	if processed then
		return
	end
	if inputObject.UserInputType == MOUSE_DRAG_INPUT_TYPE then
		-- When the player presses the mouse drag button, lock the mouse in its current position
		if not dragging then
			dragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end
end

local function onInputEnded(inputObject: InputObject, _processed: boolean)
	if inputObject.UserInputType == MOUSE_DRAG_INPUT_TYPE then
		-- When the mouse drag button is released, unlock the mouse
		if dragging then
			dragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end

local function onPointerAction(_wheel: number, pan: Vector2, _pinch: number, processed: boolean)
	if processed then
		return
	end
	-- Track panning from e.g. a mousepad
	panMovement = pan
end

local KeyboardAndMouse = {}

function KeyboardAndMouse:getInput(_deltaTime: number): Vector2
	local inversionVector = Vector2.new(1, UserGameSettings:GetCameraYInvertValue())
	local inputVector = mouseMovement * ROTATION_SPEED_MOUSE + panMovement * ROTATION_SPEED_POINTERACTION

	-- getInput() is only expected to be called once per frame. The input values are reset
	-- to prevent them from continuously rolling over into the next frame once they stop.
	resetInput()

	return inputVector * inversionVector
end

function KeyboardAndMouse:enable()
	if enabled then
		return
	end
	enabled = true

	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, UserInputService.PointerAction:Connect(onPointerAction))

	resetInput()
end

function KeyboardAndMouse:disable()
	if not enabled then
		return
	end
	enabled = false

	disconnectAndClear(connections)

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

return KeyboardAndMouse

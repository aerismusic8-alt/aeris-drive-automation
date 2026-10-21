local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local Workspace = game:GetService("Workspace")

local disconnectAndClear = require(script.Parent.Parent.Parent.disconnectAndClear)

-- These variables have been pulled from the default camera scripts
local MIN_TOUCH_SENSITIVITY_FRACTION = 0.25 -- 25% sensitivity at 90°
local ROTATION_SPEED_TOUCH = Vector2.new(1, 0.66) * math.rad(1) -- (rad/s)

local enabled = false
local connections = {}
local sunkTouchInputs = {}

local touchMovement = Vector2.zero

local function resetInput()
	touchMovement = Vector2.zero
end

-- Adjust the touch sensitivity so that sensitivity is reduced when swiping away
-- from the horizon line. Sensitivity is not adjusted when swiping toward it.
-- This function was pulled from the default camera scripts.
local function adjustTouchPitchSensitivity(delta: Vector2): Vector2
	local camera = Workspace.CurrentCamera

	if not camera then
		return delta
	end

	-- Get the camera pitch in world space
	local pitch = camera.CFrame:ToEulerAnglesYXZ()

	if delta.Y * pitch >= 0 then
		-- Do not reduce sensitivity when pitching towards the horizon
		return delta
	end

	-- Set up a curve f() to fit:
	-- f(0) = 1
	-- f(±pi/2) = 0
	local curveY = 1 - (2 * math.abs(pitch) / math.pi) ^ 0.75

	-- Remap curveY from [0, 1] -> [MIN_TOUCH_SENSITIVITY_FRACTION, 1]
	local sensitivity = curveY * (1 - MIN_TOUCH_SENSITIVITY_FRACTION) + MIN_TOUCH_SENSITIVITY_FRACTION

	return Vector2.new(1, sensitivity) * delta
end

local function onTouchMoved(inputObject: InputObject, processed: boolean)
	if processed then
		return
	end
	if sunkTouchInputs[inputObject] then
		return
	end
	touchMovement = Vector2.new(inputObject.Delta.X, inputObject.Delta.Y)
end

local function onInputBegan(inputObject: InputObject, processed: boolean)
	if inputObject.UserInputType == Enum.UserInputType.Touch then
		if processed then
			sunkTouchInputs[inputObject] = true
		end
	end
end

local function onInputEnded(inputObject: InputObject, _processed: boolean)
	if sunkTouchInputs[inputObject] then
		sunkTouchInputs[inputObject] = nil
	end
end

local Touch = {}

function Touch:getInput(_deltaTime: number): Vector2
	local inversionVector = Vector2.new(1, UserGameSettings:GetCameraYInvertValue())
	local inputVector = adjustTouchPitchSensitivity(touchMovement) * ROTATION_SPEED_TOUCH

	-- getInput() is only expected to be called once per frame. The input values are reset
	-- to prevent them from continuously rolling over into the next frame once they stop.
	resetInput()

	return inputVector * inversionVector
end

function Touch:enable()
	if enabled then
		return
	end
	enabled = true

	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, UserInputService.TouchMoved:Connect(onTouchMoved))

	resetInput()
end

function Touch:disable()
	if not enabled then
		return
	end
	enabled = false

	disconnectAndClear(connections)

	table.clear(sunkTouchInputs)
end

return Touch

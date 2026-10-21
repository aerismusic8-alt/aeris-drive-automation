--[[
	The ChaseCamera follows the car at a set distance and height, aligning itself with the car's
	movement direction. The player can control it like the standard camera (i.e. orbit around the car).
	When the player starts controlling, it switches to manual mode and does not align with the car's
	movement direction. After a few seconds without player input, the camera will return to automatic mode.
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InputCategorizer = require(script.Parent.Parent.InputCategorizer)

local InputModules = {
	[InputCategorizer.InputCategory.KeyboardAndMouse] = require(script.KeyboardAndMouse),
	[InputCategorizer.InputCategory.Gamepad] = require(script.Gamepad),
	[InputCategorizer.InputCategory.Touch] = require(script.Touch),
}
local pitchAndYawFromDirection = require(script.pitchAndYawFromDirection)

local camera = Workspace.CurrentCamera
local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis
local body_geom = car.Parent:FindFirstChild("body_geom", true)

local RENDER_STEPPED_BIND_NAME = "CarChaseCamera"
local RENDER_STEPPED_BIND_PRIORITY = Enum.RenderPriority.Camera.Value

local RESET_TO_AUTOMATIC_TIME = 3 -- Time it takes to reset back to automatic control once the player stops controlling the camera
local LOOK_AHEAD_AMOUNT = 3
local LOOK_AHEAD_HEIGHT_SCALE = 0.5
local LOOK_AHEAD_SPEED = 10
local TRAILING_CATCHUP_SPEED = 15
local GIMBAL_SPEED_AUTOMATIC = 5
local GIMBAL_SPEED_MANUAL = 15
local CAMERA_SPEED_AUTOMATIC = 5
local CAMERA_SPEED_MANUAL = 15
-- local USE_VELOCITY_DIRECTION_THRESHOLD = 10

local MAX_PITCH = math.rad(80)
local MIN_PITCH = math.rad(-80)

local gimbalCFrame = CFrame.new()
local relativeCameraCFrame = CFrame.new()
local trailingOffset = Vector3.zero
local lookAhead = Vector3.zero
local isManualControl = false
local lastManualControl = 0
local pitch = 0
local yaw = 0

local lastInputCategoryChangedConnection = nil
local currentInputCategory = InputCategorizer.getLastInputCategory()
local enabled = false
local parameters = {
	height = 7,
	distance = 15,
}

-- Enable/disable input modules when the input category changes
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

local function update(deltaTime: number)
	local chassisVelocity = chassis.AssemblyLinearVelocity
	local targetVector = chassisVelocity
	-- If the chassis is not moving fast enough, look forward rather than in the velocity direction

	-- TODO: restore
	--if chassisVelocity.Magnitude < USE_VELOCITY_DIRECTION_THRESHOLD then
	targetVector = chassis.CFrame.LookVector
	--end

	-- Read input
	local inputModule = InputModules[currentInputCategory]
	local inputVector = inputModule:getInput(deltaTime)
	local isInputting = inputVector.Magnitude ~= 0

	-- When the player makes a camera input (right click + drag, thumbstick, etc.), the camera is
	-- switched to manual mode, allowing the player to move it around freely. After a few seconds
	-- without player input, the camera switches back to automatic mode, where it is aligned with
	-- the car's movement direction.
	if isInputting then
		isManualControl = true
		lastManualControl = os.clock()
		pitch = math.clamp(pitch - inputVector.Y, MIN_PITCH, MAX_PITCH)
		yaw = (yaw - inputVector.X) % (math.pi * 2)
	end

	if isManualControl then
		-- If in manual (i.e. player) control mode and no inputs have been made recently, reset
		-- back to automatic mode.
		local elapsed = os.clock() - lastManualControl
		if elapsed > RESET_TO_AUTOMATIC_TIME then
			isManualControl = false
		end
	else
		-- When in automatic mode, calculate the new pitch and yaw from the target direction
		local newPitch, newYaw = pitchAndYawFromDirection(targetVector)
		pitch, yaw = newPitch, newYaw
	end

	-- Update gimbal cframe
	local gimbalSpeed = if isManualControl then GIMBAL_SPEED_MANUAL else GIMBAL_SPEED_AUTOMATIC
	local newGimbalCFrame = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	gimbalCFrame = gimbalCFrame:Lerp(newGimbalCFrame, math.min(deltaTime * gimbalSpeed, 1))

	-- Update look ahead
	local lookAheadFactor = if isManualControl then 0 else 1
	local newLookAhead = targetVector * LOOK_AHEAD_AMOUNT * lookAheadFactor
	lookAhead = lookAhead:Lerp(newLookAhead, math.min(deltaTime * LOOK_AHEAD_SPEED, 1))

	-- Update trailing offset
	trailingOffset -= targetVector * deltaTime
	trailingOffset = trailingOffset:Lerp(Vector3.zero, math.min(deltaTime * TRAILING_CATCHUP_SPEED, 1))

	-- Update virtual camera cframe
	local cameraSpeed = if isManualControl then CAMERA_SPEED_MANUAL else CAMERA_SPEED_AUTOMATIC
	local cameraPosition = trailingOffset
		+ Vector3.new(0, parameters.height, 0)
		+ gimbalCFrame:PointToWorldSpace(Vector3.new(0, 0, parameters.distance))
	local lookAheadPosition = lookAhead + Vector3.new(0, parameters.height * LOOK_AHEAD_HEIGHT_SCALE, 0)
	local newVirtualCameraCFrame = CFrame.lookAt(cameraPosition, lookAheadPosition, Vector3.yAxis)
	relativeCameraCFrame = relativeCameraCFrame:Lerp(newVirtualCameraCFrame, math.min(deltaTime * cameraSpeed, 1))

	-- Update actual camera cframe
	camera.CFrame = CFrame.new(body_geom.Position + Vector3.new(0, body_geom.Size.Y / 2, 0)) * relativeCameraCFrame
	camera.Focus = CFrame.new(chassis.Position)
end

local function initializeValues()
	-- Initialize values so the camera is positioned correctly when the module is enabled
	gimbalCFrame = chassis.CFrame - chassis.CFrame.Position
	local chassisCFrame = CFrame.new(chassis.Position)
	relativeCameraCFrame = chassisCFrame:ToObjectSpace(camera.CFrame)
	trailingOffset = Vector3.zero
	lookAhead = Vector3.zero
end

local ChaseCamera = {}

function ChaseCamera:setParameters(newParameters: typeof(parameters))
	parameters = newParameters
end

function ChaseCamera:enable()
	if enabled then
		return
	end
	enabled = true

	lastInputCategoryChangedConnection = InputCategorizer.lastInputCategoryChanged:Connect(onLastInputCategoryChanged)

	onLastInputCategoryChanged(InputCategorizer.getLastInputCategory())
	initializeValues()
	RunService:BindToRenderStep(RENDER_STEPPED_BIND_NAME, RENDER_STEPPED_BIND_PRIORITY, update)
end

function ChaseCamera:disable()
	if not enabled then
		return
	end
	enabled = false

	if lastInputCategoryChangedConnection then
		lastInputCategoryChangedConnection:Disconnect()
		lastInputCategoryChangedConnection = nil
	end

	-- Disable all InputModules
	for _, module in InputModules do
		module:disable()
	end

	RunService:UnbindFromRenderStep(RENDER_STEPPED_BIND_NAME)
end

return ChaseCamera

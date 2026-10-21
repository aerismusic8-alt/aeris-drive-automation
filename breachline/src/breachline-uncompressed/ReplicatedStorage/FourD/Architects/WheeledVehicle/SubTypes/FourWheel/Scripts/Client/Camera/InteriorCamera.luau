--[[
	The InteriorCamera mimics a driver's view, turning slightly in tandem with the steering and
	looking back over the shoulder while reversing.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent.Parent.Parent.Constants)
local setCharacterVisible = require(script.setCharacterVisible)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis
local inputs = car.Inputs

local RENDER_STEPPED_BIND_NAME = "CarInteriorCamera"
local RENDER_STEPPED_BIND_PRIORITY = Enum.RenderPriority.Camera.Value

local HEAD_TURN_SPEED = 4
local HEAD_ALIGN_SPEED = 30
local KEEP_UPRIGHT_PROPORTION = 0.2
local REVERSE_SPEED_THRESHOLD = 10

local forwardVector = Vector3.zero
local upVector = Vector3.zero
local headTurnAngle = 0

local enabled = false
local parameters = {
	attachment = nil,
	forwardHeadTurnAngle = 0,
	reverseHeadTurnAngle = 0,
}

local function update(deltaTime: number)
	local steeringInput = inputs:GetAttribute(Constants.STEERING_INPUT_ATTRIBUTE)
	local throttleInput = inputs:GetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE)
	local chassisLocalVelocity = chassis.CFrame:VectorToObjectSpace(chassis.AssemblyLinearVelocity)

	local targetHeadTurnAngle = steeringInput * parameters.forwardHeadTurnAngle
	-- If the throttle is in reverse and the car is actually moving backwards, turn the camer around.
	-- Note: because of the way CFrames are constructed, chassisLocalVelocity.Z is positive when the
	-- car is moving backward and negative when it is moving forward.
	if chassisLocalVelocity.Z > REVERSE_SPEED_THRESHOLD and throttleInput < 0 then
		targetHeadTurnAngle = parameters.reverseHeadTurnAngle
	end
	headTurnAngle = math.lerp(headTurnAngle, targetHeadTurnAngle, math.min(deltaTime * HEAD_TURN_SPEED, 1))

	-- Update the forward and up vectors
	local targetForwardVector = parameters.attachment.WorldCFrame.LookVector
	forwardVector = forwardVector:Lerp(targetForwardVector, math.min(deltaTime * HEAD_ALIGN_SPEED, 1))
	local targetUpVector = parameters.attachment.WorldCFrame.UpVector:Lerp(Vector3.yAxis, KEEP_UPRIGHT_PROPORTION)
	upVector = upVector:Lerp(targetUpVector, math.min(deltaTime * HEAD_ALIGN_SPEED, 1))

	-- Construct a cframe using the forward and up vectors, then apply headTurnAngle on top
	local centerPosition = parameters.attachment.WorldCFrame.Position
	local centerCFrame = CFrame.lookAt(centerPosition, centerPosition + forwardVector, upVector)
	camera.CFrame = centerCFrame * CFrame.Angles(0, -headTurnAngle, 0)
end

local function initializeValues()
	forwardVector = chassis.CFrame.LookVector
	upVector = chassis.CFrame.UpVector
	headTurnAngle = 0
end

local InteriorCamera = {}

function InteriorCamera:setParameters(newParameters: typeof(parameters))
	parameters = newParameters
end

function InteriorCamera:enable()
	if enabled then
		return
	end
	enabled = true

	initializeValues()

	RunService:BindToRenderStep(RENDER_STEPPED_BIND_NAME, RENDER_STEPPED_BIND_PRIORITY, update)

	-- Because the default camera scripts change character transparency every frame,
	-- this must be deferred so it runs after the camera code is complete.
	task.defer(function()
		local character = player.Character
		if character then
			setCharacterVisible(character, false)
		end
	end)
end

function InteriorCamera:disable()
	if not enabled then
		return
	end
	enabled = false

	RunService:UnbindFromRenderStep(RENDER_STEPPED_BIND_NAME)

	local character = player.Character
	if character then
		setCharacterVisible(character, true)
	end
end

return InteriorCamera

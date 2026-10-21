--[[
	File: KeyboardAndMouse.luau
]]--

-- Root

local KeyboardAndMouse = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local InputCommon = require(FourD.Architects.AirVehicle.Common.Scripts.InputCommon)

local Constants = require(script.Parent.Parent.Constants)
local Camera = require(script.Parent.Parent.Camera)

-- Public Functions

function KeyboardAndMouse.enable()
	InputCommon.enableMouseFreeRotate()
end

function KeyboardAndMouse.disable()
	InputCommon.disableMouseFreeRotate()
end

function KeyboardAndMouse.poll(pitchFollow: boolean?): (number, number, number, number, number)
	local forwardInput = 0
	local strafeInput = 0
	local collectiveInput = 0
	local yawAlpha = 0
	local pitchAlpha = 0

	if UserInputService:IsKeyDown(Constants.FORWARD_KEY) then
		forwardInput += 1
	end

	if UserInputService:IsKeyDown(Constants.REVERSE_KEY) then
		forwardInput -= 1
	end

	if UserInputService:IsKeyDown(Constants.STRAFE_RIGHT_KEY) then
		strafeInput += 1
	end

	if UserInputService:IsKeyDown(Constants.STRAFE_LEFT_KEY) then
		strafeInput -= 1
	end

	if UserInputService:IsKeyDown(Constants.ASCEND_KEY) then
		collectiveInput += 1
	end

	if UserInputService:IsKeyDown(Constants.DESCEND_KEY) then
		collectiveInput -= 1
	end

	if not Camera.isFreeRotateActive() then
		local mouse = UserInputService:GetMouseLocation()
		local viewport = Workspace.CurrentCamera.ViewportSize
		if viewport.X > 0 then
			local rawX = (mouse.X - viewport.X * 0.5) / (viewport.X * 0.5)
			yawAlpha = InputCommon.applyDeadzone(-rawX, Constants.YAW_DEADZONE_FRAC)
		end
		if pitchFollow and viewport.Y > 0 then
			local rawY = (mouse.Y - viewport.Y * 0.5) / (viewport.Y * 0.5)
			pitchAlpha = InputCommon.applyDeadzone(-rawY, Constants.PITCH_DEADZONE_FRAC)
		end
	end

	return
		forwardInput,
		strafeInput,
		collectiveInput,
		math.clamp(yawAlpha, -1, 1),
		math.clamp(pitchAlpha, -1, 1)
end

-- Return

return KeyboardAndMouse

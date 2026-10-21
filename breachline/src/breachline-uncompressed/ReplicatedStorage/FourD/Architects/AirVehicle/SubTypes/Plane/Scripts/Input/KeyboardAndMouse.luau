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

function KeyboardAndMouse.poll(): (number, number)
	if Camera.isFreeRotateActive() then
		return 0, 0
	end

	local mouse = UserInputService:GetMouseLocation()
	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize

	local pitchAlpha = 0
	local rotAlpha = 0

	if viewport.Y > 0 then
		local rawY = (mouse.Y - viewport.Y * 0.5) / (viewport.Y * 0.5)
		pitchAlpha = InputCommon.applyDeadzone(-rawY, Constants.MOUSE_DEADZONE_FRAC)
	end

	if viewport.X > 0 then
		local rawX = (mouse.X - viewport.X * 0.5) / (viewport.X * 0.5)
		rotAlpha = InputCommon.applyDeadzone(-rawX, Constants.MOUSE_DEADZONE_FRAC)
	end

	return math.clamp(pitchAlpha, -1, 1), math.clamp(rotAlpha, -1, 1)
end

-- Return

return KeyboardAndMouse

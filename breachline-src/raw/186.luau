--[[
	File: Touch.luau
]]--

-- Root

local Touch = {}

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local TouchButtons = require(FourD:WaitForChild("Common"):WaitForChild("TouchButtons"))

local Constants = require(script.Parent.Parent.Constants)

local touchGuiTemplate = script.TouchGui

-- Module State

local mobilePitchAlpha = 0
local mobileRotAlpha = 0
local actionsBound = false
local gui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}

-- Local Functions

local function getLocalCharacter(): Model?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return nil end
	return localPlayer.Character
end

-- Public Functions

function Touch.poll(): (number, number)
	local character = getLocalCharacter()
	if not character then return 0, 0 end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return 0, 0 end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < Constants.MOBILE_INPUT_DEADZONE then
		return 0, 0
	end

	local camera = Workspace.CurrentCamera
	local camLook = camera.CFrame.LookVector
	local camYaw = math.atan2(camLook.X, camLook.Z)
	local camYawCF = CFrame.Angles(0, camYaw, 0)
	local localMove = camYawCF:VectorToObjectSpace(Vector3.new(moveDir.X, 0, moveDir.Z))

	local pitchAlpha = -localMove.Z
	local rotAlpha = localMove.X

	pitchAlpha = math.clamp(pitchAlpha + mobilePitchAlpha, -1, 1)
	rotAlpha = math.clamp(rotAlpha + mobileRotAlpha, -1, 1)

	return pitchAlpha, rotAlpha
end

function Touch.bindMobileActions(unmountRemote: RemoteEvent, throttleAdjuster: (delta: number) -> ())
	if actionsBound then return end
	if not UserInputService.TouchEnabled then return end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	actionsBound = true

	local screen = touchGuiTemplate:Clone()
	screen.Parent = playerGui
	gui = screen

	local controls = screen.Controls
	table.insert(connections, TouchButtons.bindTap(controls.ThrottleUpButton, function()
		throttleAdjuster(Constants.MOBILE_THROTTLE_STEP)
	end))
	table.insert(connections, TouchButtons.bindTap(controls.ThrottleDownButton, function()
		throttleAdjuster(-Constants.MOBILE_THROTTLE_STEP)
	end))
	table.insert(connections, TouchButtons.bindTap(screen.Misc.ExitButton, function()
		unmountRemote:FireServer()
	end))
	table.insert(connections, TouchButtons.watchScale(screen))
end

function Touch.unbindMobileActions()
	if not actionsBound then return end
	actionsBound = false

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)

	if gui then
		gui:Destroy()
		gui = nil
	end
end

function Touch.reset()
	mobilePitchAlpha = 0
	mobileRotAlpha = 0
end

-- Return

return Touch

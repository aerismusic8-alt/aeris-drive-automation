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

local actionsBound = false
local mobileCollectiveInput = 0
local gui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}

-- Local Functions

local function getLocalCharacter(): Model?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return nil end
	return localPlayer.Character
end

-- Public Functions

function Touch.poll(): (number, number, number)
	local character = getLocalCharacter()
	if not character then return 0, 0, mobileCollectiveInput end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return 0, 0, mobileCollectiveInput end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < Constants.MOBILE_INPUT_DEADZONE then
		return 0, 0, mobileCollectiveInput
	end

	local cameraLook = Workspace.CurrentCamera.CFrame.LookVector
	local heading = Vector3.new(cameraLook.X, 0, cameraLook.Z)
	if heading.Magnitude < 1e-3 then
		return 0, 0, mobileCollectiveInput
	end
	heading = heading.Unit

	local right = heading:Cross(Vector3.yAxis)
	if right.Magnitude > 1e-3 then
		right = right.Unit
	else
		right = Vector3.xAxis
	end

	local moveHorizontal = Vector3.new(moveDir.X, 0, moveDir.Z)
	local forwardComponent = moveHorizontal:Dot(heading)
	local lateralComponent = moveHorizontal:Dot(right)

	local forwardInput = math.clamp(forwardComponent, -1, 1)
	local strafeInput = math.clamp(lateralComponent, -1, 1)

	return forwardInput, strafeInput, mobileCollectiveInput
end

function Touch.bindMobileActions(unmountRemote: RemoteEvent)
	if actionsBound then return end
	if not UserInputService.TouchEnabled then return end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	actionsBound = true

	local screen = touchGuiTemplate:Clone()
	screen.Parent = playerGui
	gui = screen

	local controls = screen.Controls
	for _, connection in ipairs(TouchButtons.bindHold(controls.AscendButton, function()
		mobileCollectiveInput = 1
	end, function()
		if mobileCollectiveInput > 0 then
			mobileCollectiveInput = 0
		end
	end)) do
		table.insert(connections, connection)
	end

	for _, connection in ipairs(TouchButtons.bindHold(controls.DescendButton, function()
		mobileCollectiveInput = -1
	end, function()
		if mobileCollectiveInput < 0 then
			mobileCollectiveInput = 0
		end
	end)) do
		table.insert(connections, connection)
	end

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
	mobileCollectiveInput = 0
end

-- Return

return Touch

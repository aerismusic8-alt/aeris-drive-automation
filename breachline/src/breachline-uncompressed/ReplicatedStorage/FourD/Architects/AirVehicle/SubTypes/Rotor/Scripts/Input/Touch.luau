--[[
	File: Touch.luau
]]--

-- Root

local Touch = {}

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local TouchButtons = require(FourD:WaitForChild("Common"):WaitForChild("TouchButtons"))

local Constants = require(script.Parent.Parent.Constants)

local touchGuiTemplate = script.TouchGui

-- Module State

local actionsBound = false
local pitchFollowMode = false
local mobileCollectiveInput = 0
local mobilePitchInput = 0
local gui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}

-- Local Functions

local function getLocalCharacter(): Model?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return nil end
	return localPlayer.Character
end

local function getRoot(): BasePart?
	local character = getLocalCharacter()
	if not character then return nil end
	local rootPart = character.PrimaryPart
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end
	return nil
end

-- Public Functions

function Touch.poll(): (number, number, number, number, number)
	local character = getLocalCharacter()
	if not character then return 0, 0, 0, 0, 0 end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return 0, 0, 0, 0, 0 end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < Constants.MOBILE_INPUT_DEADZONE then
		return 0, 0, mobileCollectiveInput, 0, mobilePitchInput
	end

	local root = getRoot()
	local heading: Vector3
	if root then
		local lookV = root.CFrame.LookVector
		heading = Vector3.new(lookV.X, 0, lookV.Z)
	else
		heading = Vector3.new(moveDir.X, 0, moveDir.Z)
	end

	if heading.Magnitude < 1e-3 then
		return 0, 0, mobileCollectiveInput, 0, mobilePitchInput
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
	local yawAlpha = math.clamp(lateralComponent * Constants.TOUCH_YAW_SENSITIVITY, -1, 1)

	return forwardInput, 0, mobileCollectiveInput, yawAlpha, mobilePitchInput
end

function Touch.bindMobileActions(unmountRemote: RemoteEvent, pitchFollow: boolean?)
	if actionsBound then return end
	if not UserInputService.TouchEnabled then return end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	actionsBound = true
	pitchFollowMode = pitchFollow == true

	local screen = touchGuiTemplate:Clone()
	screen.Parent = playerGui
	gui = screen

	local controls = screen.Controls
	local onUp, offUp, onDown, offDown

	if pitchFollowMode then
		-- Free-flight mobile: the two vertical buttons drive nose pitch instead
		-- of a pure collective; forward thrust then climbs or dives along it.
		onUp = function()
			mobilePitchInput = 1
		end
		offUp = function()
			if mobilePitchInput > 0 then
				mobilePitchInput = 0
			end
		end
		onDown = function()
			mobilePitchInput = -1
		end
		offDown = function()
			if mobilePitchInput < 0 then
				mobilePitchInput = 0
			end
		end
	else
		onUp = function()
			mobileCollectiveInput = 1
		end
		offUp = function()
			if mobileCollectiveInput > 0 then
				mobileCollectiveInput = 0
			end
		end
		onDown = function()
			mobileCollectiveInput = -1
		end
		offDown = function()
			if mobileCollectiveInput < 0 then
				mobileCollectiveInput = 0
			end
		end
	end

	for _, connection in ipairs(TouchButtons.bindHold(controls.AscendButton, onUp, offUp)) do
		table.insert(connections, connection)
	end
	for _, connection in ipairs(TouchButtons.bindHold(controls.DescendButton, onDown, offDown)) do
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

	pitchFollowMode = false
end

function Touch.reset()
	mobileCollectiveInput = 0
	mobilePitchInput = 0
end

-- Return

return Touch

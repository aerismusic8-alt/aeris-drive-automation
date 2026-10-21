--[[
	File: Input/init.luau
]]--

-- Root

local Input = {}

-- Roblox Services

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Keybinds = require(FourD.Common.Keybinds)

local Constants = require(script.Parent.Parent.Constants)

-- Constants

local KEYBINDS_SET_ID = "WheeledVehicle.Board"
local PRIORITY_HIGH = Enum.ContextActionPriority.High.Value
local THUMBSTICK_DEADZONE = 0.15
local THUMBSTICK_BIND_NAME = "BoardThumbstick"

-- Public Functions

function Input.start(boardRig: Model, _: Model): () -> ()
	local remotes = boardRig:WaitForChild("Remotes")
	local ollieRemote = remotes:WaitForChild(Constants.OLLIE_REMOTE_NAME)
	local redressRemote = remotes:WaitForChild(Constants.REDRESS_REMOTE_NAME)

	local throttleHeld = false
	local reverseHeld = false
	local leftHeld = false
	local rightHeld = false
	local thumbstickX = 0
	local thumbstickY = 0
	local throttleKey = Keybinds.getKeyboardKey(KEYBINDS_SET_ID, "Throttle")
	local reverseKey = Keybinds.getKeyboardKey(KEYBINDS_SET_ID, "Reverse")
	local localPlayer = Players.LocalPlayer

	local function handleOllie(state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			ollieRemote:FireServer()
		end

		return Enum.ContextActionResult.Sink
	end

	local function handleRedress(state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			redressRemote:FireServer()
		end

		return Enum.ContextActionResult.Sink
	end

	local function makeHoldHandler(setter: (boolean) -> ()): (Enum.UserInputState, InputObject) -> Enum.ContextActionResult
		return function(state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				setter(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				setter(false)
			end

			return Enum.ContextActionResult.Sink
		end
	end

	local function handleThumbstick(_: string, _: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		thumbstickX = input.Position.X
		thumbstickY = input.Position.Y
		return Enum.ContextActionResult.Pass
	end

	local mainHandle = Keybinds.bindActions(KEYBINDS_SET_ID, {
		Throttle = makeHoldHandler(function(v: boolean) throttleHeld = v end),
		Reverse = makeHoldHandler(function(v: boolean) reverseHeld = v end),
		SteerLeft = makeHoldHandler(function(v: boolean) leftHeld = v end),
		SteerRight = makeHoldHandler(function(v: boolean) rightHeld = v end),
	}, nil, { Priority = PRIORITY_HIGH })

	local ollieHandle = Keybinds.bindActions(KEYBINDS_SET_ID, {
		Ollie = handleOllie,
	}, nil, { Priority = PRIORITY_HIGH, CreateTouchButton = true })

	local redressHandle = Keybinds.bindActions(KEYBINDS_SET_ID, {
		Redress = handleRedress,
	}, nil, { Priority = PRIORITY_HIGH, CreateTouchButton = true })

	ContextActionService:BindActionAtPriority(
		THUMBSTICK_BIND_NAME,
		handleThumbstick,
		false,
		PRIORITY_HIGH,
		Enum.KeyCode.Thumbstick1
	)

	local directionalConn = RunService.Heartbeat:Connect(function()
		local keyboardAllowed = UserInputService:GetFocusedTextBox() == nil
		local polledThrottle = keyboardAllowed and throttleKey ~= nil
			and UserInputService:IsKeyDown(throttleKey :: Enum.KeyCode)
		local polledReverse = keyboardAllowed and reverseKey ~= nil
			and UserInputService:IsKeyDown(reverseKey :: Enum.KeyCode)
		local kbThrottle = ((throttleHeld or polledThrottle) and 1 or 0)
			- ((reverseHeld or polledReverse) and 1 or 0)
		local kbSteer = (rightHeld and 1 or 0) - (leftHeld and 1 or 0)
		local touchThrottle = 0
		local touchSteer = 0
		if UserInputService.TouchEnabled and localPlayer then
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local chassis = boardRig.PrimaryPart or boardRig:FindFirstChild("Chassis", true)
			if humanoid and chassis and chassis:IsA("BasePart") then
				local moveDir = humanoid.MoveDirection
				local flatLook = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
				local flatRight = Vector3.new(chassis.CFrame.RightVector.X, 0, chassis.CFrame.RightVector.Z)
				if moveDir.Magnitude > 0.01 and flatLook.Magnitude > 0.01 and flatRight.Magnitude > 0.01 then
					touchThrottle = math.clamp(moveDir:Dot(flatLook.Unit), -1, 1)
					touchSteer = math.clamp(moveDir:Dot(flatRight.Unit), -1, 1)
				end
			end
		end

		local throttle: number
		if math.abs(thumbstickY) > THUMBSTICK_DEADZONE then
			throttle = math.clamp(thumbstickY, -1, 1)
		elseif math.abs(touchThrottle) > THUMBSTICK_DEADZONE then
			throttle = touchThrottle
		else
			throttle = kbThrottle
		end

		local steer: number
		if math.abs(thumbstickX) > THUMBSTICK_DEADZONE then
			steer = math.clamp(thumbstickX, -1, 1)
		elseif math.abs(touchSteer) > THUMBSTICK_DEADZONE then
			steer = touchSteer
		else
			steer = kbSteer
		end

		boardRig:SetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE, throttle)
		boardRig:SetAttribute(Constants.STEERING_INPUT_ATTRIBUTE, steer)
	end)

	return function()
		mainHandle:Destroy()
		ollieHandle:Destroy()
		redressHandle:Destroy()
		ContextActionService:UnbindAction(THUMBSTICK_BIND_NAME)

		directionalConn:Disconnect()

		boardRig:SetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE, 0)
		boardRig:SetAttribute(Constants.STEERING_INPUT_ATTRIBUTE, 0)
	end
end

-- Return

return Input

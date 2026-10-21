local Players = game:GetService("Players")

local Constants = require(script.Parent.Parent.Constants)

local car = script.Parent.Parent.Parent
local driverSeat = car.DriverSeat
local chassis = car.Chassis
local inputs = car.Inputs
local redressOrientation = car.Redress.RedressOrientation
local balanceTorque = chassis:FindFirstChild("BalanceTorque")
local drivePrompt = chassis.DrivePromptAttachment.DrivePrompt
local engine = car.Engine

local UNOCCUPIED_BRAKE_TORQUE = 50000

local owner = nil

local riderMasslessState: { [BasePart]: boolean } = {}
local function setRiderMassless(character: Model?, massless: boolean)
	if massless then
		if not character then
			return
		end
		table.clear(riderMasslessState)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				riderMasslessState[part] = part.Massless
				part.Massless = true
			end
		end
	else
		for part, original in riderMasslessState do
			if part.Parent then
				part.Massless = original
			end
		end
		table.clear(riderMasslessState)
	end
end

local function setBrake(enabled: boolean)
	local brakeTorque = if enabled then UNOCCUPIED_BRAKE_TORQUE else 0
	for _, motorName in { "WheelRMotor", "WheelFMotor" } do
		local motor = engine:FindFirstChild(motorName)
		if motor then
			motor.AngularVelocity = 0
			motor.MotorMaxTorque = brakeTorque
		end
	end
end

local function setUprightTarget()
	local _, yaw, _ = chassis.CFrame:ToOrientation()
	redressOrientation.CFrame = CFrame.Angles(0, yaw, 0)
end

-- Force a character to sit in the car
local function enter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "No humanoid found!")
	if driverSeat.Occupant then
		return
	end

	driverSeat:Sit(humanoid)
end

-- Set network ownership when a player sits in the car
local function onOccupantChanged()
	local humanoid = driverSeat.Occupant
	drivePrompt.Enabled = humanoid == nil

	if humanoid then
		local character = humanoid.Parent
		setRiderMassless(character, true)
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			chassis:SetNetworkOwner(player)
		end
		redressOrientation.Enabled = false
		if balanceTorque then
			balanceTorque.Enabled = true
		end
		setBrake(false)
	else
		setRiderMassless(nil, false)
		-- Zero out all inputs when no humanoid is in the seat to prevent the car from driving itself
		inputs:SetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE, 0)
		inputs:SetAttribute(Constants.STEERING_INPUT_ATTRIBUTE, 0)
		inputs:SetAttribute(Constants.HAND_BRAKE_INPUT_ATTRIBUTE, false)
		inputs:SetAttribute(Constants.NITRO_INPUT_ATTRIBUTE, false)

		setUprightTarget()
		redressOrientation.Enabled = true
		if balanceTorque then
			balanceTorque.Enabled = false
			balanceTorque.Torque = Vector3.zero
		end
		setBrake(true)
	end
end

-- Allow the player to enter the car when they trigger the drive proximity prompt
local function onDrivePromptTriggered(player: Player)
	if owner then
		if player ~= owner then
			return
		end
	end

	local character = player.Character
	if character then
		enter(character)
	end
end

local function updateOwner()
	-- Since instance references can't be stored in attributes, the car owner is stored by UserId
	local ownerUserId = car:GetAttribute(Constants.CAR_OWNER_ATTRIBUTE)
	if ownerUserId then
		owner = Players:GetPlayerByUserId(ownerUserId)
	else
		owner = nil
	end

	-- Update the drive prompt to show who the car belongs to
	if owner then
		drivePrompt.ObjectText = `{owner.DisplayName}'s car`
	else
		drivePrompt.ObjectText = ""
	end
end

local function initialize()
	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
	drivePrompt.Triggered:Connect(onDrivePromptTriggered)

	inputs:GetAttributeChangedSignal(Constants.KEYBOARD_ENTER_KEY_CODE_ATTRIBUTE):Connect(function()
		drivePrompt.KeyboardKeyCode = inputs:GetAttribute(Constants.KEYBOARD_ENTER_KEY_CODE_ATTRIBUTE)
	end)
	inputs:GetAttributeChangedSignal(Constants.GAMEPAD_ENTER_KEY_CODE_ATTRIBUTE):Connect(function()
		drivePrompt.GamepadKeyCode = inputs:GetAttribute(Constants.GAMEPAD_ENTER_KEY_CODE_ATTRIBUTE)
	end)
	car:GetAttributeChangedSignal(Constants.CAR_OWNER_ATTRIBUTE):Connect(updateOwner)

	drivePrompt.KeyboardKeyCode = inputs:GetAttribute(Constants.KEYBOARD_ENTER_KEY_CODE_ATTRIBUTE)
	drivePrompt.GamepadKeyCode = inputs:GetAttribute(Constants.GAMEPAD_ENTER_KEY_CODE_ATTRIBUTE)

	updateOwner()
	onOccupantChanged()
end

initialize()
X
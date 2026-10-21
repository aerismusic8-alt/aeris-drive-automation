local Players = game:GetService("Players")

local Constants = require(script.Parent.Parent.Constants)

local car = script.Parent.Parent.Parent
local driverSeat = car.DriverSeat
local chassis = car.Chassis
local inputs = car.Inputs
local drivePrompt = chassis.DrivePromptAttachment.DrivePrompt

local owner = nil

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
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			chassis:SetNetworkOwner(player)
		end
	else
		-- Zero out all inputs when no humanoid is in the seat to prevent the car from driving itself
		inputs:SetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE, 0)
		inputs:SetAttribute(Constants.STEERING_INPUT_ATTRIBUTE, 0)
		inputs:SetAttribute(Constants.HAND_BRAKE_INPUT_ATTRIBUTE, false)
		inputs:SetAttribute(Constants.NITRO_INPUT_ATTRIBUTE, false)
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
	-- The seat may already be occupied when this script starts (e.g. a car cloned in and
	-- immediately sat in), in which case the Occupant signal above will never fire for that driver.
	onOccupantChanged()
end

initialize()
.

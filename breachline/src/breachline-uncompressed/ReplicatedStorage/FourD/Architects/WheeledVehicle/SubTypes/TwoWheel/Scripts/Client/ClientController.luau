-- GENERATED WRAPPER around upstream ClientController.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
-- Don't run if this is under ReplicatedStorage
if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then
	return
end

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local clientFolder = script.Parent
local scriptsFolder = clientFolder.Parent
local car = scriptsFolder.Parent

local Constants = require(scriptsFolder:WaitForChild("Constants"))
local Controller = require(scriptsFolder:WaitForChild("Controller"))
local Input = require(clientFolder:WaitForChild("Input"))
local Speedometer = require(clientFolder:WaitForChild("Speedometer"))
local setJumpingEnabled = require(script:WaitForChild("setJumpingEnabled"))
local disconnectAndClear = require(clientFolder:WaitForChild("disconnectAndClear"))
local HelpUI = require(ReplicatedStorage:WaitForChild("FourD").Common.HelpUI)

local destructionHandlerTemplate = script:WaitForChild("DestructionHandler")
local player = Players.LocalPlayer
local driverSeat = car:WaitForChild("DriverSeat")
local engine = car:WaitForChild("Engine")
local remotes = car:WaitForChild("Remotes")
local setNitroEnabledRemote = remotes:WaitForChild("SetNitroEnabled")
local animations = car:WaitForChild("Animations")
local driveAnimation = animations:WaitForChild("DriveAnimation")

-- The HelpUI states + injected state-name attribute live on the wrapper vehicle
-- model (the canonical model the capability registers against), not this rig.
local vehicleModelRef = driverSeat:WaitForChild("VehicleModelRef", 5)
local helpModel: Instance = if vehicleModelRef and vehicleModelRef:IsA("ObjectValue") and vehicleModelRef.Value
	then vehicleModelRef.Value
	else car

local isControlling = false
local connections = {}
local driveAnimationTrack = nil
local PromptSuppression = require(game:GetService("ReplicatedStorage"):WaitForChild("FourD"):WaitForChild("Common"):WaitForChild("PromptSuppression"))
local promptSuppressionHeld = false

local function startControlling()
	if isControlling then
		return
	end
	isControlling = true

	-- Hide all proximity prompts (including this vehicle's mount prompt) while driving.
	if not promptSuppressionHeld then
		promptSuppressionHeld = true
		PromptSuppression.acquire()
	end

	-- Stop the player from jumping out the seat since a separate key is bound to exit the car.
	local character = player.Character
	if character then
		setJumpingEnabled(character, false)

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				driveAnimationTrack = animator:LoadAnimation(driveAnimation)
				driveAnimationTrack:Play()
			end
		end
	end

	-- Connect the Controller's update function to RunService.Stepped.
	-- Stepped is used here since it fires prior to the physics simulation, and the controller
	-- updates the physics constraints on the car.
	table.insert(
		connections,
		RunService.Stepped:Connect(function(_, deltaTime: number)
			Controller:update(deltaTime)
		end)
	)

	table.insert(
		connections,
		engine:GetAttributeChangedSignal(Constants.NITRO_ENABLED_ATTRIBUTE):Connect(function()
			local isNitroEnabled = engine:GetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE)
			setNitroEnabledRemote:FireServer(isNitroEnabled)
		end)
	)

	table.insert(
		connections,
		UserInputService.JumpRequest:Connect(function()
			Controller:jump()
		end)
	)

	-- Camera:enable() -- TEMP DISABLED
	Input:enable()
	Speedometer:enable()

	HelpUI.applyRole(helpModel, "WheeledVehicle.TwoWheel", "HelpUI_DriverState")
end

local function stopControlling()
	if not isControlling then
		return
	end
	isControlling = false

	if promptSuppressionHeld then
		promptSuppressionHeld = false
		PromptSuppression.release()
	end

	-- Camera:disable() -- TEMP DISABLED
	Input:disable()
	Speedometer:disable()

	HelpUI.clearRole(helpModel)

	disconnectAndClear(connections)

	-- Reset the car Controller. If the car has been destroyed (i.e. is not parented anywhere in the DataModel) this can be skipped.
	if car:IsDescendantOf(game) then
		Controller:reset()
	end

	local character = player.Character
	if character then
		setJumpingEnabled(character, true)
	end

	if driveAnimationTrack then
		driveAnimationTrack:Stop()
		driveAnimationTrack = nil
	end
end

local function onOccupantChanged()
	local isOccupiedByLocalPlayer = false

	local humanoid = driverSeat.Occupant
	if humanoid then
		local character = humanoid.Parent
		local playerInSeat = Players:GetPlayerFromCharacter(character)
		if playerInSeat == player then
			isOccupiedByLocalPlayer = true
		end
	end

	if isOccupiedByLocalPlayer then
		startControlling()
	else
		stopControlling()
	end
end

-- When using Deferred signal mode: since this script is parented to the car, destroying the car will clean up
-- all connections (including .Destroying) before they can actually execute.
-- To avoid this, we'll use a slightly hacky solution and clone a listener script into PlayerScripts.
-- This script will continue running after the car is destroyed and allow us to properly clean up when the car is destroyed.
local function setupDestructionHandler()
	local destructionHandler = destructionHandlerTemplate:Clone()
	destructionHandler.Parent = player.PlayerScripts
	destructionHandler.Enabled = true

	-- Defer firing the BindableEvent so the script is able to initialize first
	task.defer(function()
		destructionHandler.BindToCar:Fire(car, stopControlling)
	end)
end

setupDestructionHandler()
driverSeat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
-- The vehicle only replicates to this client after it's parented to Workspace, so a rider seated
-- at spawn is already in the seat by the time this runs and the signal above never fires.
onOccupantChanged()

end

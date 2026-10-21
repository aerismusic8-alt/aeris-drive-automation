-- GENERATED WRAPPER around upstream DriverClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
Train5 DriverClient - binds the exit action and shows the driver help overlay
while the local player occupies the driver seat, swapping to the rider overlay
while autoMode is on. Cloned into the engine car model by bind(); help state and
keybinds are scoped to the root train model.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Keybinds = require(FourD.Common.Keybinds)
local HelpUI = require(FourD.Common.HelpUI)

local carModel = script.Parent
if not carModel:IsA("Model") then return end

local seat = carModel:FindFirstChildWhichIsA("VehicleSeat")
if not seat then
	-- Dispatched from a scan, so this body can run before the rest
	-- of the model replicates. Returning here is permanent: the
	-- dispatcher starts a host once and never revisits it.
	local seatDeadline = os.clock() + 10
	repeat
		task.wait()
		seat = carModel:FindFirstChildWhichIsA("VehicleSeat")
	until seat or os.clock() >= seatDeadline
end
if not seat then return end

local rootModel = carModel

local function resolveRoot(): Model
	if rootModel:GetAttribute("driveMode") ~= nil then
		return rootModel
	end

	local candidate: Instance? = carModel
	while candidate do
		if candidate:IsA("Model") and candidate:GetAttribute("driveMode") ~= nil then
			rootModel = candidate
			break
		end

		candidate = candidate.Parent
	end

	return rootModel
end

local player = Players.LocalPlayer
local bindHandle = nil
local boundModel = nil
local autoModeConnection = nil

local function isLocalOccupant(): boolean
	local occupant = seat.Occupant
	local character = player.Character
	return occupant ~= nil and character ~= nil and occupant:IsDescendantOf(character)
end

local function onExit(state: Enum.UserInputState): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		local occupant = seat.Occupant
		if occupant then
			occupant:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	return nil
end

local function currentRoleAttribute(model: Model): string
	if seat:IsA("VehicleSeat") and model:GetAttribute("autoMode") ~= true then
		return "HelpUI_DriverState"
	end

	return "HelpUI_RiderState"
end

local function updateBinding()
	if isLocalOccupant() then
		if not bindHandle then
			boundModel = resolveRoot()
			bindHandle = Keybinds.bindActions("Trackable", { Exit = onExit }, boundModel)

			if not autoModeConnection then
				autoModeConnection = boundModel:GetAttributeChangedSignal("autoMode"):Connect(updateBinding)
			end
		end

		HelpUI.applyRole(boundModel, "Trackable", currentRoleAttribute(boundModel))
	elseif bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
		HelpUI.clearRole(boundModel)
		boundModel = nil
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(updateBinding)

script.Destroying:Connect(function()
	if autoModeConnection then
		autoModeConnection:Disconnect()
		autoModeConnection = nil
	end

	if bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
	end
end)

updateBinding()

end

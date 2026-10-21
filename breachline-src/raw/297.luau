-- GENERATED WRAPPER around upstream DriverClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
RollercoasterCart3 DriverClient - binds the exit action and shows the driver
or rider help overlay while the local player occupies this car's seat.
Cloned into each RollercoasterCart3 car model by bind().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Keybinds = require(FourD.Common.Keybinds)
local HelpUI = require(FourD.Common.HelpUI)

local carModel = script.Parent
if not carModel:IsA("Model") then return end

local seat = carModel:FindFirstChildWhichIsA("VehicleSeat") or carModel:FindFirstChildWhichIsA("Seat")
if not seat then
	-- Dispatched from a scan, so this body can run before the rest
	-- of the model replicates. Returning here is permanent: the
	-- dispatcher starts a host once and never revisits it.
	local seatDeadline = os.clock() + 10
	repeat
		task.wait()
		seat = carModel:FindFirstChildWhichIsA("VehicleSeat") or carModel:FindFirstChildWhichIsA("Seat")
	until seat or os.clock() >= seatDeadline
end
if not seat then return end

local rootModel = carModel
while rootModel and rootModel:GetAttribute("driveMode") == nil do
	rootModel = rootModel:FindFirstAncestorWhichIsA("Model")
end

rootModel = rootModel or carModel

local player = Players.LocalPlayer
local bindHandle = nil

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

local function currentRoleAttribute(): string
	if seat:IsA("VehicleSeat") and rootModel:GetAttribute("autoMode") ~= true then
		return "HelpUI_DriverState"
	end

	return "HelpUI_RiderState"
end

local function updateBinding()
	if isLocalOccupant() then
		if not bindHandle then
			bindHandle = Keybinds.bindActions("Trackable", { Exit = onExit }, rootModel)
		end

		HelpUI.applyRole(rootModel, "Trackable", currentRoleAttribute())
	elseif bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
		HelpUI.clearRole(rootModel)
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(updateBinding)
rootModel:GetAttributeChangedSignal("autoMode"):Connect(updateBinding)

script.Destroying:Connect(function()
	if bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
	end
end)

updateBinding()

end

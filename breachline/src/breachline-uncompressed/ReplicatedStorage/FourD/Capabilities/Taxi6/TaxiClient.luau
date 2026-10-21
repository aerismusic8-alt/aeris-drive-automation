-- GENERATED WRAPPER around upstream TaxiClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
if not script.Parent:IsA("Model") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage.FourD.Common.Keybinds)

local model = script.Parent
local player = Players.LocalPlayer

local toggleEvent = model:FindFirstChild("TaxiSignToggleEvent")
if not toggleEvent or not toggleEvent:IsA("RemoteEvent") then return end

local toggleKey = Keybinds.getKeyboardKey("Taxi6", "Toggle", model) or Enum.KeyCode.T

local function isDriver(): boolean
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then return false end
	local occupant = seat.Occupant
	if not occupant then return false end
	return occupant.Parent == player.Character
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode ~= toggleKey then return end
	if not isDriver() then return end

	toggleEvent:FireServer()
end)

end

-- GENERATED WRAPPER around upstream SchoolBusClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
if not script.Parent:IsA("Model") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Keybinds = require(ReplicatedStorage.FourD.Common.Keybinds)

local KEYBINDS_SET_ID = "SchoolBus6"
local TOGGLE_BIND_ID = "ToggleStopSign"

local model = script.Parent
local player = Players.LocalPlayer

local toggleEvent = model:FindFirstChild("StopSignToggleEvent")
if not toggleEvent or not toggleEvent:IsA("RemoteEvent") then return end

local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
if not seat then
	-- Dispatched from a scan, so this body can run before the rest
	-- of the model replicates. Returning here is permanent: the
	-- dispatcher starts a host once and never revisits it.
	local seatDeadline = os.clock() + 10
	repeat
		task.wait()
		seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	until seat or os.clock() >= seatDeadline
end
if not seat then return end

local bindHandle = nil

local function onToggle(state: Enum.UserInputState): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		toggleEvent:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

local function isDriver(): boolean
	local occupant = seat.Occupant
	return occupant ~= nil and occupant.Parent == player.Character
end

local function refresh()
	if isDriver() then
		if bindHandle then return end
		bindHandle = Keybinds.bindActions(KEYBINDS_SET_ID, {
			[TOGGLE_BIND_ID] = onToggle,
		}, model, { CreateTouchButton = true })
	elseif bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(refresh)
refresh()

end

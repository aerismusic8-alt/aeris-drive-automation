-- GENERATED WRAPPER around upstream SeatPromptClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
RollercoasterCart3 SeatPromptClient - hides all ProximityPrompts for the
local player while they occupy this cart's seat. Cloned into each
RollercoasterCart3 model by bind().
]]

local Players = game:GetService("Players")
local PromptSuppression = require(game:GetService("ReplicatedStorage"):WaitForChild("FourD"):WaitForChild("Common"):WaitForChild("PromptSuppression"))

local model = script.Parent
if not model:IsA("Model") then return end

local seat = model:FindFirstChildWhichIsA("VehicleSeat") or model:FindFirstChildWhichIsA("Seat")
if not seat then
	-- Dispatched from a scan, so this body can run before the rest
	-- of the model replicates. Returning here is permanent: the
	-- dispatcher starts a host once and never revisits it.
	local seatDeadline = os.clock() + 10
	repeat
		task.wait()
		seat = model:FindFirstChildWhichIsA("VehicleSeat") or model:FindFirstChildWhichIsA("Seat")
	until seat or os.clock() >= seatDeadline
end
if not seat then return end

local player = Players.LocalPlayer
local suppressing = false

local function isLocalOccupant(): boolean
	local occupant = seat.Occupant
	local character = player.Character
	return occupant ~= nil and character ~= nil and occupant:IsDescendantOf(character)
end

local function updateSuppression()
	local shouldSuppress = isLocalOccupant()
	if shouldSuppress == suppressing then return end

	suppressing = shouldSuppress
	if shouldSuppress then
		PromptSuppression.acquire()
	else
		PromptSuppression.release()
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(updateSuppression)

script.Destroying:Connect(function()
	if suppressing then
		suppressing = false
		PromptSuppression.release()
	end
end)

updateSuppression()

end
R
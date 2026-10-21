--[[
Turret5 MountPrompt - seats a player at the turret when they trigger the
ProximityPrompt. Cloned into each Turret5 model by the capability's bind().
]]

local model = script.Parent
if not model:IsA("Model") then return end

local seat = model:FindFirstChild("DriverSeat")
if not seat or not seat:IsA("VehicleSeat") then return end

local prompt = seat:FindFirstChild("MountPrompt")
if not prompt or not prompt:IsA("ProximityPrompt") then return end

local function updatePromptState()
	prompt.Enabled = seat.Occupant == nil
end

prompt.Triggered:Connect(function(player: Player)
	if seat.Occupant then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	seat:Sit(humanoid)
end)

seat:GetPropertyChangedSignal("Occupant"):Connect(updatePromptState)
updatePromptState()

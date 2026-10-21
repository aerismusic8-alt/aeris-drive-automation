--[[
RollercoasterCart3 SeatPrompt - seats a player in the cart when they trigger
the ProximityPrompt. Cloned into each RollercoasterCart3 model by bind().
]]

local model = script.Parent
if not model:IsA("Model") then return end

local seat = model:FindFirstChildWhichIsA("VehicleSeat") or model:FindFirstChildWhichIsA("Seat")
if not seat then return end

local prompt = seat:FindFirstChild("SeatPrompt")
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
q
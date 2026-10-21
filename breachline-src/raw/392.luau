-- Persisted authoritative siren toggle runtime.

local Players = game:GetService("Players")

local model = script.Parent
local toggleEvent = model:WaitForChild("SirenToggleEvent") :: RemoteEvent
local leftRef = script:WaitForChild("LeftStrobeRef") :: ObjectValue
local rightRef = script:WaitForChild("RightStrobeRef") :: ObjectValue
local left = leftRef.Value
local right = rightRef.Value

assert(left and left:IsA("Folder"), "LeftStrobeRef is invalid")
assert(right and right:IsA("Folder"), "RightStrobeRef is invalid")

local enabled = false
local function setEnabled(value: boolean)
	enabled = value
	model:SetAttribute("sirenEnabled", value)
	for _, wrapper in { left, right } do
		if value and wrapper:GetAttribute("StrobeEnabled") ~= true then
			wrapper:SetAttribute("StrobeStartTime", workspace:GetServerTimeNow())
		end
		wrapper:SetAttribute("StrobeEnabled", value)
	end
end

toggleEvent.OnServerEvent:Connect(function(player)
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local occupant = seat and seat.Occupant
	if not occupant or Players:GetPlayerFromCharacter(occupant.Parent) ~= player then return end
	setEnabled(not enabled)
end)

script:SetAttribute("RuntimeVersion", 1)
script:SetAttribute("RuntimeReady", true)
d3
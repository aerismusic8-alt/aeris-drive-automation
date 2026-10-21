-- Instructions for the new setup:
-- 1. This is the SERVER SCRIPT. Place it directly inside the VehicleSeat.
-- 2. Create LocalScripts named "VehicleExitHandler" and "VehicleCameraHandler", and place them INSIDE this server script.
-- 3. Make sure the "VehicleExitHandler" LocalScript is DISABLED by default in its properties.
-- 4. Paste the client-side logic into the "VehicleExitHandler" LocalScript.

--========================================================================
-- Configuration
--========================================================================
local Players = game:GetService("Players")
local seat = script.Parent
assert(seat:IsA("VehicleSeat") or seat:IsA("Seat"), "This script must be a direct child of a VehicleSeat or Seat.")

-- Find the LocalScript template that is a child of this server script
local cameraScriptTemplate = script:FindFirstChild("VehicleCameraHandler")
assert(
	cameraScriptTemplate and cameraScriptTemplate:IsA("LocalScript"),
	"A disabled LocalScript named 'VehicleCameraHandler' must be a child of this script."
)

--========================================================================
-- Core Logic (Server Script inside the VehicleSeat/Seat)
--========================================================================

local originalLTM = {}
local sittingPlayer = nil
local vehicle = seat:FindFirstChild("VehicleModelRef").Value

local function makeSittingPlayerInvisible()
	for _, desc in ipairs(sittingPlayer.Character:GetDescendants()) do
		if desc:IsA("BasePart") or desc:IsA("MeshPart") or desc:IsA("Decal") then
			originalLTM[desc] = desc.Transparency
			desc.Transparency = 1
		end
	end
end

local function restoreSittingPlayerVisibility()
	for part, ltm in pairs(originalLTM) do
		if part and part.Parent then
			part.Transparency = ltm or 0
		end
	end
end

-- When a player attempts to exit the vehicle, use special logic to eject the player
-- outside of the containing vehicle. Otherwise, they might get stuck in the vehicle
local function repositionSittingPlayer()
	local EXTRA_EXIT_BUFFER = 5
	local EXIT_UP_OFFSET = 3
	local vehicleCFrame, vehicleSize = vehicle:GetBoundingBox()
	local leftVector = -vehicleCFrame.RightVector
	local exitSideOffset = (vehicleSize.X / 2) + EXTRA_EXIT_BUFFER
	local exitPosition = vehicleCFrame.Position + (leftVector * exitSideOffset) + Vector3.new(0, EXIT_UP_OFFSET, 0)
	sittingPlayer.Character:PivotTo(CFrame.new(exitPosition))
end

-- Cleanup when a player leaves the seat
local function processSittingPlayerLeaving()
	restoreSittingPlayerVisibility()
	if sittingPlayer and sittingPlayer.Character then
		repositionSittingPlayer()
	end
	local playerGui = sittingPlayer and sittingPlayer:FindFirstChild("PlayerGui")
	if playerGui then
		local oldCamScript = playerGui:FindFirstChild("VehicleCameraHandler_Instance")
		if oldCamScript then
			oldCamScript:Destroy()
		end
	end
	originalLTM = {}
	sittingPlayer = nil
end

-- This function runs when a player sits in or gets out of THIS specific seat.
seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local humanoid = seat.Occupant
	-- Player SAT DOWN
	if humanoid then
		if sittingPlayer then
			processSittingPlayerLeaving()
		end
		sittingPlayer = Players:GetPlayerFromCharacter(humanoid.Parent)
		if sittingPlayer then
			local cameraScriptClone = cameraScriptTemplate:Clone()
			cameraScriptClone.Name = "VehicleCameraHandler_Instance"
			cameraScriptClone.Parent = sittingPlayer:WaitForChild("PlayerGui")
			cameraScriptClone.Disabled = false
			local vehicleModelValue = Instance.new("ObjectValue")
			vehicleModelValue.Name = "VehicleModel"
			vehicleModelValue.Value = vehicle
			vehicleModelValue.Parent = cameraScriptClone
		end
		-- Player GOT UP (or was removed)
	else
		if sittingPlayer then
			processSittingPlayerLeaving()
		end
	end
end)

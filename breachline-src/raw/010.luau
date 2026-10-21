-- This LocalScript sets the player's camera zoom once based on vehicle size,
-- then restores the player's previous zoom limits and exits.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Expected to be provided by the server-side SeatEventHandler
local vehicleValue = script:FindFirstChild("VehicleModel") or script:WaitForChild("VehicleModel", 2)
local vehicle = vehicleValue and vehicleValue.Value or nil

if not vehicle then
	script:Destroy()
	return
end

-- Save current zoom bounds
local originalMinZoom = player.CameraMinZoomDistance
local originalMaxZoom = player.CameraMaxZoomDistance

-- Compute required distance to fit the whole vehicle in view
local camera = Workspace.CurrentCamera
if camera then
	local _, size = vehicle:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local fovRadians = math.rad(camera.FieldOfView)
	local requiredDistance = (maxDim * 0.5) / math.tan(fovRadians * 0.5)
	requiredDistance = requiredDistance * 1.5 -- padding

	-- Apply fixed zoom once
	player.CameraMinZoomDistance = requiredDistance
	player.CameraMaxZoomDistance = requiredDistance

	-- Ensure camera system applies the change this frame
	task.wait()

	-- Restore previous bounds, keeping max high enough so user can zoom back out if needed
	player.CameraMinZoomDistance = originalMinZoom
	player.CameraMaxZoomDistance = math.max(originalMaxZoom, requiredDistance)
end

script:Destroy()

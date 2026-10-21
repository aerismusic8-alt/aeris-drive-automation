local VRService = game:GetService("VRService")
local Workspace = game:GetService("Workspace")

local CameraModules = {
	ChaseCamera = require(script.ChaseCamera),
	InteriorCamera = require(script.InteriorCamera),
	FixedCamera = require(script.FixedCamera),
}
local CameraModes = require(script.CameraModes)

local camera = Workspace.CurrentCamera
local cycleCameraModeEvent = script.CycleCameraMode

local cycleCameraModeConnection = nil
local currentCameraModeIndex = 1
local enabled = false

-- Set the current mode and enable/disable the correct CameraModules
local function setMode(modeIndex: number)
	currentCameraModeIndex = modeIndex
	local currentModeInfo = CameraModes[currentCameraModeIndex]
	for name, module in CameraModules do
		if name == currentModeInfo.module then
			-- Enable the CameraModule and set parameters for the current mode
			module:setParameters(currentModeInfo.parameters)
			module:enable()
		else
			-- Disable other CameraModules
			module:disable()
		end
	end
end

-- Cycle to the next camera mode, wrapping around at the end
local function cycleCameraMode()
	local nextModeIndex = currentCameraModeIndex + 1
	if nextModeIndex > #CameraModes then
		nextModeIndex = 1
	end
	setMode(nextModeIndex)
end

local Camera = {}

function Camera:enable()
	if enabled then
		return
	end
	-- Custom camera is not enabled for VR devices, allowing the default VR vehicle camera to be used
	if VRService.VREnabled then
		return
	end

	enabled = true

	cycleCameraModeConnection = cycleCameraModeEvent.Event:Connect(cycleCameraMode)

	-- Set the CameraType to scriptable, since we are taking control of it
	camera.CameraType = Enum.CameraType.Scriptable
	-- Initialize with the current mode
	setMode(currentCameraModeIndex)
end

function Camera:disable()
	if not enabled then
		return
	end
	enabled = false

	if cycleCameraModeConnection then
		cycleCameraModeConnection:Disconnect()
		cycleCameraModeConnection = nil
	end

	-- Reset the camera back to CameraType.Custom to re-enable default camera controls
	camera.CameraType = Enum.CameraType.Custom

	-- Disable all CameraModules
	for _, module in CameraModules do
		module:disable()
	end
end

return Camera

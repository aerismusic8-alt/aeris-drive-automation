--[[
	The FixedCamera rigidly attaches the camera to an attachment on the car.
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local camera = Workspace.CurrentCamera

local RENDER_STEPPED_BIND_NAME = "CarFixedCamera"
local RENDER_STEPPED_BIND_PRIORITY = Enum.RenderPriority.Camera.Value

local enabled = false
local parameters = {
	attachment = nil,
}

local function update(_deltaTime: number)
	-- Set the camera CFrame to the currently set attachment's WorldCFrame
	camera.CFrame = parameters.attachment.WorldCFrame
end

local FixedCamera = {}

function FixedCamera:setParameters(newParameters: typeof(parameters))
	parameters = newParameters
end

function FixedCamera:enable()
	if enabled then
		return
	end
	enabled = true

	RunService:BindToRenderStep(RENDER_STEPPED_BIND_NAME, RENDER_STEPPED_BIND_PRIORITY, update)
end

function FixedCamera:disable()
	if not enabled then
		return
	end
	enabled = false

	RunService:UnbindFromRenderStep(RENDER_STEPPED_BIND_NAME)
end

return FixedCamera

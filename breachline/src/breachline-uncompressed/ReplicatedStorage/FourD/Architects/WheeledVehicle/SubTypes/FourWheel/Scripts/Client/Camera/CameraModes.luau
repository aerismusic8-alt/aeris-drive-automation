local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis
local config = car.Parent:FindFirstChild("CarConfig")

local function readValue(valueName: string, defaultValue: number): number
	local value = config and config:FindFirstChild(valueName)
	if value then
		return value.Value
	end
	return defaultValue
end

local heightScale = readValue("cameraHeightScale", 1)
local distanceScale = readValue("cameraDistanceScale", 1)
local aimHeightOffset = readValue("cameraAimHeightOffset", 0)

local CameraModes = {
	{
		module = "ChaseCamera",
		parameters = {
			height = 7 * heightScale,
			distance = 30 * distanceScale,
			aimHeightOffset = aimHeightOffset,
		},
	},
	{
		module = "ChaseCamera",
		parameters = {
			height = 9 * heightScale,
			distance = 50 * distanceScale,
			aimHeightOffset = aimHeightOffset,
		},
	},
	{
		module = "InteriorCamera",
		parameters = {
			attachment = chassis.InteriorCameraAttachment,
			forwardHeadTurnAngle = math.rad(20),
			reverseHeadTurnAngle = -math.rad(140),
		},
	},
	{
		module = "FixedCamera",
		parameters = {
			attachment = chassis.HoodCameraAttachment,
		},
	},
}

return CameraModes

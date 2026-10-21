local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis

local CameraModes = {
	{
		module = "ChaseCamera",
		parameters = {
			height = 7,
			distance = 30,
		},
	},
	{
		module = "ChaseCamera",
		parameters = {
			height = 9,
			distance = 50,
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

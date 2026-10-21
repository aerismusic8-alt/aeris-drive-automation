--[[
	File: Performance.luau
]]--

-- Root

local Performance = {}

-- Constants

local DEFAULT_MAX_SPEED = 25
local DEFAULT_ACCELERATION = 30
local DEFAULT_ALTITUDE_CHANGE_RATE = 10
local DEFAULT_LOOK_RATE = 40
local DEFAULT_CAMERA_DISTANCE = 18

-- Public Functions

function Performance.read(root: BasePart): PerformanceTable
	return {
		MaxSpeed = root:GetAttribute("MaxSpeed") or DEFAULT_MAX_SPEED,
		Acceleration = root:GetAttribute("Acceleration") or DEFAULT_ACCELERATION,
		AltitudeChangeRate = root:GetAttribute("AltitudeChangeRate") or DEFAULT_ALTITUDE_CHANGE_RATE,
		LookRate = root:GetAttribute("LookRate") or DEFAULT_LOOK_RATE,
		CameraDistance = root:GetAttribute("CameraDistance") or DEFAULT_CAMERA_DISTANCE,
	}
end

-- Types

export type PerformanceTable = {
	MaxSpeed: number,
	Acceleration: number,
	AltitudeChangeRate: number,
	LookRate: number,
	CameraDistance: number,
}

-- Return

return Performance
F
--[[
	File: Performance.luau
]]--

-- Root

local Performance = {}

-- Constants

local DEFAULT_MAX_SPEED = 100
local DEFAULT_STALL_SPEED = 30
local DEFAULT_ACCELERATION = 25
local DEFAULT_PITCH_RATE = 20
local DEFAULT_TURN_RATE = 40
local DEFAULT_MAX_BANK_DEGREES = 25
local DEFAULT_CAMERA_DISTANCE = 25
local DEFAULT_CAMERA_HEIGHT = 6
local DEFAULT_PITCH_CLAMP_DEGREES = 85

-- Public Functions

function Performance.read(root: BasePart): PerformanceTable
	return {
		MaxSpeed = root:GetAttribute("MaxSpeed") or DEFAULT_MAX_SPEED,
		StallSpeed = root:GetAttribute("StallSpeed") or DEFAULT_STALL_SPEED,
		Acceleration = root:GetAttribute("Acceleration") or DEFAULT_ACCELERATION,
		PitchRate = root:GetAttribute("PitchRate") or DEFAULT_PITCH_RATE,
		TurnRate = root:GetAttribute("TurnRate") or DEFAULT_TURN_RATE,
		MaxBankDegrees = root:GetAttribute("MaxBankDegrees") or DEFAULT_MAX_BANK_DEGREES,
		CameraDistance = root:GetAttribute("CameraDistance") or DEFAULT_CAMERA_DISTANCE,
		CameraHeight = root:GetAttribute("CameraHeight") or DEFAULT_CAMERA_HEIGHT,
		PitchClampDegrees = root:GetAttribute("PitchClampDegrees") or DEFAULT_PITCH_CLAMP_DEGREES,
	}
end

-- Types

export type PerformanceTable = {
	MaxSpeed: number,
	StallSpeed: number,
	Acceleration: number,
	PitchRate: number,
	TurnRate: number,
	MaxBankDegrees: number,
	CameraDistance: number,
	CameraHeight: number,
	PitchClampDegrees: number,
}

-- Return

return Performance

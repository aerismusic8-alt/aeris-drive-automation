--[[
	File: Performance.luau
]]--

-- Root

local Performance = {}

-- Constants

local DEFAULT_MAX_SPEED_LATERAL = 150
local DEFAULT_MAX_SPEED_STRAFE = 80
local DEFAULT_ACCELERATION = 20
local DEFAULT_MAX_COLLECTIVE = 20
local DEFAULT_COLLECTIVE_RATE = 15
local DEFAULT_YAW_RATE = 40
local DEFAULT_CAMERA_DISTANCE = 25
local DEFAULT_CAMERA_HEIGHT = 6
local DEFAULT_PITCH_RATE = 55
local DEFAULT_MAX_PITCH_FOLLOW_DEGREES = 65
local DEFAULT_MAX_VISUAL_PITCH_DEGREES = 25
local DEFAULT_MAX_VISUAL_ROLL_DEGREES = 25

-- Public Functions

function Performance.read(root: BasePart): PerformanceTable
	local pitchFollow = root:GetAttribute("PitchFollow")
	if type(pitchFollow) ~= "boolean" then
		pitchFollow = false
	end

	return {
		MaxSpeedLateral = root:GetAttribute("MaxSpeedLateral") or DEFAULT_MAX_SPEED_LATERAL,
		MaxSpeedStrafe = root:GetAttribute("MaxSpeedStrafe") or DEFAULT_MAX_SPEED_STRAFE,
		Acceleration = root:GetAttribute("Acceleration") or DEFAULT_ACCELERATION,
		MaxCollective = root:GetAttribute("MaxCollective") or DEFAULT_MAX_COLLECTIVE,
		CollectiveRate = root:GetAttribute("CollectiveRate") or DEFAULT_COLLECTIVE_RATE,
		YawRate = root:GetAttribute("YawRate") or DEFAULT_YAW_RATE,
		CameraDistance = root:GetAttribute("CameraDistance") or DEFAULT_CAMERA_DISTANCE,
		CameraHeight = root:GetAttribute("CameraHeight") or DEFAULT_CAMERA_HEIGHT,
		PitchFollow = pitchFollow,
		PitchRate = root:GetAttribute("PitchRate") or DEFAULT_PITCH_RATE,
		MaxPitchFollowDegrees = root:GetAttribute("MaxPitchFollowDegrees") or DEFAULT_MAX_PITCH_FOLLOW_DEGREES,
		MaxVisualPitchDegrees = root:GetAttribute("MaxVisualPitchDegrees") or DEFAULT_MAX_VISUAL_PITCH_DEGREES,
		MaxVisualRollDegrees = root:GetAttribute("MaxVisualRollDegrees") or DEFAULT_MAX_VISUAL_ROLL_DEGREES,
	}
end

-- Types

export type PerformanceTable = {
	MaxSpeedLateral: number,
	MaxSpeedStrafe: number,
	Acceleration: number,
	MaxCollective: number,
	CollectiveRate: number,
	YawRate: number,
	CameraDistance: number,
	CameraHeight: number,
	PitchFollow: boolean,
	PitchRate: number,
	MaxPitchFollowDegrees: number,
	MaxVisualPitchDegrees: number,
	MaxVisualRollDegrees: number,
}

-- Return

return Performance

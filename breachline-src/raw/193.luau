--[[
	File: Constants.luau
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local InputConstants = require(FourD.Architects.AirVehicle.Common.Scripts.InputConstants)

local Constants = {}

for key, value in InputConstants do
	Constants[key] = value
end

Constants.VERBOSE_LOGGING = false

-- Input deadzone (Rotor-specific)
Constants.YAW_DEADZONE_FRAC = 0.05
Constants.PITCH_DEADZONE_FRAC = 0.05

-- Translation input
Constants.FORWARD_KEY = Enum.KeyCode.W
Constants.REVERSE_KEY = Enum.KeyCode.S
Constants.STRAFE_LEFT_KEY = Enum.KeyCode.A
Constants.STRAFE_RIGHT_KEY = Enum.KeyCode.D

-- Altitude input
Constants.ASCEND_KEY = Enum.KeyCode.Space
Constants.DESCEND_KEY = Enum.KeyCode.LeftControl

-- Visual tilt
Constants.MAX_BANK_DEGREES = 25
Constants.MAX_PITCH_DEGREES = 25
Constants.TILT_LERP_RATE = 5

-- Mobile
Constants.TOUCH_YAW_SENSITIVITY = 1.0

-- Rotor + blur disk tunables
Constants.MAIN_ROTOR_RADS_PER_SEC = 60
Constants.TAIL_ROTOR_RADS_PER_SEC = 90
Constants.ROTOR_MIN_RATIO = 0.3
Constants.BLUR_DISK_FADE_START_RATIO = 0.2
Constants.BLUR_DISK_FADE_END_RATIO = 0.5

-- Camera
Constants.CAMERA_BIND_NAME = "RotorCameraStep"

-- Action names
Constants.ACTION_MOBILE_EXIT = "RotorMobileExit"
Constants.ACTION_MOBILE_ASCEND = "RotorMobileAscend"
Constants.ACTION_MOBILE_DESCEND = "RotorMobileDescend"
Constants.ACTION_MOBILE_PITCH_UP = "RotorMobilePitchUp"
Constants.ACTION_MOBILE_PITCH_DOWN = "RotorMobilePitchDown"

-- Rotor attributes
Constants.ROTOR_KIND_ATTRIBUTE = "RotorKind"
Constants.ROTOR_KIND_MAIN = "Main"
Constants.ROTOR_KIND_TAIL = "Tail"

return Constants
Q
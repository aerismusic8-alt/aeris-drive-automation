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

-- Input deadzone (Plane-specific)
Constants.MOUSE_DEADZONE_FRAC = 0.05

-- Throttle input
Constants.THROTTLE_UP_KEYBOARD_KEY = Enum.KeyCode.W
Constants.THROTTLE_DOWN_KEYBOARD_KEY = Enum.KeyCode.S
Constants.THROTTLE_UP_GAMEPAD_KEY = Enum.KeyCode.ButtonA
Constants.THROTTLE_DOWN_GAMEPAD_KEY = Enum.KeyCode.ButtonB

-- Rotor + blur disk tunables
Constants.ROTOR_MAX_RADS_PER_SEC = 60
Constants.ROTOR_MIN_RATIO = 0.1
Constants.BLUR_DISK_FADE_START_RATIO = 0.25
Constants.BLUR_DISK_FADE_END_RATIO = 0.55

-- Flight tunables
Constants.ROLL_LEVEL_GAIN = 3
Constants.MAX_BANK_DEGREES = 25
Constants.PITCH_LIFT_MULTIPLIER = 1.5
Constants.MOBILE_THROTTLE_STEP = 0.25

-- Jet thruster flame VFX (mirrored in Construction/BuildThrusters.luau)
Constants.JET_FLAME_TAG = "PlaneJetFlame"
Constants.MIN_FLAME_LENGTH = 0.05

-- Camera
Constants.CAMERA_BIND_NAME = "PlaneCameraStep"

-- Action names
Constants.ACTION_MOBILE_EXIT = "PlaneMobileExit"
Constants.ACTION_MOBILE_THROTTLE_UP = "PlaneMobileThrottleUp"
Constants.ACTION_MOBILE_THROTTLE_DOWN = "PlaneMobileThrottleDown"

return Constants

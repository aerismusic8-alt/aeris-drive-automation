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

-- Translation input
Constants.FORWARD_KEY = Enum.KeyCode.W
Constants.REVERSE_KEY = Enum.KeyCode.S
Constants.STRAFE_LEFT_KEY = Enum.KeyCode.A
Constants.STRAFE_RIGHT_KEY = Enum.KeyCode.D

-- Altitude input
Constants.ASCEND_KEY = Enum.KeyCode.Space
Constants.DESCEND_KEY = Enum.KeyCode.LeftControl
Constants.ASCEND_GAMEPAD_KEY = Enum.KeyCode.ButtonA
Constants.DESCEND_GAMEPAD_KEY = Enum.KeyCode.ButtonB

-- Visual tilt
Constants.MAX_TILT_DEGREES = 25
Constants.TILT_LERP_RATE = 5

-- Camera look
Constants.MAX_PITCH_DEGREES = 85

-- Altitude controller
Constants.ALTITUDE_HOLD_GAIN = 4
Constants.ALTITUDE_MAX_VEL_MULT = 4

-- Camera
Constants.CAMERA_BIND_NAME = "JetpackCameraStep"

-- Action names
Constants.ACTION_MOBILE_EXIT = "JetpackMobileExit"
Constants.ACTION_MOBILE_ASCEND = "JetpackMobileAscend"
Constants.ACTION_MOBILE_DESCEND = "JetpackMobileDescend"

return Constants

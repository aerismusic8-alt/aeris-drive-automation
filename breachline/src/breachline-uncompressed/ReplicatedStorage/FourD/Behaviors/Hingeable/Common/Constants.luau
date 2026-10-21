--[[
	File: Common/Constants.luau

	Default parameter values, CollectionService tag names, wrapper folder name,
	and the attribute name set the client renderer reads from. Shared across the
	Hingeable class and its helpers.
]]--

local Constants = {}

Constants.WRAPPER_TAG = "Hingeable_Wrapper"
Constants.WRAPPER_NAME = "Hingeable_Wrapper"
Constants.ANCHOR_PART_NAME = "HingeableAnchor"

Constants.MOTOR_REF_VALUE_NAME = "MotorRef"
Constants.ROOT_REF_VALUE_NAME = "RootRef"
Constants.ANCHOR_REF_VALUE_NAME = "AnchorRef"

Constants.ATTR_MODE = "Mode"
Constants.ATTR_BASE_C0 = "BaseC0"
Constants.ATTR_START_ANGLE = "StartAngle"
Constants.ATTR_START_TIME = "StartTime"
Constants.ATTR_RATE = "Rate"
Constants.ATTR_TARGET_ANGLE = "TargetAngle"
Constants.ATTR_MAX_SPEED = "MaxSpeed"
Constants.ATTR_DAMPING = "Damping"
Constants.ATTR_STIFFNESS = "Stiffness"
Constants.ATTR_LOCKED_ANGLE = "LockedAngle"

Constants.MODE_FREE = "Free"
Constants.MODE_MOTOR = "Motor"
Constants.MODE_SERVO = "Servo"
Constants.MODE_LOCKED = "Locked"

Constants.DEFAULTS = {
	Mode = "Free",
	Rate = 0,
	TargetAngle = 0,
	MaxSpeed = 6,
	Damping = 1,
	Stiffness = 3,
}

return Constants

--[[
	File: Common/Constants.luau

	Default parameter values and instance names for Spinnable.
]]--

local Constants = {}

Constants.ROTOR_PART_NAME = "SpinnableRotor"
Constants.ANCHOR_PART_NAME = "SpinnableAnchor"
Constants.HINGE_NAME = "Spinnable_HingeConstraint"

Constants.DEFAULTS = {
	MaxTorque = math.huge,
}

return Constants

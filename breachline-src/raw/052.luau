--[[
	File: Common/Constants.luau

	Default parameter values and instance names for Slidable.
]]--

local Constants = {}

Constants.MOVER_PART_NAME = "SlidableMover"
Constants.ANCHOR_PART_NAME = "SlidableAnchor"
Constants.PRISMATIC_NAME = "Slidable_PrismaticConstraint"

Constants.DEFAULTS = {
	Mode = "oscillate",
	Speed = 10,
	MaxForce = math.huge,
}

return Constants

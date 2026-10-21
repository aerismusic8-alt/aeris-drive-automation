--[[
	File: Common/Types.luau

	Public type definitions for the Spinnable behavior.
]]--

local Types = {}

export type SpinnableParams = {
	---Spin pivot in assembly:GetPivot()-local space. RightVector is the spin
	---axis; Position is the pivot point.
	PivotCFrame: CFrame,
	---Angular velocity in radians per second (signed; right-hand rule around
	---the pivot's RightVector). Required.
	Rate: number,
	---Optional PVInstance to spin against. When set, the rotor follows this
	---body's motion (e.g. a fan blade on a moving vehicle). When nil, the spin
	---anchors to world space.
	RelativeTo: PVInstance?,
	---Maximum torque the motor applies. Default math.huge (the constraint always
	---wins against collisions/friction).
	MaxTorque: number?,
}

return Types

--[[
	File: Common/Types.luau

	Public type definitions for the Slidable behavior.
]]--

local Types = {}

---"oscillate" = auto back-and-forth; "toggle" = switch between open/closed.
export type SlideMode = "oscillate" | "toggle"

export type SlidableParams = {
	---Slide axis in assembly:GetPivot()-local space. The assembly slides along
	---this vector's direction. Position is the pivot (attachment) point.
	PivotCFrame: CFrame,
	---Total travel distance in studs. The mover slides from 0 to Travel along
	---the axis. Required.
	Travel: number,
	---Slide mode. "oscillate" auto-reciprocates; "toggle" requires SetOpen().
	---Default "oscillate".
	Mode: SlideMode?,
	---Period of one full oscillation cycle (out + back) in seconds. Required
	---when Mode = "oscillate". Ignored for "toggle".
	Period: number?,
	---Linear speed in studs/s for the PrismaticConstraint Servo. Default 10.
	Speed: number?,
	---Maximum force the servo applies. Default math.huge.
	MaxForce: number?,
	---Optional PVInstance to slide against. When set, the mover follows this
	---body's motion (e.g. a drawer in a moving desk). When nil, the slide
	---anchors to world space.
	RelativeTo: PVInstance?,
}

return Types

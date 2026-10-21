--[[
	File: Common/Types.luau

	Public type definitions for the Hingeable behavior. Centralized here to
	keep init.luau, the helper modules, and the client renderer in sync on
	the parameter shapes.
]]--

local Types = {}

---Operating mode of a Hingeable. `Free` uses a HingeConstraint with server
---physics. `Motor` / `Servo` / `Locked` use a kinematic Motor6D rendered by
---each client via attribute-driven angle math.
export type HingeMode = "Free" | "Motor" | "Servo" | "Locked"

---Optional tuning for `Hingeable:SetTargetAngle`. Missing values fall back to
---`Constants.DEFAULTS`. `Damping = 1` is critically damped; `0` is undamped.
export type AngleTargetOpts = {
	---Maximum angular velocity (rad/s) the client renderer will let the rotor reach.
	MaxSpeed: number?,
	---Damping ratio zeta. `1` = critically damped, `0` = undamped, `>1` overdamped.
	Damping: number?,
	---Spring response rate. Numerically Hz under the hood (settle time ~= 1/Stiffness
	---seconds at Damping = 1), but exposed as "Stiffness" because higher values feel
	---snappier and that's the only intuition callers need.
	Stiffness: number?,
}

---Optional tuning for `Hingeable.new`. Only `PivotCFrame` is required; every
---other field is nil-safe and falls back to `Constants.DEFAULTS`.
export type HingeableParams = {
	---Hinge pivot in assembly-root LOCAL space. `RightVector` defines the hinge axis;
	---`Position` defines the pivot point.
	PivotCFrame: CFrame,
	---Operating mode at construction. Default `"Free"`.
	Mode: HingeMode?,
	---Optional PVInstance to hinge against. When set, the rotor follows this body's
	---motion (e.g. a chest lid riding its chest base). When nil, the hinge anchors
	---to a synthesized invisible Terrain part fixed in world space.
	RelativeTo: PVInstance?,
	---Initial angular velocity (rad/s) for `Motor` mode. Default 0.
	Rate: number?,
	---Initial target angle (radians) for `Servo` mode. Default 0.
	TargetAngle: number?,
	---Lower swing limit (radians) for `Free` mode. Both Lower and Upper must be
	---set together for limits to apply. Stored across mode changes; reapplied
	---whenever the mode returns to `Free`.
	LowerLimit: number?,
	---Upper swing limit (radians) for `Free` mode. See `LowerLimit`.
	UpperLimit: number?,
}

return Types
y
--[[
	File: Common/Types.luau

	Public type definitions for the Emittable behavior.
]]--

local Types = {}

---Effect style selects the underlying Roblox effect class.
---"fire" = Fire, "smoke" = Smoke, "sparkles" / "embers" / "magic" / "steam" =
---ParticleEmitter presets.
export type EffectStyle = "fire" | "smoke" | "sparkles" | "embers" | "magic" | "steam"

export type EmittableParams = {
	---Effect style. Required — there is no sensible default.
	Style: EffectStyle,
	---Color override. Applies to Fire.Color / Smoke.Color / ParticleEmitter
	---ColorSequence. Nil keeps the preset default.
	Color: Color3?,
	---Scale multiplier for the effect's size/rate. Default 1. Larger values
	---produce bigger, more intense effects.
	Scale: number?,
	---Whether the effect starts enabled. Default true.
	Enabled: boolean?,
}

return Types

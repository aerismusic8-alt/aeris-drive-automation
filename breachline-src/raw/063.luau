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
	---Effect style. Required 
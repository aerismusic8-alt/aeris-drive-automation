--[[
	File: Common/Types.luau

	Public type definitions for the Lightable dispatcher and its SubTypes.
	Centralized here to avoid cyclic requires between init.luau and SubTypes.
]]--

local Types = {}

---Discriminator selecting which Roblox light class backs a Lightable instance:
---`"point"` -> PointLight, `"spot"` -> SpotLight, `"surface"` -> SurfaceLight.
---Only `"spot"` and `"surface"` honor the Angle / Face params.
export type LightType = "point" | "surface" | "spot"

---Anchor for a Lightable instance. BasePart / Attachment ties the class's
---lifetime to the instance; CFrame / Vector3 spawns a synthesized Attachment
---under `workspace.Terrain` owned by the class's Dumpster.
export type LightOrigin = BasePart | Attachment | CFrame | Vector3

---Optional tuning for `Lightable.newStatic`. Every field is nil-safe; missing
---values fall back to `Constants.DEFAULTS`.
export type StaticLightParams = {
	---Cone half-angle in degrees. Directional types only (`"spot"`/`"surface"`); ignored on `"point"`.
	Angle: number?,
	---The starting brightness of the light source.
	Brightness: number?,
	---Starting emission color.
	Color: Color3?,
	---Whether the light is emitting at construction. Default `true`.
	Enabled: boolean?,
	---Emission face. Directional types only; ignored on `"point"`.
	Face: Enum.NormalId?,
	---Maximum emission range in studs.
	Range: number?,
	---Whether the light casts dynamic shadows.
	Shadows: boolean?,
	---Roblox light class to instantiate; cannot be changed after construction.
	Type: LightType?,
}

---Single keyframe in a strobe pattern. Per-field nils inherit from the
---owning `StrobeLightParams` base values at construction time.
export type StrobeKeyframe = {
	---Brightness during this slot. Inherits the strobe's base Brightness when nil.
	Brightness: number?,
	---Color during this slot. Inherits the strobe's base Color when nil.
	Color: Color3?,
	---Whether the light emits during this slot. `false` blanks it regardless of other fields.
	Enabled: boolean?,
	---Range during this slot. Inherits the strobe's base Range when nil.
	Range: number?,
	---Duration of this slot in seconds.
	Time: number?,
}

---Optional tuning for `Lightable.newStrobe`. Base props fall back to
---`Constants.DEFAULTS`; `Strobe` defaults to an empty list (light stays off).
export type StrobeLightParams = {
	---Cone half-angle in degrees. Directional types only.
	Angle: number?,
	---Base brightness — keyframes with nil Brightness inherit this.
	Brightness: number?,
	---Base color — keyframes with nil Color inherit this.
	Color: Color3?,
	---Whether the strobe is actively cycling at construction. Default `false`.
	Enabled: boolean?,
	---Emission face. Directional types only.
	Face: Enum.NormalId?,
	---Base range — keyframes with nil Range inherit this.
	Range: number?,
	---Whether the light casts dynamic shadows.
	Shadows: boolean?,
	---Roblox light class to instantiate; cannot be changed after construction.
	Type: LightType?,
	---Ordered keyframe list describing one full cycle. Baked at construction; immutable at runtime.
	Strobe: { StrobeKeyframe }?,
}

---Timing config for `Lightable.flash`. Total duration =
---`Count * OnLength + max(0, Count - 1) * OffLength`.
export type FlashConfig = {
	---Number of on-pulses. Values `< 1` early-out with no instances created.
	Count: number?,
	---Seconds the light is on per pulse. Values `<= 0` early-out.
	OnLength: number?,
	---Seconds of darkness between pulses. Negative values early-out.
	OffLength: number?,
}

---Optional tuning for `Lightable.flash`. No `Enabled` field — a flash is
---always a fire-and-forget one-shot.
export type FlashingLightParams = {
	---Cone half-angle in degrees. Directional types only.
	Angle: number?,
	---Brightness during each on-pulse.
	Brightness: number?,
	---Emission color during each on-pulse.
	Color: Color3?,
	---Emission face. Directional types only.
	Face: Enum.NormalId?,
	---Maximum emission range in studs.
	Range: number?,
	---Whether the light casts dynamic shadows.
	Shadows: boolean?,
	---Roblox light class to instantiate.
	Type: LightType?,
	---Pulse train timing — Count / OnLength / OffLength.
	Flash: FlashConfig?,
}

return Types

 rebuild the class to change the pattern.
---@param origin -- BasePart, Attachment, CFrame, or Vector3. World-space origins anchor to a synthesized Terrain Attachment owned by the class.
---@param params -- Optional tuning plus `Strobe` keyframe list; see `Types.StrobeLightParams`. Defaults live in `Common/Constants.luau`.
---@return strobeLight -- `StrobeLight` exposing Set/Get accessors and `:Destroy()`. Setters mirror to the wrapper attributes the client renderer watches.
function Lightable.newStrobe(origin: LightOrigin, params: StrobeLightParams?): StrobeLight
	return Strobe.new(origin, params)
end

---Fires a one-shot flash sequence at `origin`. Server stamps a tagged wrapper with
---`FlashCount` / `FlashOnLength` / `FlashOffLength` / `FlashStartTime`; clients render
---the on/off cycle and the wrapper auto-cleans after the total duration. Fire-and-forget:
---no handle is returned and the effect cannot be cancelled.
---@param origin -- BasePart, Attachment, CFrame, or Vector3. World-space origins anchor to a synthesized Terrain Attachment owned by the effect.
---@param params -- Optional tuning plus `Flash` config (Count / OnLength / OffLength); see `Types.FlashingLightParams`.
function Lightable.flash(origin: LightOrigin, params: FlashingLightParams?)
	Flash(origin, params)
end

return Lightable
S
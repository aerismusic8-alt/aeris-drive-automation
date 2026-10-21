--[[
	File: Lightable/init.luau

	Dispatcher module for the Lightable behavior. Exposes three constructors:

		Lightable.newStatic(origin, params?) -> StaticLight
		Lightable.newStrobe(origin, params?) -> StrobeLight
		Lightable.flash(origin, params?) -> ()

	`origin` may be a BasePart, Attachment, CFrame, or Vector3. World-space
	origins (CFrame / Vector3) anchor to a new Attachment under
	`workspace.Terrain` that is destroyed alongside the returned class.

	Static lights are server-authoritative; strobe + flash effects render
	client-side via the shared `LightableClient` LocalScript in
	`StarterPlayer/StarterPlayerScripts/Client`.
]]--

-- Root

local Lightable = {}

-- Dependencies

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local LightableRoot = FourD.Behaviors.Lightable
local Types = require(LightableRoot.Common.Types)
local Static = require(LightableRoot.SubTypes.Static)
local Strobe = require(LightableRoot.SubTypes.Strobe)
local Flash = require(LightableRoot.SubTypes.Flash)

-- Types

export type LightType = Types.LightType
export type LightOrigin = Types.LightOrigin
export type StaticLightParams = Types.StaticLightParams
export type StrobeLightParams = Types.StrobeLightParams
export type StrobeKeyframe = Types.StrobeKeyframe
export type FlashingLightParams = Types.FlashingLightParams
export type FlashConfig = Types.FlashConfig
export type StaticLight = Static.StaticLight
export type StrobeLight = Strobe.StrobeLight

-- Public Functions

---Builds a server-authoritative static light at `origin`. Color, brightness, range,
---shadows, and (for spot/surface) angle/face are mutable at runtime via the returned
---class's setters. Lifetime is tied to the origin: when a BasePart/Attachment origin
---is destroyed, the class self-destroys via its Dumpster.
---@param origin -- BasePart, Attachment, CFrame, or Vector3. World-space origins anchor to a synthesized Terrain Attachment owned by the class.
---@param params -- Optional tuning; see `Types.StaticLightParams`. Defaults live in `Common/Constants.luau`.
---@return staticLight -- Mutable, replicated `StaticLight` exposing Set/Get accessors and `:Destroy()`.
function Lightable.newStatic(origin: LightOrigin, params: StaticLightParams?): StaticLight
	return Static.new(origin, params)
end

---Builds a strobing light at `origin`. The server publishes base attributes and a
---baked `Keyframes` sub-folder on a tagged wrapper; clients render the cycle from
---`workspace:GetServerTimeNow()` so late joiners pick up the correct phase. Keyframes
---are immutable post-construction 
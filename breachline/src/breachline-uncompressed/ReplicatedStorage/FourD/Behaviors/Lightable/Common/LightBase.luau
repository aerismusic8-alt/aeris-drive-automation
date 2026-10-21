--[[
	File: Common/LightBase.luau

	Shared base class for StaticLight and StrobeLight. Holds the method
	bodies that are identical between the two subtypes: every getter,
	`Destroy`, the frozen-table guard, and the point-type guard for
	directional-only properties (Angle, Face).

	Setters call an overridable `_applyProperty` hook so subclasses can
	inject extra side-effects on writes (e.g. StrobeLight mirrors every
	write into a wrapper-folder attribute so `LightableClient` can pick
	up the change). Base implementation writes only to `self._light`.

	NOT on this base: `SetEnabled` / `GetEnabled`. The two subtypes
	define "enabled" against different storage (`_light.Enabled` vs the
	wrapper's `StrobeEnabled` attribute), so each provides its own.

	Subclass usage:
		local StaticLight = setmetatable({}, { __index = LightBase })
		StaticLight.__index = StaticLight
		-- subclass-specific methods...
		-- in Static.new:
		local self = setmetatable({ _dumpster = ..., _light = ..., _type = ... }, StaticLight)
]]--

-- Root

local LightBase = {}
LightBase.__index = LightBase

-- Constants

local VERBOSE_LOGGING = false

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function isPointType(self: any): boolean
	return self._type == "point"
end

-- Internal Methods

function LightBase:_assertAlive()
	assert(table.isfrozen(self) == false, "cannot operate on a destroyed light")
end

function LightBase:_applyProperty(prop: string, value: any)
	local light = self._light
	light[prop] = value
end

-- Public Methods

---Sets cone half-angle of directional light (spot/surface). No-op + warn on
---point-type lights (PointLight has no Angle property). Routes through
---`_applyProperty` so subclass overrides still fire.
---@param angle -- New cone half-angle in degrees.
function LightBase:SetAngle(angle: number)
	self:_assertAlive()
	if isPointType(self) then
		vwarn("SetAngle is a no-op on a point-type light")
		return
	end

	self:_applyProperty("Angle", angle)
end

---Reads cone half-angle of underlying directional light. Returns `nil` for
---point lights.
---@return angle -- Current Angle value, or `nil` for point lights.
function LightBase:GetAngle(): number?
	self:_assertAlive()
	if isPointType(self) then
		return nil
	end

	local directional = self._light
	return directional.Angle
end

---Sets underlying Light instance's `Brightness`. Routes through
---`_applyProperty` so subclass overrides see the write.
---@param brightness -- New brightness multiplier.
function LightBase:SetBrightness(brightness: number)
	self:_assertAlive()
	self:_applyProperty("Brightness", brightness)
end

---Reads underlying Light instance's `Brightness`.
---@return brightness -- Current Brightness value.
function LightBase:GetBrightness(): number
	self:_assertAlive()
	return self._light.Brightness
end

---Sets underlying Light instance's `Color`. Routes through `_applyProperty`
---so subclass overrides see the write.
---@param color -- New light color. Combined with Brightness to determine final emission.
function LightBase:SetColor(color: Color3)
	self:_assertAlive()
	self:_applyProperty("Color", color)
end

---Reads underlying Light instance's `Color`.
---@return color -- Current Color3 value.
function LightBase:GetColor(): Color3
	self:_assertAlive()
	return self._light.Color
end

---Sets emission face of directional light (spot/surface). No-op + warn on
---point-type lights (PointLight has no Face property). Routes through
---`_applyProperty` so subclass overrides still fire.
---@param face -- New emission face. Strobe mirrors this to `BaseFace` as the enum name.
function LightBase:SetFace(face: Enum.NormalId)
	self:_assertAlive()
	if isPointType(self) then
		vwarn("SetFace is a no-op on a point-type light")
		return
	end

	self:_applyProperty("Face", face)
end

---Reads emission face of underlying directional light. Returns `nil` for
---point lights.
---@return face -- Current Face value, or `nil` for point lights.
function LightBase:GetFace(): Enum.NormalId?
	self:_assertAlive()
	if isPointType(self) then
		return nil
	end

	local directional = self._light
	return directional.Face
end

---Sets underlying Light instance's `Range`. Routes through `_applyProperty`
---so subclass overrides see the write.
---@param range -- New maximum emission range in studs.
function LightBase:SetRange(range: number)
	self:_assertAlive()
	self:_applyProperty("Range", range)
end

---Reads underlying Light instance's `Range`.
---@return range -- Current Range value in studs.
function LightBase:GetRange(): number
	self:_assertAlive()
	return self._light.Range
end

---Sets underlying Light instance's `Shadows` flag. Routes through
---`_applyProperty` so subclass overrides see the write.
---@param shadows -- Whether the light should cast dynamic shadows.
function LightBase:SetShadows(shadows: boolean)
	self:_assertAlive()
	self:_applyProperty("Shadows", shadows)
end

---Reads underlying Light instance's `Shadows` flag.
---@return shadows -- Current Shadows value.
function LightBase:GetShadows(): boolean
	self:_assertAlive()
	return self._light.Shadows
end

---Drains the class's Dumpster (destroying the Light, any wrapper folder, and
---the synthesized Terrain attachment if owned), nils every field, and freezes
---`self`. Subsequent method calls fail `_assertAlive`.
function LightBase:Destroy()
	self:_assertAlive()
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
	vprint("Destroyed light")
end

-- Types

export type LightBase = typeof(LightBase)

return LightBase

--[[
	File: SubTypes/Strobe.luau

	StrobeLight class. Server holds the Light (Enabled = false at all times)
	and a tagged wrapper Folder that carries base props + the keyframe table.
	A single shared LightableClient on each player computes the strobe phase
	from `workspace:GetServerTimeNow()` and toggles the Light locally.

	Returned by `Lightable.newStrobe(...)`.

	Inherits getters, Destroy, and the directional-only guards from
	`Common/LightBase`. Overrides `_applyProperty` so every setter mirrors
	its write into the wrapper folder's `Base*` attribute (which the client
	renderer reads). `SetEnabled` / `GetEnabled` live here because Strobe's
	"enabled" is the wrapper attribute, not `_light.Enabled`.
]]--

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local LightableRoot = FourD.Behaviors.Lightable
local Types = require(LightableRoot.Common.Types)
local Constants = require(LightableRoot.Common.Constants)
local CreateLight = require(LightableRoot.Common.CreateLight)
local ResolveOrigin = require(LightableRoot.Common.ResolveOrigin)
local LightBase = require(LightableRoot.Common.LightBase)

-- Root

local Strobe = {}
local Overrides = setmetatable({}, { __index = LightBase })
Overrides.__index = Overrides

-- Constants

local VERBOSE_LOGGING = false
local STROBE_ATTR_MAP: { [string]: string } = {
	Angle = "BaseAngle",
	Brightness = "BaseBrightness",
	Color = "BaseColor",
	Face = "BaseFace",
	Range = "BaseRange",
	Shadows = "BaseShadows",
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function serializeKeyframes(
	keyframes: { Types.StrobeKeyframe },
	mainBrightness: number,
	mainColor: Color3,
	mainRange: number
): string
	local list = {}
	for index, raw in ipairs(keyframes) do
		local color = raw.Color or mainColor
		list[index] = {
			B = raw.Brightness or mainBrightness,
			C = { color.R, color.G, color.B },
			E = if raw.Enabled ~= nil then raw.Enabled else Constants.DEFAULTS.KeyframeEnabled,
			R = raw.Range or mainRange,
			T = raw.Time or Constants.DEFAULTS.KeyframeTime,
		}
	end

	return HttpService:JSONEncode(list)
end

-- Override Internal Methods

function Overrides:_applyProperty(prop: string, value: any)
	local light = self._light
	light[prop] = value

	local attr = STROBE_ATTR_MAP[prop]
	if attr then
		local toWrite = if prop == "Face" then value.Name else value
		self._wrapper:SetAttribute(attr, toWrite)
	end
end

-- Override Public Methods

---Toggles whether the strobe is actively cycling. Writes the wrapper's
---`StrobeEnabled` attribute (NOT `_light.Enabled`, which stays false
---server-side). Transitions off->on stamp a fresh `StrobeStartTime` so the
---cycle restarts cleanly.
---@param enabled -- Whether the strobe should run.
function Overrides:SetEnabled(enabled: boolean)
	self:_assertAlive()
	local wasEnabled = self._wrapper:GetAttribute("StrobeEnabled")
	if not wasEnabled and enabled then
		self._wrapper:SetAttribute("StrobeStartTime", workspace:GetServerTimeNow())
	end
	self._wrapper:SetAttribute("StrobeEnabled", enabled)
end

---Reads the wrapper folder's `StrobeEnabled` attribute (NOT the underlying
---Light's `Enabled`, which is always false server-side for strobes).
---@return enabled -- Current StrobeEnabled value.
function Overrides:GetEnabled(): boolean
	self:_assertAlive()
	return self._wrapper:GetAttribute("StrobeEnabled") == true
end

-- Constructor

function Strobe.new(origin: Types.LightOrigin, params: Types.StrobeLightParams?): StrobeLight
	local p: Types.StrobeLightParams = params or {}
	local lightType: Types.LightType = p.Type or Constants.DEFAULTS.Type

	local brightness = p.Brightness or Constants.DEFAULTS.Brightness
	local color = p.Color or Constants.DEFAULTS.Color
	local range = p.Range or Constants.DEFAULTS.Range
	local shadows = if p.Shadows ~= nil then p.Shadows else Constants.DEFAULTS.Shadows
	local strobeEnabled = if p.Enabled ~= nil then p.Enabled else Constants.DEFAULTS.StrobeEnabled

	local mainDump = Dumpster.new()
	local parentInstance = ResolveOrigin(origin, mainDump)

	local light = CreateLight(lightType, {
		Angle = p.Angle,
		Brightness = brightness,
		Color = color,
		Enabled = false,
		Face = p.Face,
		Range = range,
		Shadows = shadows,
	})
	light.Parent = parentInstance
	mainDump:Add(light)

	local wrapper = Instance.new("Folder")
	wrapper.Name = Constants.STROBE_WRAPPER_NAME
	wrapper:SetAttribute("LightType", lightType)
	wrapper:SetAttribute("BaseBrightness", brightness)
	wrapper:SetAttribute("BaseColor", color)
	wrapper:SetAttribute("BaseRange", range)
	wrapper:SetAttribute("BaseShadows", shadows)
	if lightType ~= "point" then
		wrapper:SetAttribute("BaseAngle", p.Angle or Constants.DEFAULTS.Angle)
		wrapper:SetAttribute("BaseFace", (p.Face or Constants.DEFAULTS.Face).Name)
	end
	wrapper:SetAttribute("StrobeEnabled", strobeEnabled)
	wrapper:SetAttribute("StrobeStartTime", workspace:GetServerTimeNow())
	wrapper:SetAttribute(
		Constants.KEYFRAMES_ATTRIBUTE_NAME,
		serializeKeyframes(p.Strobe or {}, brightness, color, range)
	)

	local lightRef = Instance.new("ObjectValue")
	lightRef.Name = Constants.LIGHT_REF_VALUE_NAME
	lightRef.Value = light
	lightRef.Parent = wrapper

	CollectionService:AddTag(wrapper, Constants.STROBE_TAG)

	wrapper.Parent = parentInstance
	mainDump:Add(wrapper)

	local self = setmetatable({
		_dumpster = mainDump,
		_light = light,
		_wrapper = wrapper,
		_type = lightType,
	}, Overrides)

	vprint("Created", lightType, "strobe light on", parentInstance:GetFullName())
	return self
end

-- Types

export type StrobeLight = typeof(Overrides)

-- Return

return Strobe

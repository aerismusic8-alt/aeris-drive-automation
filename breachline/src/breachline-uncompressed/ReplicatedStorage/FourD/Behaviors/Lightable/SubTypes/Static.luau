--[[
	File: SubTypes/Static.luau

	StaticLight class. A mutable light source whose properties are fully
	server-authoritative; Roblox property replication handles client sync.
	Returned by `Lightable.newStatic(...)`.

	Inherits getters, Destroy, and the directional-only guards from
	`Common/LightBase`. Only `SetEnabled` / `GetEnabled` and the
	constructor live here; `SetEnabled` writes directly to
	`_light.Enabled` (no wrapper folder involved).
]]--

-- Roblox Services

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

local Static = {}
local Overrides = setmetatable({}, { __index = LightBase })
Overrides.__index = Overrides

-- Constants

local VERBOSE_LOGGING = false

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

-- Override Public Methods

---Sets underlying Light instance's `Enabled` flag directly. Roblox property
---replication handles client sync for static lights.
---@param enabled -- Whether the light should currently emit.
function Overrides:SetEnabled(enabled: boolean)
	self:_assertAlive()
	self._light.Enabled = enabled
end

---Reads underlying Light instance's `Enabled` flag.
---@return enabled -- Current Enabled value.
function Overrides:GetEnabled(): boolean
	self:_assertAlive()
	return self._light.Enabled
end

-- Constructor

function Static.new(origin: Types.LightOrigin, params: Types.StaticLightParams?): StaticLight
	local p: Types.StaticLightParams = params or {}
	local lightType: Types.LightType = p.Type or Constants.DEFAULTS.Type

	local mainDump = Dumpster.new()
	local parentInstance = ResolveOrigin(origin, mainDump)

	local light = CreateLight(lightType, {
		Angle = p.Angle,
		Brightness = p.Brightness,
		Color = p.Color,
		Enabled = if p.Enabled ~= nil then p.Enabled else Constants.DEFAULTS.StaticEnabled,
		Face = p.Face,
		Range = p.Range,
		Shadows = p.Shadows,
	})
	light.Parent = parentInstance
	mainDump:Add(light)

	local self = setmetatable({
		_dumpster = mainDump,
		_light = light,
		_type = lightType,
	}, Overrides)

	vprint("Created", lightType, "static light on", parentInstance:GetFullName())
	return self
end

-- Types

export type StaticLight = typeof(Overrides)

-- Return

return Static

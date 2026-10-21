--[[
	File: SubTypes/Flash.luau

	Fire-and-forget flash light. Server creates a Light (Enabled = false)
	plus a tagged wrapper carrying the flash timing as attributes, then
	schedules a single cleanup task after the total flash duration.

	The shared LightableClient on each player reads the wrapper attributes
	and toggles `Light.Enabled` locally using a server-time offset, so all
	clients render the same on/off pattern even on short sub-100ms flashes.

	Invoked via `Lightable.flash(...)`. Returns nothing.
]]--

-- Dependencies

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local LightableRoot = FourD.Behaviors.Lightable
local Types = require(LightableRoot.Common.Types)
local Constants = require(LightableRoot.Common.Constants)
local CreateLight = require(LightableRoot.Common.CreateLight)
local ResolveOrigin = require(LightableRoot.Common.ResolveOrigin)

-- Constants

local VERBOSE_LOGGING = false

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

-- Public Functions

return function(origin: Types.LightOrigin, params: Types.FlashingLightParams?)
	local p: Types.FlashingLightParams = params or {}
	local lightType: Types.LightType = p.Type or Constants.DEFAULTS.Type

	local flashConfig = p.Flash or {}
	local count = flashConfig.Count or Constants.DEFAULTS.FlashCount
	local onLength = flashConfig.OnLength or Constants.DEFAULTS.FlashOnLength
	local offLength = flashConfig.OffLength or Constants.DEFAULTS.FlashOffLength

	if count < 1 then return end
	if onLength <= 0 then return end
	if offLength < 0 then return end

	local totalDuration = count * onLength + math.max(0, count - 1) * offLength

	local brightness = p.Brightness or Constants.DEFAULTS.Brightness
	local color = p.Color or Constants.DEFAULTS.Color
	local range = p.Range or Constants.DEFAULTS.Range
	local shadows = if p.Shadows ~= nil then p.Shadows else Constants.DEFAULTS.Shadows

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
	wrapper.Name = Constants.FLASH_WRAPPER_NAME
	wrapper:SetAttribute("LightType", lightType)
	wrapper:SetAttribute("BaseBrightness", brightness)
	wrapper:SetAttribute("BaseColor", color)
	wrapper:SetAttribute("BaseRange", range)
	wrapper:SetAttribute("BaseShadows", shadows)
	if lightType ~= "point" then
		wrapper:SetAttribute("BaseAngle", p.Angle or Constants.DEFAULTS.Angle)
		wrapper:SetAttribute("BaseFace", (p.Face or Constants.DEFAULTS.Face).Name)
	end
	wrapper:SetAttribute("FlashCount", count)
	wrapper:SetAttribute("FlashOnLength", onLength)
	wrapper:SetAttribute("FlashOffLength", offLength)
	wrapper:SetAttribute("FlashStartTime", workspace:GetServerTimeNow())
	wrapper:SetAttribute("FlashTotalDuration", totalDuration)

	local lightRef = Instance.new("ObjectValue")
	lightRef.Name = Constants.LIGHT_REF_VALUE_NAME
	lightRef.Value = light
	lightRef.Parent = wrapper

	CollectionService:AddTag(wrapper, Constants.FLASH_TAG)

	wrapper.Parent = parentInstance
	mainDump:Add(wrapper)

	-- Don't add this thread to mainDump: if the dumpster destroyed it mid-run
	-- (e.g. emitPart dies first), task.cancel on the executing thread would halt
	-- the dumpster's own cleanup iteration. mainDump:Destroy() is safely
	-- idempotent so a redundant fire after early destruction is a no-op.
	task.delay(totalDuration, function()
		mainDump:Destroy()
	end)

	vprint("Flashed", lightType, "light on", parentInstance:GetFullName(), "for", totalDuration, "s")
end

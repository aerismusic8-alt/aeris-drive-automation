--[[
	File: Common/CreateLight.luau

	Constructs an unparented Light instance (PointLight / SurfaceLight /
	SpotLight) from a `LightType` string and applies the shared base
	properties. Angle + Face are silently ignored for point lights (with a
	warning) since Roblox's PointLight does not support them.
]]--

-- Dependencies

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local LightableRoot = FourD.Behaviors.Lightable
local Types = require(LightableRoot.Common.Types)
local Constants = require(LightableRoot.Common.Constants)

-- Local Functions

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

-- Types

export type AppliedLightProps = {
	Angle: number?,
	Brightness: number?,
	Color: Color3?,
	Enabled: boolean?,
	Face: Enum.NormalId?,
	Range: number?,
	Shadows: boolean?,
}

-- Public Functions

local function createLight(lightType: Types.LightType, props: AppliedLightProps): PointLight | SurfaceLight | SpotLight
	local light
	if lightType == "surface" then
		light = Instance.new("SurfaceLight")
	elseif lightType == "spot" then
		light = Instance.new("SpotLight")
	else
		light = Instance.new("PointLight")
	end

	light.Brightness = props.Brightness or Constants.DEFAULTS.Brightness
	light.Color = props.Color or Constants.DEFAULTS.Color
	light.Range = props.Range or Constants.DEFAULTS.Range
	light.Shadows = if props.Shadows ~= nil then props.Shadows else Constants.DEFAULTS.Shadows
	light.Enabled = if props.Enabled ~= nil then props.Enabled else Constants.DEFAULTS.StaticEnabled
	light.Name = Constants.LIGHT_INSTANCE_NAME

	if lightType == "point" then
		if props.Angle ~= nil then
			vwarn("Angle ignored: PointLight does not support an Angle property")
		end
		if props.Face ~= nil then
			vwarn("Face ignored: PointLight does not support a Face property")
		end
	else
		local directional = light
		directional.Angle = props.Angle or Constants.DEFAULTS.Angle
		directional.Face = props.Face or Constants.DEFAULTS.Face
	end

	return light
end

return createLight
F
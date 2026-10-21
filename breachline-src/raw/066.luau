--[[
	File: Common/Constants.luau

	Default parameter values, CollectionService tag names, and wrapper folder
	names shared across the Lightable dispatcher and its SubTypes.
]]--

local Constants = {}

Constants.STROBE_TAG = "Lightable_Strobe"
Constants.FLASH_TAG = "Lightable_Flash"

Constants.STROBE_WRAPPER_NAME = "Lightable_Strobe"
Constants.FLASH_WRAPPER_NAME = "Lightable_Flash"

Constants.LIGHT_INSTANCE_NAME = "Light"
Constants.KEYFRAMES_ATTRIBUTE_NAME = "Keyframes"
Constants.LIGHT_REF_VALUE_NAME = "LightRef"

Constants.DEFAULTS = {
	Angle = 90,
	Brightness = 1,
	Color = Color3.new(1, 1, 1),
	Face = Enum.NormalId.Front,
	Range = 8,
	Shadows = false,
	Type = "point",

	StaticEnabled = true,
	StrobeEnabled = false,

	KeyframeTime = 1,
	KeyframeEnabled = true,

	FlashCount = 1,
	FlashOnLength = 1,
	FlashOffLength = 1,
}

return Constants

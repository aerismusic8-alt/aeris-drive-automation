--[[
	Scene pass for Breachline, applied to the place at build time.

	Two things are wrong with the lighting as shipped, and one thing is worth
	improving.

	Wrong: Lighting holds two Atmosphere instances. Roblox renders every
	Atmosphere under Lighting, so the two stack -- the second one's haze sits
	on top of the first -- which flattens contrast and washes out distance.
	The one meant to be used is DustDistrictAtmosphere; the plain Atmosphere
	beside it is the default that was never removed.

	Wrong: ClockTime is unset. The map reads as an overcast noon, which is the
	flattest light there is for reading silhouettes, and it is the reason the
	dust colour correction has little to work with.

	Improved: the map is 126 parts with no occluders, so its depth cue has to
	come from atmosphere and sun angle rather than geometry. A lower sun with
	warmer haze gives the two bomb sites visibly different light and makes
	players readable at range, which is what a tactical shooter needs.

	Baked at build time rather than shipped as a script, so the place carries
	the values directly and there is nothing to run at load.

	Usage:
	  rbxmk run --allow-insecure-paths breachline/scene.lua <place.rbxl> <out.rbxl>
]]

local inPath, outPath = ...

assert(inPath, "usage: scene.lua <place.rbxl> <out.rbxl>")
assert(outPath, "usage: scene.lua <place.rbxl> <out.rbxl>")

local place = fs.read(inPath)
assert(place and place.ClassName == "DataModel", "place did not decode to a DataModel")

local Lighting = place:FindFirstChild("Lighting")
assert(Lighting, "place has no Lighting service")

local LIGHTING_PROPERTIES = {
	-- Late afternoon. Long shadows and a warm key light, rather than noon.
	ClockTime = 16.2,
	GeographicLatitude = 24,

	Brightness = 2.4,
	-- Cool shadow fill against the warm key, which is what keeps a player in
	-- shade from reading as a flat grey silhouette.
	Ambient = Color3.fromRGB(86, 88, 96),
	OutdoorAmbient = Color3.fromRGB(122, 118, 110),

	-- Shadows on: they are the depth cue the geometry does not provide.
	GlobalShadows = true,
	ShadowSoftness = 0.32,

	EnvironmentDiffuseScale = 1.15,
	EnvironmentSpecularScale = 1.1,
	ExposureCompensation = 0.08,

	-- A short fog range is what makes distance legible on a flat map.
	FogColor = Color3.fromRGB(196, 186, 168),
	FogStart = 90,
	FogEnd = 620,
}

local ATMOSPHERE_PROPERTIES = {
	Density = 0.32,
	Offset = 0.15,
	Color = Color3.fromRGB(214, 198, 172),
	Decay = Color3.fromRGB(120, 96, 70),
	Glare = 0.15,
	Haze = 1.2,
}

local SUN_RAYS = { Intensity = 0.06, Spread = 0.35 }

local BLOOM = {
	-- A lower threshold lets the sun and muzzle flashes bloom without the
	-- whole scene glowing.
	Threshold = 1.4,
	Intensity = 0.6,
	Size = 22,
}

local COLOR = {
	Brightness = 0.02,
	Contrast = 0.12,
	Saturation = -0.04,
}

local function apply(instance, properties)
	for name, value in pairs(properties) do
		instance[name] = value
	end
end

---Keep exactly one instance of `className`, named `keep`, removing any others.
---Two of the same effect stack, and stacking is the bug: the place shipped with
---two Atmospheres, two Blooms, two colour corrections and two sun-rays, so the
---haze, the glow and the grade all landed twice.
---
---The key is the class, not the name. The shipped copies are named "Bloom",
---"SunRays" and "DustDistrictColor", so a lookup by name finds nothing and
---creates a duplicate beside the original.
local function collapse(className, keep)
	local kept = nil
	for _, child in ipairs(Lighting:GetChildren()) do
		if child.ClassName == className then
			if kept == nil then
				kept = child
			else
				child:Destroy()
			end
		end
	end

	if not kept then
		kept = Instance.new(className)
		kept.Parent = Lighting
	end

	kept.Name = keep
	return kept
end

local atmosphere = collapse("Atmosphere", "DustDistrictAtmosphere")
apply(atmosphere, ATMOSPHERE_PROPERTIES)

apply(Lighting, LIGHTING_PROPERTIES)
apply(collapse("SunRaysEffect", "SunRays"), SUN_RAYS)
apply(collapse("BloomEffect", "Bloom"), BLOOM)
apply(collapse("ColorCorrectionEffect", "DustDistrictColor"), COLOR)

fs.write(outPath, place, "rbxl")
print(string.format("SCENE_OK out=%s", outPath))

--[[
	File: ConeMath.luau
]]--

-- Root

local ConeMath = {}

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Public Functions

local function spreadDegToPixelRadius(spreadDeg: number, camera: Camera): number
	if spreadDeg <= 0 then return 0 end

	local d = Constants.CONE_ENGAGEMENT_DISTANCE
	local fovRad = math.rad(camera.FieldOfView)
	local worldRadius = d * math.tan(math.rad(spreadDeg) * 0.5)
	return (worldRadius * camera.ViewportSize.Y) / (2 * d * math.tan(fovRad * 0.5))
end

local function perturbDirection(baseDir: Vector3, spreadDeg: number, seed: number): Vector3
	if spreadDeg <= 0 then return baseDir.Unit end

	local rng = Random.new(seed)
	local maxConeRad = math.rad(spreadDeg) * 0.5
	local theta = rng:NextNumber() * maxConeRad
	local phi = rng:NextNumber() * math.pi * 2

	local up = if math.abs(baseDir.Y) > 0.999
		then Vector3.new(1, 0, 0)
		else Vector3.yAxis
	local right = baseDir:Cross(up).Unit
	local realUp = right:Cross(baseDir).Unit

	local sinT = math.sin(theta)
	local offset = right * (sinT * math.cos(phi)) + realUp * (sinT * math.sin(phi))
	return (baseDir.Unit * math.cos(theta) + offset).Unit
end

ConeMath.spreadDegToPixelRadius = spreadDegToPixelRadius
ConeMath.perturbDirection = perturbDirection

-- Return

return ConeMath

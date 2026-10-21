-- GENERATED WRAPPER around upstream WheelSpin.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
Train5 WheelSpin - cosmetic client-side wheel rotation driven by the root train's
trackSpeed attribute while it is on a track. Cloned into every car model by bind().
]]

local RunService = game:GetService("RunService")

local carModel = script.Parent
if not carModel:IsA("Model") then return end

local rootModel = carModel

local function resolveRoot(): Model
	if rootModel:GetAttribute("driveMode") ~= nil then
		return rootModel
	end

	local candidate: Instance? = carModel
	while candidate do
		if candidate:IsA("Model") and candidate:GetAttribute("driveMode") ~= nil then
			rootModel = candidate
			break
		end

		candidate = candidate.Parent
	end

	return rootModel
end

local WHEEL_NAMES = { "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" }
local MIN_RADIUS = 0.05
local FULL_TURN = math.pi * 2

type WheelPartEntry = {
	Part: BasePart,
	BaseOffset: CFrame,
}

type WheelEntry = {
	PartEntries: { WheelPartEntry },
	Center: Vector3,
	Radius: number,
	Angle: number,
}

local wheels: { WheelEntry } = {}
local initialized = false

local function collectParts(instance: Instance): { BasePart }
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function buildWheel(bodyCFrame: CFrame, wheelInstance: Instance): WheelEntry?
	local parts = collectParts(wheelInstance)
	if #parts == 0 then
		return nil
	end

	local partEntries: { WheelPartEntry } = {}
	local minBounds = Vector3.new(math.huge, math.huge, math.huge)
	local maxBounds = -minBounds

	for _, part in ipairs(parts) do
		local baseOffset = bodyCFrame:ToObjectSpace(part.CFrame)
		table.insert(partEntries, { Part = part, BaseOffset = baseOffset })

		local halfSize = part.Size / 2
		local halfExtent = Vector3.new(
			math.abs(baseOffset.XVector.X) * halfSize.X + math.abs(baseOffset.YVector.X) * halfSize.Y + math.abs(baseOffset.ZVector.X) * halfSize.Z,
			math.abs(baseOffset.XVector.Y) * halfSize.X + math.abs(baseOffset.YVector.Y) * halfSize.Y + math.abs(baseOffset.ZVector.Y) * halfSize.Z,
			math.abs(baseOffset.XVector.Z) * halfSize.X + math.abs(baseOffset.YVector.Z) * halfSize.Y + math.abs(baseOffset.ZVector.Z) * halfSize.Z
		)
		minBounds = minBounds:Min(baseOffset.Position - halfExtent)
		maxBounds = maxBounds:Max(baseOffset.Position + halfExtent)
	end

	for _, entry in ipairs(partEntries) do
		entry.Part.Anchored = true
	end

	return {
		PartEntries = partEntries,
		Center = (minBounds + maxBounds) / 2,
		Radius = math.max((maxBounds.Y - minBounds.Y) / 2, MIN_RADIUS),
		Angle = 0,
	}
end

local function initializeWheels(bodyCFrame: CFrame)
	for _, wheelName in ipairs(WHEEL_NAMES) do
		local wheelInstance = carModel:FindFirstChild(wheelName)
		if wheelInstance then
			local wheel = buildWheel(bodyCFrame, wheelInstance)
			if wheel then
				table.insert(wheels, wheel)
			end
		end
	end
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	local root = resolveRoot()
	if root:GetAttribute("trackActive") ~= true then
		return
	end

	local primaryPart = carModel.PrimaryPart
	if not primaryPart then
		return
	end

	local bodyCFrame = primaryPart.CFrame
	if not initialized then
		initialized = true
		initializeWheels(bodyCFrame)
	end

	local speedAttribute = root:GetAttribute("trackSpeed")
	local speed = if typeof(speedAttribute) == "number" then speedAttribute else 0

	for _, wheel in ipairs(wheels) do
		wheel.Angle = (wheel.Angle - speed * deltaTime / wheel.Radius) % FULL_TURN
		local spin = CFrame.new(wheel.Center) * CFrame.Angles(wheel.Angle, 0, 0) * CFrame.new(-wheel.Center)
		for _, entry in ipairs(wheel.PartEntries) do
			entry.Part.CFrame = bodyCFrame * spin * entry.BaseOffset
		end
	end
end)

end
=
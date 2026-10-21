--[[
	File: BuildPropellers.luau
]]--

-- Root

local BuildPropellers = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local Heuristics = require(script.Parent.Heuristics)

-- Constants

local BLADE_ROOT_SIZE = Vector3.new(0.4, 0.4, 0.4)
local BLUR_DISK_HEIGHT = 0.1
local PROP_HUB_NAME = "PropHub"
local BLUR_DISK_NAME = "BlurDisk"

-- Local Functions

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

-- Public Functions

function BuildPropellers.makeHubPart(centroid: Vector3, spinAxis: Vector3): Part
	local hub = Instance.new("Part")
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CastShadow = false
	hub.CFrame = CFrame.lookAt(centroid, centroid + spinAxis)
	hub.Massless = true
	hub.Name = PROP_HUB_NAME
	hub.Size = BLADE_ROOT_SIZE
	hub.Transparency = 1
	return hub
end

function BuildPropellers.makeBlurDisk(
	hub: Part,
	spinAxis: Vector3,
	radius: number,
	initialTransparency: number,
	visibleTransparency: number
): Part
	local disk = Instance.new("Part")
	disk.Anchored = false
	disk.CanCollide = false
	disk.CanQuery = false
	disk.CastShadow = false
	disk.Color = Color3.fromRGB(200, 200, 200)
	disk.Massless = true
	disk.Material = Enum.Material.SmoothPlastic
	disk.Name = BLUR_DISK_NAME
	disk.Shape = Enum.PartType.Cylinder
	disk.Size = Vector3.new(BLUR_DISK_HEIGHT, radius * 2, radius * 2)
	disk.Transparency = initialTransparency

	disk:SetAttribute("VisibleTransparency", visibleTransparency)

	local axis = spinAxis.Unit
	local upHint = if math.abs(axis.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
	local upVector = upHint - axis * upHint:Dot(axis)
	if upVector.Magnitude < 1e-3 then
		upVector = Vector3.xAxis
	end

	disk.CFrame = CFrame.fromMatrix(hub.Position, axis, upVector.Unit)
	return disk
end

function BuildPropellers.breakWeldsTo(part: BasePart, root: BasePart)
	for _, child in root:GetChildren() do
		if child:IsA("WeldConstraint") and child.Part1 == part then
			child:Destroy()
		end
	end

	for _, child in part:GetChildren() do
		if child:IsA("WeldConstraint") and (child.Part0 == root or child.Part1 == root) then
			child:Destroy()
		end
	end
end

function BuildPropellers.tryGetSinglePart(propellerPV: PVInstance): BasePart?
	if propellerPV:IsA("BasePart") then
		return propellerPV
	end

	local parts = ConstructionHelpers.getAllParts({ propellerPV })
	if #parts == 1 then
		return parts[1]
	end

	return nil
end

function BuildPropellers.computeSinglePartRadius(size: Vector3, localSpinAxis: Vector3): number
	if localSpinAxis.X > 0.5 then
		return math.max(size.Y, size.Z) * 0.5
	end

	if localSpinAxis.Y > 0.5 then
		return math.max(size.X, size.Z) * 0.5
	end

	return math.max(size.X, size.Y) * 0.5
end

function BuildPropellers.rig(config: PropellerRigConfig)
	local propellers = config.Propellers
	if not propellers or #propellers == 0 then return end

	local wrapperModel = config.WrapperModel
	local root = config.Root
	local motorPrefix = config.MotorPrefix
	local blurDiskOpacity = config.BlurDiskOpacity
	local blurDiskInitialTransparency = config.BlurDiskInitialTransparency
	local motorBuilder = config.MotorBuilder
	local warnLabel = config.WarnLabel or "propeller"

	for index, propellerPV in propellers do
		local motorName = if index == 1 then motorPrefix else `{motorPrefix}{index}`

		local singlePart = BuildPropellers.tryGetSinglePart(propellerPV)
		if singlePart then
			BuildPropellers.breakWeldsTo(singlePart, root)

			local localSpinAxis = GeometryUtils.getFlattestAxis(singlePart.Size)
			local worldSpinAxis = singlePart.CFrame:VectorToWorldSpace(localSpinAxis)

			singlePart.Anchored = false
			singlePart.CanCollide = false
			singlePart.Massless = true

			local radius = BuildPropellers.computeSinglePartRadius(singlePart.Size, localSpinAxis)
			if radius > 0 then
				local disk = BuildPropellers.makeBlurDisk(
					singlePart,
					worldSpinAxis,
					radius,
					blurDiskInitialTransparency,
					blurDiskOpacity
				)
				disk.Parent = wrapperModel
				ConstructionHelpers.makeWeld(singlePart, disk)
			end

			motorBuilder(root, singlePart, worldSpinAxis, motorName)
			continue
		end

		Heuristics.stripPlaceholders(propellerPV)

		local spinAxis = Heuristics.computePropPrincipalAxis(propellerPV)
		local blades = Heuristics.detectBlades(propellerPV, spinAxis)

		if #blades == 0 then
			vwarn(`{warnLabel} #{index} has no detected blades; skipping decoration`)
			continue
		end

		local fallbackCenter, _ = GeometryUtils.getBodyBounds(propellerPV)
		local hubPos = Heuristics.computeHubPosition(propellerPV, blades, fallbackCenter, spinAxis)
		local hub = BuildPropellers.makeHubPart(hubPos, spinAxis)
		hub.Parent = wrapperModel

		for _, part in GeometryUtils.getInstanceParts(propellerPV) do
			BuildPropellers.breakWeldsTo(part, root)
			part.CanCollide = false
			part.Massless = true
			part.Anchored = false
			ConstructionHelpers.makeWeld(hub, part)
		end

		local radius = Heuristics.computeBladeMaxRadius(blades, hub.Position, spinAxis)
		if radius > 0 then
			local disk = BuildPropellers.makeBlurDisk(
				hub,
				spinAxis,
				radius,
				blurDiskInitialTransparency,
				blurDiskOpacity
			)
			disk.Parent = wrapperModel
			ConstructionHelpers.makeWeld(hub, disk)
		end

		motorBuilder(root, hub, spinAxis, motorName)
	end
end

-- Types

export type MotorBuilder = (root: BasePart, rotorRoot: BasePart, spinAxis: Vector3, motorName: string) -> ()

export type PropellerRigConfig = {
	WrapperModel: Model,
	Root: BasePart,
	Propellers: { PVInstance }?,
	MotorPrefix: string,
	BlurDiskOpacity: number,
	BlurDiskInitialTransparency: number,
	MotorBuilder: MotorBuilder,
	WarnLabel: string?,
}

-- Return

return BuildPropellers

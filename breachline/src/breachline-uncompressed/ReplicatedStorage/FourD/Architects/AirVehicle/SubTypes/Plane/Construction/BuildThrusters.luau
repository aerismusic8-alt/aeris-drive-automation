--[[
	File: BuildThrusters.luau
]]--

-- Root

local BuildThrusters = {}

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local recenterModelPivot = require(FourD.Common.recenterModelPivot)

-- Constants

local VFX_CLONE_PREFIX = "JetThrusterVfx_"
local VFX_ROOT_NAME = "VfxRoot"
local FLAME_MOTOR_NAME = "JetFlameMotor"
local FIT_MODEL_NAME = "JetThrusterFit"
local EXHAUST_KEYWORDS = { "exhaust", "nozzle", "thrust", "engine", "jet" }
local VFX_LOCAL_AXIS = Vector3.yAxis
local TEMPLATE_OUTER_RADIUS = 0.7
local MIN_RADIUS_SCALE = 0.05
-- Flame cone width trimmed to this fraction of the nozzle opening so tapered nozzles don't clip the flame.
local FLAME_WIDTH_FACTOR = 0.75
-- Seat the flame root this fraction of the opening radius inside the nozzle mouth so it reads as attached.
local NOZZLE_INSET_RATIO = 0.5
local VFX_ROOT_SIZE = Vector3.new(0.1, 0.1, 0.1)
-- Mirror of PlaneConstants.JET_FLAME_TAG / MIN_FLAME_LENGTH (Scripts/Constants.luau); FX runtime reads them.
local JET_FLAME_TAG = "PlaneJetFlame"
local MIN_FLAME_LENGTH = 0.05

-- Types

export type FlameFit = {
	Part: BasePart,
	Outward: Vector3,
	Face: Vector3,
	Radius: number,
}

export type RigResult = {
	VfxClones: { Model },
}

-- Local Functions

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function nameMatchesAny(name: string, keywords: { string }): boolean
	local lower = string.lower(name)
	for _, keyword in keywords do
		if string.find(lower, keyword, 1, true) then
			return true
		end
	end

	return false
end

local function collectParts(entry: PVInstance): { BasePart }
	if entry:IsA("BasePart") then
		return { entry }
	end

	return ConstructionHelpers.getAllParts({ entry })
end

local function keywordParts(parts: { BasePart }): { BasePart }
	local matched: { BasePart } = {}
	for _, part in parts do
		if nameMatchesAny(part.Name, EXHAUST_KEYWORDS) then
			table.insert(matched, part)
		end
	end

	return matched
end

-- Half-extent of the part's oriented bounding box projected onto a world direction.
-- Half-extent of an oriented bounding box (cframe + size) projected onto a world direction.
local function obbHalfExtent(cframe: CFrame, size: Vector3, direction: Vector3): number
	local half = size * 0.5
	return math.abs(cframe.RightVector:Dot(direction)) * half.X
		+ math.abs(cframe.UpVector:Dot(direction)) * half.Y
		+ math.abs(cframe.LookVector:Dot(direction)) * half.Z
end

-- Conservative opening radius: tightest half-extent of the cross-section perpendicular to the exhaust axis.
-- Conservative opening radius: tightest half-extent of the cross-section perpendicular to the exhaust axis.
local function perpRadius(cframe: CFrame, size: Vector3, axis: Vector3): number
	local reference = if math.abs(axis.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local u = axis:Cross(reference).Unit
	local v = axis:Cross(u).Unit
	return math.min(obbHalfExtent(cframe, size, u), obbHalfExtent(cframe, size, v))
end

local function rearMostPart(parts: { BasePart }, backward: Vector3): BasePart
	local best = parts[1]
	local bestProjection = -math.huge
	for _, part in parts do
		local projection = part.Position:Dot(backward)
		if projection > bestProjection then
			bestProjection = projection
			best = part
		end
	end

	return best
end

local function buildExhaustList(entry: PVInstance, backward: Vector3): { FlameFit }
	local fits: { FlameFit } = {}
	local parts = collectParts(entry)
	if #parts == 0 then
		return fits
	end

	local chosen: { BasePart }
	if #parts == 1 then
		chosen = parts
	else
		local matched = keywordParts(parts)
		if #matched > 0 then
			chosen = matched
		else
			chosen = { rearMostPart(parts, backward) }
		end
	end

	for _, part in chosen do
		-- Wrap the part in its own Model and recenter its pivot so GetBoundingBox reports the true
		-- visual center/size (AI PartOperation/MeshPart pivots are offset from their geometry).
		local holder = Instance.new("Model")
		holder.Name = FIT_MODEL_NAME
		holder.Parent = part.Parent
		part.Parent = holder
		recenterModelPivot(holder)

		local cframe, size = holder:GetBoundingBox()
		local axialHalf = obbHalfExtent(cframe, size, backward)
		local radius = perpRadius(cframe, size, backward)
		local inset = math.min(radius * NOZZLE_INSET_RATIO, axialHalf)
		local face = cframe.Position + backward * (axialHalf - inset)
		table.insert(fits, { Part = part, Outward = backward, Face = face, Radius = radius })
	end

	return fits
end

local function buildOrientationCFrame(position: Vector3, outward: Vector3): CFrame
	local target = if outward.Magnitude > 1e-4 then outward.Unit else VFX_LOCAL_AXIS
	local dot = math.clamp(VFX_LOCAL_AXIS:Dot(target), -1, 1)

	if dot > 0.9999 then
		return CFrame.new(position)
	end

	if dot < -0.9999 then
		return CFrame.new(position) * CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
	end

	local rotationAxis = VFX_LOCAL_AXIS:Cross(target)
	if rotationAxis.Magnitude < 1e-4 then
		return CFrame.new(position)
	end

	local angle = math.acos(dot)
	return CFrame.new(position) * CFrame.fromAxisAngle(rotationAxis.Unit, angle)
end

local function disableEffects(vfxClone: Model)
	for _, descendant in vfxClone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = false
		end
	end
end

local function setupFlameMesh(mesh: BasePart, vfxRoot: BasePart, radiusScale: number)
	local authoredSize = mesh.Size
	local authoredTransparency = mesh.Transparency
	local radiusX = authoredSize.X * radiusScale * FLAME_WIDTH_FACTOR
	local radiusZ = authoredSize.Z * radiusScale * FLAME_WIDTH_FACTOR
	local fullLength = authoredSize.Y * radiusScale

	mesh:SetAttribute("FlameFullLength", fullLength)
	mesh:SetAttribute("FlameRadiusX", radiusX)
	mesh:SetAttribute("FlameRadiusZ", radiusZ)
	mesh:SetAttribute("FlameVisibleTransparency", authoredTransparency)

	local startLength = MIN_FLAME_LENGTH
	local startTransparency = 1

	mesh.Anchored = false
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = false
	mesh.Massless = true
	mesh.Size = Vector3.new(radiusX, startLength, radiusZ)
	mesh.Transparency = startTransparency

	local motor = Instance.new("Motor6D")
	motor.Name = FLAME_MOTOR_NAME
	motor.Part0 = vfxRoot
	motor.Part1 = mesh
	motor.C0 = CFrame.new(0, startLength * 0.5, 0)
	motor.C1 = CFrame.identity
	motor.Parent = mesh

	mesh.CFrame = vfxRoot.CFrame * motor.C0

	CollectionService:AddTag(mesh, JET_FLAME_TAG)
end

local function buildFlame(wrapperModel: Model, fit: FlameFit, vfxTemplate: Model, index: number): Model?
	local radiusScale = math.max(fit.Radius / TEMPLATE_OUTER_RADIUS, MIN_RADIUS_SCALE)

	local clone = vfxTemplate:Clone()
	clone.Name = `{VFX_CLONE_PREFIX}{index}`

	local meshes: { BasePart } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(meshes, descendant)
		end
	end

	if #meshes == 0 then
		vwarn(`vfx template has no BaseParts; skipping thruster {index}`)
		clone:Destroy()
		return nil
	end

	local vfxRoot = Instance.new("Part")
	vfxRoot.Name = VFX_ROOT_NAME
	vfxRoot.Size = VFX_ROOT_SIZE
	vfxRoot.Transparency = 1
	vfxRoot.Anchored = false
	vfxRoot.CanCollide = false
	vfxRoot.CanQuery = false
	vfxRoot.CanTouch = false
	vfxRoot.CastShadow = false
	vfxRoot.Massless = true
	vfxRoot.CFrame = buildOrientationCFrame(fit.Face, fit.Outward)
	vfxRoot.Parent = clone
	clone.PrimaryPart = vfxRoot

	for _, mesh in meshes do
		setupFlameMesh(mesh, vfxRoot, radiusScale)
	end

	disableEffects(clone)

	clone.Parent = wrapperModel
	ConstructionHelpers.makeWeld(fit.Part, vfxRoot)

	return clone
end

-- Public Functions

function BuildThrusters.rig(
	wrapperModel: Model,
	thrusterEntry: PVInstance,
	forwardAxis: Vector3,
	vfxTemplate: Model
): RigResult
	local backward = if forwardAxis.Magnitude > 1e-4 then (-forwardAxis).Unit else -Vector3.zAxis
	local fits = buildExhaustList(thrusterEntry, backward)

	local vfxClones: { Model } = {}
	for index, fit in fits do
		local clone = buildFlame(wrapperModel, fit, vfxTemplate, index)
		if clone then
			table.insert(vfxClones, clone)
		end
	end

	return {
		VfxClones = vfxClones,
	}
end

-- Return

return BuildThrusters

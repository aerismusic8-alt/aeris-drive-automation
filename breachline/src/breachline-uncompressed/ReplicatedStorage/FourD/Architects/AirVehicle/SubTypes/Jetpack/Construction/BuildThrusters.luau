--[[
	File: BuildThrusters.luau
]]--

-- Root

local BuildThrusters = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local GeometryUtils = require(FourD.Common.GeometryUtils)

-- Constants

local VFX_CLONE_PREFIX = "JetFlameRoot_"
local EXHAUST_KEYWORDS = { "exhaust", "nozzle", "thrust" }
local VFX_LOCAL_DOWN_AXIS = -Vector3.yAxis

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

local function enumerateThrusters(thruster: PVInstance): { PVInstance }
	if thruster:IsA("BasePart") then
		return { thruster }
	end

	local thrusters: { PVInstance } = {}
	for _, child in thruster:GetChildren() do
		if child:IsA("BasePart") or child:IsA("Model") then
			table.insert(thrusters, child)
		end
	end

	if #thrusters == 0 then
		table.insert(thrusters, thruster)
	end

	return thrusters
end

local function collectParts(thrusterPV: PVInstance): { BasePart }
	if thrusterPV:IsA("BasePart") then
		return { thrusterPV }
	end
	return ConstructionHelpers.getAllParts({ thrusterPV })
end

local function pickKeywordCandidates(parts: { BasePart }): { BasePart }
	local matched: { BasePart } = {}
	for _, part in parts do
		if nameMatchesAny(part.Name, EXHAUST_KEYWORDS) then
			table.insert(matched, part)
		end
	end
	if #matched > 0 then
		return matched
	end
	return parts
end

local function principalAxis(parts: { BasePart }, centroid: Vector3): Vector3
	if #parts <= 1 then
		return Vector3.yAxis
	end

	local primary, secondary, tertiary, eigenvalues = GeometryUtils.computePrincipalAxes(parts, centroid)
	local axes = { primary, secondary, tertiary }
	local values = { eigenvalues.X, eigenvalues.Y, eigenvalues.Z }
	local maxIndex = 1
	for i = 2, 3 do
		if values[i] > values[maxIndex] then
			maxIndex = i
		end
	end

	local axis = axes[maxIndex]
	if axis.Magnitude < 1e-4 then
		return Vector3.yAxis
	end
	return axis.Unit
end

local function pickLongestAxisExhaust(part: BasePart, packCentroid: Vector3): (Vector3, Vector3)
	local localAxis, length = GeometryUtils.getLongestAxis(part.Size)
	if length < 1e-4 then
		return part.Position, -Vector3.yAxis
	end

	local worldAxis = part.CFrame:VectorToWorldSpace(localAxis)
	local halfLength = length * 0.5
	local facePositive = part.Position + worldAxis * halfLength
	local faceNegative = part.Position - worldAxis * halfLength

	local positiveDistanceSq = (facePositive - packCentroid).Magnitude ^ 2
	local negativeDistanceSq = (faceNegative - packCentroid).Magnitude ^ 2

	if positiveDistanceSq >= negativeDistanceSq then
		return facePositive, worldAxis.Unit
	end
	return faceNegative, (-worldAxis).Unit
end

local function pickExhaustPart(
	thrusterParts: { BasePart },
	candidates: { BasePart },
	thrusterCentroid: Vector3,
	packCentroid: Vector3
): (BasePart?, Vector3?)
	if #candidates == 0 then return nil, nil end

	local outwardHint = thrusterCentroid - packCentroid
	local outwardSign: Vector3
	if outwardHint.Magnitude < 1e-4 then
		outwardSign = -Vector3.yAxis
	else
		outwardSign = outwardHint.Unit
	end

	local axis = principalAxis(thrusterParts, thrusterCentroid)
	if axis:Dot(outwardSign) < 0 then
		axis = -axis
	end

	local bestPart: BasePart? = nil
	local bestProjection = -math.huge
	for _, part in candidates do
		local projection = (part.Position - thrusterCentroid):Dot(axis)
		if projection > bestProjection then
			bestProjection = projection
			bestPart = part
		end
	end

	return bestPart, axis
end

local function buildOrientationCFrame(position: Vector3, outward: Vector3): CFrame
	local downAxis = if outward.Magnitude > 1e-4 then outward.Unit else -Vector3.yAxis
	local localDown = VFX_LOCAL_DOWN_AXIS
	local dot = math.clamp(localDown:Dot(downAxis), -1, 1)

	if dot > 0.9999 then
		return CFrame.new(position)
	end

	if dot < -0.9999 then
		return CFrame.new(position) * CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
	end

	local axis = localDown:Cross(downAxis)
	if axis.Magnitude < 1e-4 then
		return CFrame.new(position)
	end

	local angle = math.acos(dot)
	return CFrame.new(position) * CFrame.fromAxisAngle(axis.Unit, angle)
end

local function disableEffects(vfxClone: Model)
	for _, descendant in vfxClone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = false
		end
	end
end

local function setVfxAnchored(vfxClone: Model)
	for _, descendant in vfxClone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		end
	end
end

-- Public Functions

function BuildThrusters.rig(
	wrapperModel: Model,
	hullRoot: BasePart,
	pack: PVInstance,
	thruster: PVInstance,
	vfxTemplate: Model
): RigResult
	local packCentroid, _ = GeometryUtils.getBodyBounds(pack)
	local thrusters = enumerateThrusters(thruster)

	local vfxClones: { Model } = {}

	for index, thrusterPV in thrusters do
		local thrusterParts = collectParts(thrusterPV)
		if #thrusterParts == 0 then
			vwarn(`thruster {index} has no parts; skipping`)
			continue
		end

		local exhaustPart: BasePart
		local position: Vector3
		local outward: Vector3

		if #thrusterParts == 1 then
			exhaustPart = thrusterParts[1]
			position, outward = pickLongestAxisExhaust(exhaustPart, packCentroid)
		else
			local thrusterCentroid, _ = GeometryUtils.getBodyBounds(thrusterPV)
			local candidates = pickKeywordCandidates(thrusterParts)
			local resolvedPart, exhaustAxis = pickExhaustPart(thrusterParts, candidates, thrusterCentroid, packCentroid)
			if not resolvedPart then
				vwarn(`thruster {index} could not resolve exhaust part; skipping`)
				continue
			end
			exhaustPart = resolvedPart

			if exhaustAxis and exhaustAxis.Magnitude > 1e-4 then
				outward = exhaustAxis.Unit
			else
				local fallback = exhaustPart.Position - thrusterCentroid
				if fallback.Magnitude > 1e-4 then
					outward = fallback.Unit
				else
					local packToThruster = thrusterCentroid - packCentroid
					outward = if packToThruster.Magnitude > 1e-4 then packToThruster.Unit else -Vector3.yAxis
				end
			end

			position = exhaustPart.Position
		end

		local vfxClone = vfxTemplate:Clone()
		vfxClone.Name = `{VFX_CLONE_PREFIX}{index}`

		local vfxRoot = vfxClone:FindFirstChildWhichIsA("BasePart")
		if not vfxRoot then
			vwarn(`vfx template missing BasePart; skipping thruster {index}`)
			vfxClone:Destroy()
			continue
		end

		setVfxAnchored(vfxClone)
		vfxClone.PrimaryPart = vfxRoot

		local targetCFrame = buildOrientationCFrame(position, outward)
		vfxClone:PivotTo(targetCFrame)

		disableEffects(vfxClone)

		vfxClone.Parent = wrapperModel

		ConstructionHelpers.makeWeld(exhaustPart, vfxRoot)

		table.insert(vfxClones, vfxClone)
	end

	return {
		VfxClones = vfxClones,
	}
end

-- Types

export type RigResult = {
	VfxClones: { Model },
}

-- Return

return BuildThrusters

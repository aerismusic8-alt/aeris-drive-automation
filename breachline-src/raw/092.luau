 single attachment at the gun's AABB front face, parented to
	     the largest part. Warns on use.
]]--

local FourD = script:FindFirstAncestor("FourD")
local GeometryUtils = require(FourD.Common.GeometryUtils)

local ALIGNMENT_DOT_THRESHOLD = 0.85
local ELONGATION_RATIO_THRESHOLD = 4
local WIDE_RATIO_THRESHOLD = 1.8
local LATERAL_OFFSET_RATIO = 0.92

local function getSortedLocalAxes(part: BasePart): { { axis: Vector3, length: number } }
	local axes = {
		{ axis = Vector3.xAxis, length = part.Size.X },
		{ axis = Vector3.yAxis, length = part.Size.Y },
		{ axis = Vector3.zAxis, length = part.Size.Z },
	}
	table.sort(axes, function(a, b)
		return a.length > b.length
	end)

	return axes
end

local function makeBarrelAttachment(part: BasePart, frontWorldPos: Vector3, fwd: Vector3, name: string): Attachment
	local lookCFrame = CFrame.lookAt(frontWorldPos, frontWorldPos + fwd)
	local localCFrame = part.CFrame:ToObjectSpace(lookCFrame)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = localCFrame
	attachment.Parent = part

	return attachment
end

local function tryMultiPartScan(parts: { BasePart }, fwd: Vector3): { Attachment }
	local attachments: { Attachment } = {}

	for _, part in ipairs(parts) do
		local sortedAxes = getSortedLocalAxes(part)
		local longLocal = sortedAxes[1].axis
		local longSize = sortedAxes[1].length
		local midSize = sortedAxes[2].length
		if midSize <= 0 then continue end

		local longWorld = part.CFrame:VectorToWorldSpace(longLocal)
		local alignment = longWorld:Dot(fwd)
		if math.abs(alignment) < ALIGNMENT_DOT_THRESHOLD then continue end

		local elongation = longSize / midSize
		if elongation < ELONGATION_RATIO_THRESHOLD then continue end

		local frontWorldPos = part.Position + fwd * (longSize * 0.5)
		local index = #attachments + 1
		table.insert(attachments, makeBarrelAttachment(part, frontWorldPos, fwd, "GunBarrel" .. index))
	end

	return attachments
end

local function tryWideMeshFallback(part: BasePart, fwd: Vector3): { Attachment }?
	if not part:IsA("MeshPart") then return nil end

	type AxisProjection = { axis: Vector3, length: number, fwdDot: number }
	local projections: { AxisProjection } = {}
	for _, entry in ipairs(getSortedLocalAxes(part)) do
		local worldAxis = part.CFrame:VectorToWorldSpace(entry.axis)
		table.insert(projections, {
			axis = worldAxis,
			length = entry.length,
			fwdDot = worldAxis:Dot(fwd),
		})
	end
	table.sort(projections, function(a, b)
		return math.abs(a.fwdDot) > math.abs(b.fwdDot)
	end)

	local forwardProj = projections[1]
	local perpA = projections[2]
	local perpB = projections[3]

	local sizeA, sizeB
	local wideAxis: Vector3
	if perpA.length >= perpB.length then
		sizeA, sizeB = perpA.length, perpB.length
		wideAxis = perpA.axis
	else
		sizeA, sizeB = perpB.length, perpA.length
		wideAxis = perpB.axis
	end

	if sizeB <= 0 then return nil end

	local frontCenter = part.Position + fwd * (forwardProj.length * 0.5)
	local attachments: { Attachment } = {}

	if sizeA / sizeB >= WIDE_RATIO_THRESHOLD then
		local lateral = wideAxis * (sizeA * 0.5 * LATERAL_OFFSET_RATIO)
		table.insert(attachments, makeBarrelAttachment(part, frontCenter - lateral, fwd, "GunBarrel1"))
		table.insert(attachments, makeBarrelAttachment(part, frontCenter + lateral, fwd, "GunBarrel2"))
	else
		table.insert(attachments, makeBarrelAttachment(part, frontCenter, fwd, "GunBarrel1"))
	end

	return attachments
end

local function singleFrontFaceFallback(gunModel: Model, parts: { BasePart }, fwd: Vector3): { Attachment }
	local largest = GeometryUtils.findLargestPart(gunModel) or parts[1]
	local cf = GeometryUtils.getInstanceCFrame(gunModel)
	local size = GeometryUtils.getInstanceSize(gunModel)
	local localFwd = cf:VectorToObjectSpace(fwd)
	local halfExtent =
		math.abs(localFwd.X) * size.X * 0.5
		+ math.abs(localFwd.Y) * size.Y * 0.5
		+ math.abs(localFwd.Z) * size.Z * 0.5
	local frontWorldPos = cf.Position + fwd * halfExtent

	return { makeBarrelAttachment(largest, frontWorldPos, fwd, "GunBarrel1") }
end

local function detectHardpoints(gunModel: Model, forwardAxis: Vector3): { Attachment }
	local parts = GeometryUtils.getInstanceParts(gunModel)
	if #parts == 0 then
		warn("[Gunnable.detectHardpoints] gun model has no BaseParts")
		return {}
	end

	local fwd = forwardAxis.Unit

	local barrels = tryMultiPartScan(parts, fwd)
	if #barrels > 0 then
		return barrels
	end

	if #parts == 1 then
		local meshFallback = tryWideMeshFallback(parts[1], fwd)
		if meshFallback then return meshFallback end
	end

	warn("[Gunnable.detectHardpoints] no elongated barrels found, defaulting to single front-face attachment")

	return singleFrontFaceFallback(gunModel, parts, fwd)
end

return detectHardpoints
^
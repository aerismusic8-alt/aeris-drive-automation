

local BARREL_KEYWORDS = { "barrel", "cannon", "tube", "bore" }
local BARREL_ALIGNMENT_THRESHOLD = 0.9
local MOUNT_KEYWORDS  = { "mount", "pivot", "swivel", "turret_base", "turret base", "base" }
local MUZZLE_KEYWORDS = { "muzzle", "flash", "nozzle", "tip" }

local function nameMatches(partName: string, keywords: { string }): boolean
	local lower = partName:lower()
	for _, kw in ipairs(keywords) do
		if lower:find(kw) then return true end
	end
	return false
end

local function getPartLongestAxisDir(part: BasePart): (Vector3, number)
	local s = part.Size
	local cf = part.CFrame
	local maxLen = s.X
	local axisDir = cf.RightVector

	if s.Y > maxLen then
		maxLen = s.Y
		axisDir = cf.UpVector
	end
	if s.Z > maxLen then
		maxLen = s.Z
		axisDir = -cf.LookVector
	end
	return axisDir, maxLen
end

---Estimates the forward direction of a gun model. Prefers parts whose names match
---`barrel`/`cannon`/`tube`/`bore` (length-weighted average); otherwise picks the part local axis
---(X, Y, or Z) most aligned with `carForward`; finally falls back to `carForward`.
---@param gunModel -- Model or BasePart representing the gun.
---@param carForward -- Vehicle forward direction used to disambiguate axis sign and as a fallback.
---@return forward -- Unit vector of the inferred barrel direction.
function GeometryUtils.detectGunForward(gunModel: Instance, carForward: Vector3): Vector3
	local parts = GeometryUtils.getInstanceParts(gunModel)
	if #parts == 0 then return carForward end

	local barrelDirs = {}
	local barrelWeights = {}
	for _, part in ipairs(parts) do
		if nameMatches(part.Name, BARREL_KEYWORDS) then
			local axisDir, axisLen = getPartLongestAxisDir(part)
			if axisDir:Dot(carForward) < 0 then axisDir = -axisDir end
			table.insert(barrelDirs, axisDir)
			table.insert(barrelWeights, axisLen)
		end
	end

	if #barrelDirs > 0 then
		local dominantDir = barrelDirs[1]
		local dominantLen = barrelWeights[1]
		for i, dir in ipairs(barrelDirs) do
			if barrelWeights[i] > dominantLen then
				dominantLen = barrelWeights[i]
				dominantDir = dir
			end
		end

		local weightedSum = Vector3.zero
		for i, dir in ipairs(barrelDirs) do
			if dir:Dot(dominantDir) >= BARREL_ALIGNMENT_THRESHOLD then
				weightedSum += dir * barrelWeights[i]
			end
		end
		if weightedSum.Magnitude > 0.001 then
			return weightedSum.Unit
		end
	end

	local AXIS_ALIGNMENT_THRESHOLD = 0.5
	local bestAlignment = 0
	local bestDir: Vector3? = nil
	for _, part in ipairs(parts) do
		local cf = part.CFrame
		local localAxes = {
			{ axis = cf.RightVector,  length = part.Size.X },
			{ axis = cf.UpVector,     length = part.Size.Y },
			{ axis = -cf.LookVector,  length = part.Size.Z },
		}
		for _, entry in ipairs(localAxes) do
			local alignment = math.abs(entry.axis:Dot(carForward)) * entry.length
			if alignment > bestAlignment then
				local dir = entry.axis
				if dir:Dot(carForward) < 0 then dir = -dir end
				bestAlignment = alignment
				bestDir = dir
			end
		end
	end

	if bestDir and math.abs(bestDir:Dot(carForward)) >= AXIS_ALIGNMENT_THRESHOLD then
		return bestDir
	end

	return carForward
end

---Locates the pivot point of a gun. Prefers parts named `mount`/`pivot`/`swivel`/`turret_base`/`base`;
---otherwise returns the model bounding-box center offset slightly downward; finally falls back to the
---primary part position or `Vector3.zero`.
---@param gunModel -- Model or BasePart representing the gun.
---@param gunForward -- Forward direction of the gun (currently unused but reserved for future heuristics).
---@return pivot -- World-space pivot position.
function GeometryUtils.findGunPivot(gunModel: Instance, gunForward: Vector3): Vector3
	local parts = GeometryUtils.getInstanceParts(gunModel)

	for _, part in ipairs(parts) do
		if nameMatches(part.Name, MOUNT_KEYWORDS) then
			return part.Position
		end
	end

	if gunModel:IsA("Model") then
		local cf, sz = gunModel:GetBoundingBox()
		return cf.Position - Vector3.new(0, sz.Y * 0.3, 0)
	end

	local anchor = GeometryUtils.getOrSetPrimaryPart(gunModel)
	if anchor then return anchor.Position end
	return Vector3.zero
end

---Locates the muzzle of a gun. Prefers parts matching muzzle keywords (`muzzle`/`flash`/`nozzle`/`tip`),
---then falls back to barrel parts, then to the most-forward part overall, and finally to a bounding-box
---offset along `gunForward`.
---@param gunModel -- Model or BasePart representing the gun.
---@param gunForward -- Unit vector pointing forward along the barrel.
---@return muzzlePart -- BasePart selected as the muzzle, or `nil` if none was found.
---@return tipPosition -- World-space position at the tip of the muzzle.
function GeometryUtils.findGunMuzzle(gunModel: Instance, gunForward: Vector3): (BasePart?, Vector3)
	local parts = GeometryUtils.getInstanceParts(gunModel)

	local muzzleParts = {}
	for _, part in ipairs(parts) do
		if nameMatches(part.Name, MUZZLE_KEYWORDS) then
			table.insert(muzzleParts, part)
		end
	end
	if #muzzleParts > 0 then
		local best, bestExtent = nil, -math.huge
		for _, part in ipairs(muzzleParts) do
			local ext = part.Position:Dot(gunForward) + part.Size.Magnitude * 0.5
			if ext > bestExtent then
				best = part
				bestExtent = ext
			end
		end
		if best then
			local cf = best.CFrame
			local halfExtent = 0.5 * (
				math.abs(gunForward:Dot(cf.RightVector)) * best.Size.X
				+ math.abs(gunForward:Dot(cf.UpVector)) * best.Size.Y
				+ math.abs(gunForward:Dot(cf.LookVector)) * best.Size.Z
			)
			return best, best.Position + gunForward * halfExtent
		end
	end

	local barrels = {}
	for _, part in ipairs(parts) do
		if nameMatches(part.Name, BARREL_KEYWORDS) then
			table.insert(barrels, part)
		end
	end
	if #barrels > 0 then
		local best, bestExtent = nil, -math.huge
		for _, part in ipairs(barrels) do
			local axisDir, axisLen = getPartLongestAxisDir(part)
			if axisDir:Dot(gunForward) < 0 then axisDir = -axisDir end
			local tipPos = part.Position + axisDir * (axisLen * 0.5)
			local ext = tipPos:Dot(gunForward)
			if ext > bestExtent then
				best = part
				bestExtent = ext
			end
		end
		if best then
			local axisDir, axisLen = getPartLongestAxisDir(best)
			if axisDir:Dot(gunForward) < 0 then axisDir = -axisDir end
			return best, best.Position + axisDir * (axisLen * 0.5)
		end
	end

	if #parts > 0 then
		local best, bestExtent = nil, -math.huge
		for _, part in ipairs(parts) do
			local ext = part.Position:Dot(gunForward)
			if ext > bestExtent then
				best = part
				bestExtent = ext
			end
		end
		if best then
			return best, best.Position + gunForward * (best.Size.Magnitude * 0.25)
		end
	end

	local fallbackPos = Vector3.zero
	if gunModel:IsA("Model") then
		local cf, sz = gunModel:GetBoundingBox()
		fallbackPos = cf.Position + gunForward * (sz.Magnitude * 0.5)
	end
	return nil, fallbackPos
end

---Returns the largest `BasePart` (by volume) inside `container`. If `container` is itself a `BasePart`,
---returns it directly.
---@param container -- BasePart, Model, or Folder to scan.
---@return largest -- BasePart with the greatest X*Y*Z volume, or `nil` if no parts were found.
function GeometryUtils.findLargestPart(container: Instance): BasePart?
	if container:IsA("BasePart") then
		return container
	end

	local best: BasePart? = nil
	local bestVolume = 0

	for _, part in GeometryUtils.getInstanceParts(container) do
		local volume = part.Size.X * part.Size.Y * part.Size.Z
		if volume > bestVolume then
			bestVolume = volume
			best = part
		end
	end

	return best
end


---Computes the volume-weighted centroid of `parts`. Each part contributes its position weighted by
---X*Y*Z volume.
---@param parts -- Array of BaseParts to combine.
---@return centroid -- Volume-weighted center; `Vector3.zero` if the total weight is zero.
---@return totalWeight -- Sum of part volumes.
function GeometryUtils.computeVolumeWeightedCentroid(parts: { BasePart }): (Vector3, number)
	local sum = Vector3.zero
	local totalWeight = 0
	for _, part in parts do
		local weight = part.Size.X * part.Size.Y * part.Size.Z
		sum = sum + part.Position * weight
		totalWeight = totalWeight + weight
	end
	if totalWeight == 0 then
		return Vector3.zero, 0
	end
	return sum / totalWeight, totalWeight
end

local function buildCovariance(parts: { BasePart }, centroid: Vector3): { number }
	local xx, xy, xz, yy, yz, zz = 0, 0, 0, 0, 0, 0
	for _, part in parts do
		local weight = part.Size.X * part.Size.Y * part.Size.Z
		local d = part.Position - centroid
		xx = xx + weight * d.X * d.X
		yy = yy + weight * d.Y * d.Y
		zz = zz + weight * d.Z * d.Z
		xy = xy + weight * d.X * d.Y
		xz = xz + weight * d.X * d.Z
		yz = yz + weight * d.Y * d.Z

		local partCFrame = part.CFrame
		local axes = { partCFrame.RightVector, partCFrame.UpVector, partCFrame.LookVector }
		local extents = { part.Size.X, part.Size.Y, part.Size.Z }
		for axisIndex = 1, 3 do
			local axis = axes[axisIndex]
			local extent = extents[axisIndex]
			local scalar = (weight * extent * extent) / 12
			xx = xx + scalar * axis.X * axis.X
			yy = yy + scalar * axis.Y * axis.Y
			zz = zz + scalar * axis.Z * axis.Z
			xy = xy + scalar * axis.X * axis.Y
			xz = xz + scalar * axis.X * axis.Z
			yz = yz + scalar * axis.Y * axis.Z
		end
	end
	return { xx, xy, xz, yy, yz, zz }
end

local function matrixMul(cov: { number }, v: Vector3): Vector3
	local xx, xy, xz, yy, yz, zz = cov[1], cov[2], cov[3], cov[4], cov[5], cov[6]
	return Vector3.new(
		xx * v.X + xy * v.Y + xz * v.Z,
		xy * v.X + yy * v.Y + yz * v.Z,
		xz * v.X + yz * v.Y + zz * v.Z
	)
end

local function rayleighQuotient(cov: { number }, v: Vector3): number
	local mv = matrixMul(cov, v)
	return v:Dot(mv)
end

local function powerIterate(cov: { number }, seed: Vector3, deflate: { Vector3 }?): Vector3
	local v = seed.Unit
	for _ = 1, 40 do
		local next = matrixMul(cov, v)
		if deflate then
			for _, axis in deflate do
				next = next - axis * next:Dot(axis)
			end
		end
		if next.Magnitude < 1e-8 then
			return v
		end
		v = next.Unit
	end
	return v
end

---Computes the three orthogonal principal axes of a part cluster around `centroid` using power
---iteration on the volume-weighted covariance matrix. The primary axis aligns with the direction of
---greatest variance.
---@param parts -- Array of BaseParts forming the cluster.
---@param centroid -- World-space centroid (typically from `computeVolumeWeightedCentroid`).
---@return primary -- Unit vector of the largest-variance axis.
---@return secondary -- Unit vector orthogonal to `primary`, second-largest variance.
---@return tertiary -- Unit vector orthogonal to both, smallest variance.
---@return eigenvalues -- Vector3 of Rayleigh quotients (variance magnitudes) along each axis.
function GeometryUtils.computePrincipalAxes(
	parts: { BasePart },
	centroid: Vector3
): (Vector3, Vector3, Vector3, Vector3)
	if #parts == 0 then
		return Vector3.xAxis, Vector3.yAxis, Vector3.zAxis, Vector3.zero
	end
	local cov = buildCovariance(parts, centroid)
	local primary = powerIterate(cov, Vector3.new(0.3, 1, 0.2))
	local secondarySeed = Vector3.new(1, 0.2, 0.3)
	if math.abs(secondarySeed:Dot(primary)) > 0.95 then
		secondarySeed = Vector3.new(0.2, 0.3, 1)
	end
	local secondary = powerIterate(cov, secondarySeed, { primary })
	local tertiary = primary:Cross(secondary).Unit
	secondary = tertiary:Cross(primary).Unit
	local eigenvalues = Vector3.new(
		rayleighQuotient(cov, primary),
		rayleighQuotient(cov, secondary),
		rayleighQuotient(cov, tertiary)
	)
	return primary, secondary, tertiary, eigenvalues
end

local function projectPartCorners(part: BasePart, axis: Vector3, origin: Vector3): (number, number)
	local cf = part.CFrame
	local half = part.Size * 0.5
	local minProj, maxProj = math.huge, -math.huge
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local corner = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
				local proj = (corner - origin):Dot(axis)
				minProj = math.min(minProj, proj)
				maxProj = math.max(maxProj, proj)
			end
		end
	end
	return minProj, maxProj
end

function GeometryUtils.measureExtentsInFrame(parts: { BasePart }, frame: CFrame): (Vector3, Vector3)
	if #parts == 0 then
		return frame.Position, Vector3.zero
	end

	local rightAxis = frame.RightVector
	local upAxis = frame.UpVector
	local backAxis = -frame.LookVector
	local origin = frame.Position

	local rMin, rMax = math.huge, -math.huge
	local uMin, uMax = math.huge, -math.huge
	local bMin, bMax = math.huge, -math.huge
	for _, part in parts do
		local rLow, rHigh = projectPartCorners(part, rightAxis, origin)
		local uLow, uHigh = projectPartCorners(part, upAxis, origin)
		local bLow, bHigh = projectPartCorners(part, backAxis, origin)
		rMin, rMax = math.min(rMin, rLow), math.max(rMax, rHigh)
		uMin, uMax = math.min(uMin, uLow), math.max(uMax, uHigh)
		bMin, bMax = math.min(bMin, bLow), math.max(bMax, bHigh)
	end

	local size = Vector3.new(rMax - rMin, uMax - uMin, bMax - bMin)
	local centerLocal = Vector3.new((rMin + rMax) * 0.5, (uMin + uMax) * 0.5, (bMin + bMax) * 0.5)
	return frame:PointToWorldSpace(centerLocal), size
end

---Creates an invisible `BasePart` sized and oriented to the true bounds of `model`, parents it to
---`model`, and assigns it as the `PrimaryPart`. Bounds come from projecting every descendant part's
---corners onto `referenceCFrame`'s axes, so the result never reads `PrimaryPart`, `WorldPivot` or
---`PivotOffset`, all of which can be corrupted on generated models.
---@param model -- Model to enclose. Must contain at least one BasePart.
---@param referenceCFrame -- Supplies the box orientation; its position is ignored.
---@param anchorName -- Name for the created part. Defaults to "BoundingBoxAnchor".
---@return anchor -- The created BasePart, parented to `model` and set as its PrimaryPart.
function GeometryUtils.createBoundingBoxAnchor(
	model: Model,
	referenceCFrame: CFrame,
	anchorName: string?
): BasePart
	local parts = GeometryUtils.getInstanceParts(model)
	if #parts == 0 then
		error("Expected at least one BasePart inside " .. model:GetFullName())
	end

	local center, size = GeometryUtils.measureExtentsInFrame(parts, referenceCFrame)

	local anchor = Instance.new("Part")
	anchor.Name = anchorName or "BoundingBoxAnchor"
	anchor.Size = size
	anchor.CFrame = referenceCFrame.Rotation + center
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.Anchored = false
	anchor.Parent = model
	model.PrimaryPart = anchor

	return anchor
end

--- Heuristically locates the towing coupler point of a hitch.
--- The hitch is assumed to sit toward the front of the assembled vehicle along its
--- longest axis; the coupler is the front-most extremity of the hitch geometry.
--- Names, sizes and orientation of the hitch parts are not relied upon.
---@param allParts -- every BasePart of the assembled vehicle.
---@param hitchParts -- the subset of parts that make up the hitch.
---@return couplerWorldCFrame -- world CFrame for the hitch attachment (front faces forward).
---@return anchorPart -- the hitch part nearest the coupler point, suitable to parent to.
function GeometryUtils.findCouplerPoint(
	allParts: { BasePart },
	hitchParts: { BasePart }
): (CFrame, BasePart)
	local centroid = GeometryUtils.computeVolumeWeightedCentroid(allParts)
	local primary, secondary, tertiary = GeometryUtils.computePrincipalAxes(allParts, centroid)

	local towAxis = primary
	local bestExtent = -math.huge
	for _, axis in { primary, secondary, tertiary } do
		local minProj, maxProj = math.huge, -math.huge
		for _, part in allParts do
			local lo, hi = projectPartCorners(part, axis, centroid)
			minProj = math.min(minProj, lo)
			maxProj = math.max(maxProj, hi)
		end
		local extent = maxProj - minProj
		if extent > bestExtent then
			bestExtent = extent
			towAxis = axis
		end
	end

	local hitchCentroid = GeometryUtils.computeVolumeWeightedCentroid(hitchParts)
	local centroidOffset = (hitchCentroid - centroid):Dot(towAxis)
	local forward = if centroidOffset < 0 then -towAxis else towAxis

	if math.abs(centroidOffset) < 0.5 then
		local hitchSet = {}
		for _, part in hitchParts do
			hitchSet[part] = true
		end

		local hitchMin, hitchMax = math.huge, -math.huge
		local otherMin, otherMax = math.huge, -math.huge
		local hasOther = false
		for _, part in allParts do
			local lo, hi = projectPartCorners(part, towAxis, centroid)
			if hitchSet[part] then
				hitchMin = math.min(hitchMin, lo)
				hitchMax = math.max(hitchMax, hi)
			else
				hasOther = true
				otherMin = math.min(otherMin, lo)
				otherMax = math.max(otherMax, hi)
			end
		end

		if hasOther then
			local protrusionPlus = hitchMax - otherMax
			local protrusionMinus = otherMin - hitchMin
			forward = if protrusionPlus >= protrusionMinus then towAxis else -towAxis
		end
	end

	local tipProj, rearProj = -math.huge, math.huge
	for _, part in hitchParts do
		local lo, hi = projectPartCorners(part, forward, centroid)
		tipProj = math.max(tipProj, hi)
		rearProj = math.min(rearProj, lo)
	end

	local frontBand = math.min(2, 0.15 * (tipProj - rearProj))
	local frontSum = Vector3.zero
	local frontWeight = 0
	for _, part in hitchParts do
		local _, hi = projectPartCorners(part, forward, centroid)
		if hi >= tipProj - frontBand then
			local weight = part.Size.X * part.Size.Y * part.Size.Z
			frontSum += part.Position * weight
			frontWeight += weight
		end
	end

	local frontCentre = if frontWeight > 0 then frontSum / frontWeight else hitchCentroid
	local frontCentreProj = (frontCentre - centroid):Dot(forward)
	local couplerPoint = frontCentre + forward * (tipProj - frontCentreProj)

	local anchorPart = hitchParts[1]
	local bestDist = math.huge
	for _, part in hitchParts do
		local dist = (part.Position - couplerPoint).Magnitude
		if dist < bestDist then
			bestDist = dist
			anchorPart = part
		end
	end

	return CFrame.lookAt(couplerPoint, couplerPoint + forward), anchorPart
end

return GeometryUtils

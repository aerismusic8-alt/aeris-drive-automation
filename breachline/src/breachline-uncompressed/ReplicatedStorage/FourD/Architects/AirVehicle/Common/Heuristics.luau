--[[
	File: Heuristics.luau
]]--

-- Root

local Heuristics = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local GeometryUtils = require(FourD.Common.GeometryUtils)

-- Constants

local BLADE_ELONGATION_RATIO = 2.0
local BLADE_DOMINANT_RATIO = 1.5
local BLADE_PERPENDICULAR_DOT_THRESHOLD = 0.5
local AABB_HORIZONTAL_RATIO_THRESHOLD = 1.1
local PRINCIPAL_AXIS_HORIZONTAL_THRESHOLD = 0.1
local HUB_NAME_KEYWORD = "hub"

-- Local Functions

local function flattenY(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function safeUnit(vector: Vector3, fallback: Vector3): Vector3
	if vector.Magnitude < 1e-4 then
		return fallback
	end

	return vector.Unit
end

local function snapToBodyAxis(worldDir: Vector3, bodyCFrame: CFrame): Vector3
	local localDir = bodyCFrame:VectorToObjectSpace(worldDir)
	local localAxis = if math.abs(localDir.X) >= math.abs(localDir.Z)
		then Vector3.xAxis * math.sign(localDir.X)
		else Vector3.zAxis * math.sign(localDir.Z)
	return safeUnit(flattenY(bodyCFrame:VectorToWorldSpace(localAxis)), safeUnit(worldDir, Vector3.xAxis))
end

---Orients an (unsigned) fore/aft `axis` using the body's mass distribution. The AABB
---longest-axis and principal-axis heuristics recover the fore/aft *line* but not which
---end is the nose, so on a body with no propeller/thruster/hint cue the sign is otherwise
---arbitrary. The bulky end pulls the volume-weighted centroid off the geometric (AABB)
---center: a helicopter's cabin sits forward of the thin tail boom, so the centroid leads
---the center along the forward axis. Returns `axis` flipped to point from the center
---toward that heavier end; if the body is too symmetric to tell, `axis` is unchanged.
local function orientByMassBulk(body: PVInstance, bodyCenter: Vector3, axis: Vector3): Vector3
	local parts = GeometryUtils.getInstanceParts(body)
	if #parts == 0 then
		return axis
	end
	local centroid = GeometryUtils.computeVolumeWeightedCentroid(parts)
	if flattenY(centroid - bodyCenter):Dot(axis) < 0 then
		return -axis
	end
	return axis
end

local function getPartLongestAxisDir(part: BasePart): (Vector3, number)
	local size = part.Size
	local cf = part.CFrame
	local maxLen = size.X
	local axisDir = cf.RightVector

	if size.Y > maxLen then
		maxLen = size.Y
		axisDir = cf.UpVector
	end

	if size.Z > maxLen then
		maxLen = size.Z
		axisDir = cf.LookVector
	end

	return axisDir, maxLen
end

local function findNamedHub(propellerPV: PVInstance): BasePart?
	for _, descendant in propellerPV:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end
		if string.find(string.lower(descendant.Name), HUB_NAME_KEYWORD) then
			return descendant
		end
	end

	return nil
end

local function solveBladeAxisIntersection(blades: { BasePart }): Vector3?
	local m11, m12, m13 = 0, 0, 0
	local m22, m23, m33 = 0, 0, 0
	local b1, b2, b3 = 0, 0, 0

	for _, blade in blades do
		local axis, _ = getPartLongestAxisDir(blade)
		local d = axis.Unit
		local p = blade.Position

		local pxx = 1 - d.X * d.X
		local pxy = -d.X * d.Y
		local pxz = -d.X * d.Z
		local pyy = 1 - d.Y * d.Y
		local pyz = -d.Y * d.Z
		local pzz = 1 - d.Z * d.Z

		m11 += pxx
		m12 += pxy
		m13 += pxz
		m22 += pyy
		m23 += pyz
		m33 += pzz

		b1 += pxx * p.X + pxy * p.Y + pxz * p.Z
		b2 += pxy * p.X + pyy * p.Y + pyz * p.Z
		b3 += pxz * p.X + pyz * p.Y + pzz * p.Z
	end

	local det = m11 * (m22 * m33 - m23 * m23)
		- m12 * (m12 * m33 - m23 * m13)
		+ m13 * (m12 * m23 - m22 * m13)

	if math.abs(det) < 1e-4 then
		return nil
	end

	local invDet = 1 / det
	local i11 = (m22 * m33 - m23 * m23) * invDet
	local i12 = (m13 * m23 - m12 * m33) * invDet
	local i13 = (m12 * m23 - m13 * m22) * invDet
	local i22 = (m11 * m33 - m13 * m13) * invDet
	local i23 = (m12 * m13 - m11 * m23) * invDet
	local i33 = (m11 * m22 - m12 * m12) * invDet

	local x = i11 * b1 + i12 * b2 + i13 * b3
	local y = i12 * b1 + i22 * b2 + i23 * b3
	local z = i13 * b1 + i23 * b2 + i33 * b3

	return Vector3.new(x, y, z)
end

local function averageInnerTips(blades: { BasePart }): Vector3
	local roughCenter = Vector3.zero
	for _, blade in blades do
		roughCenter += blade.Position
	end

	roughCenter /= #blades

	local innerSum = Vector3.zero
	for _, blade in blades do
		local longestAxis, longestLen = getPartLongestAxisDir(blade)
		local tipA = blade.Position + longestAxis * (longestLen * 0.5)
		local tipB = blade.Position - longestAxis * (longestLen * 0.5)
		local distA = (tipA - roughCenter).Magnitude
		local distB = (tipB - roughCenter).Magnitude
		local innerTip = if distA <= distB then tipA else tipB
		innerSum += innerTip
	end

	return innerSum / #blades
end

-- Public Functions

function Heuristics.stripPlaceholders(propellerPV: PVInstance)
	for _, descendant in propellerPV:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end
		if descendant.Transparency == 0 then continue end
		descendant:Destroy()
	end
end

function Heuristics.computePropPrincipalAxis(propellerPV: PVInstance): Vector3
	local parts = GeometryUtils.getInstanceParts(propellerPV)
	if #parts == 0 then
		return Vector3.yAxis
	end

	local centroid, _ = GeometryUtils.computeVolumeWeightedCentroid(parts)
	local primary, secondary, tertiary, _ = GeometryUtils.computePrincipalAxes(parts, centroid)

	-- A spinning rotor is significantly flatter on its rotation axis than the
	-- other two. Measure physical extents in the principal-axis frame and pick
	-- the flattest one as the spin axis. This is more reliable than ordering by
	-- eigenvalue magnitude, which is ambiguous for two-blade rotors where mass
	-- variance along the in-plane perpendicular and the disk normal are close.
	local axisFrame = CFrame.fromMatrix(centroid, primary, secondary, tertiary)
	local _, extents = GeometryUtils.measureExtentsInFrame(parts, axisFrame)

	local axes = { primary, secondary, tertiary }
	local sizes = { extents.X, extents.Y, extents.Z }
	local minIndex = 1
	for i = 2, 3 do
		if sizes[i] < sizes[minIndex] then
			minIndex = i
		end
	end

	return axes[minIndex].Unit
end

function Heuristics.detectBlades(propellerPV: PVInstance, spinAxis: Vector3): { BasePart }
	local blades: { BasePart } = {}
	local parts = GeometryUtils.getInstanceParts(propellerPV)

	for _, part in parts do
		local size = part.Size
		local sorted = { size.X, size.Y, size.Z }
		table.sort(sorted)
		local shortest = math.max(sorted[1], 1e-3)
		local middle = math.max(sorted[2], 1e-3)
		local longest = sorted[3]
		local elongation = longest / shortest
		local dominance = longest / middle

		if elongation < BLADE_ELONGATION_RATIO then continue end
		if dominance < BLADE_DOMINANT_RATIO then continue end

		local longestAxis, _ = getPartLongestAxisDir(part)
		if math.abs(longestAxis:Dot(spinAxis)) >= BLADE_PERPENDICULAR_DOT_THRESHOLD then continue end

		table.insert(blades, part)
	end

	return blades
end

function Heuristics.computeBladeMaxRadius(blades: { BasePart }, hubPos: Vector3, spinAxis: Vector3): number
	local maxRadius = 0
	local axis = spinAxis.Unit

	local function radialDistance(pos: Vector3): number
		local offset = pos - hubPos
		local axial = axis * offset:Dot(axis)
		local radial = offset - axial
		return radial.Magnitude
	end

	for _, blade in blades do
		local cf = blade.CFrame
		local half = blade.Size * 0.5
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local corner = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					maxRadius = math.max(maxRadius, radialDistance(corner))
				end
			end
		end
	end

	return maxRadius
end

function Heuristics.computeHubPosition(
	propellerPV: PVInstance,
	blades: { BasePart },
	fallbackCenter: Vector3,
	spinAxis: Vector3
): Vector3
	local namedHub = findNamedHub(propellerPV)
	if namedHub then
		return namedHub.Position
	end

	if #blades == 0 then
		return fallbackCenter
	end

	if #blades == 1 then
		return fallbackCenter
	end

	local intersection = solveBladeAxisIntersection(blades)
	if intersection then
		local _, propSize = GeometryUtils.getBodyBounds(propellerPV)
		if (intersection - fallbackCenter).Magnitude <= propSize.Magnitude then
			return intersection
		end
	end

	return averageInnerTips(blades)
end

function Heuristics.computeCentroid(pvList: { PVInstance }): Vector3
	if #pvList == 0 then
		return Vector3.zero
	end

	local weightedSum = Vector3.zero
	local totalWeight = 0

	for _, pv in pvList do
		local center, size = GeometryUtils.getBodyBounds(pv)
		local weight = size.X * size.Y * size.Z
		weightedSum += center * weight
		totalWeight += weight
	end

	if totalWeight <= 0 then
		return pvList[1] and GeometryUtils.getBodyBounds(pvList[1]) or Vector3.zero
	end

	return weightedSum / totalWeight
end

function Heuristics.detectForwardAxis(
	body: PVInstance,
	forwardHint: { PVInstance }?,
	towardCandidates: { PVInstance }?,
	awayCandidates: { PVInstance }?,
	warnLabel: string?
): Vector3
	local bodyCenter, bodySize = GeometryUtils.getBodyBounds(body)
	local bodyCFrame = GeometryUtils.getInstanceCFrame(body)

	if forwardHint and #forwardHint > 0 then
		local hintCentroid = Heuristics.computeCentroid(forwardHint)
		local direction = flattenY(hintCentroid - bodyCenter)
		if direction.Magnitude > 1e-3 then
			return snapToBodyAxis(direction, bodyCFrame)
		end
	end

	if towardCandidates and #towardCandidates > 0 then
		local towardCentroid = Heuristics.computeCentroid(towardCandidates)
		local direction = flattenY(towardCentroid - bodyCenter)
		if direction.Magnitude > 1e-3 then
			return snapToBodyAxis(direction, bodyCFrame)
		end
	end

	if awayCandidates and #awayCandidates > 0 then
		local awayCentroid = Heuristics.computeCentroid(awayCandidates)
		local direction = flattenY(bodyCenter - awayCentroid)
		if direction.Magnitude > 1e-3 then
			return snapToBodyAxis(direction, bodyCFrame)
		end
	end

	local horizontalLong = math.max(bodySize.X, bodySize.Z)
	local horizontalShort = math.max(math.min(bodySize.X, bodySize.Z), 1e-3)

	if horizontalLong / horizontalShort >= AABB_HORIZONTAL_RATIO_THRESHOLD then
		local localForward = if bodySize.X >= bodySize.Z then Vector3.xAxis else Vector3.zAxis
		local worldForward = flattenY(bodyCFrame:VectorToWorldSpace(localForward))
		if worldForward.Magnitude > 1e-3 then
			return orientByMassBulk(body, bodyCenter, worldForward.Unit)
		end
	end

	local parts = GeometryUtils.getInstanceParts(body)
	if #parts > 0 then
		local centroid, _ = GeometryUtils.computeVolumeWeightedCentroid(parts)
		local primary, _, _, _ = GeometryUtils.computePrincipalAxes(parts, centroid)
		local horizontal = flattenY(primary)
		if horizontal.Magnitude > PRINCIPAL_AXIS_HORIZONTAL_THRESHOLD then
			return orientByMassBulk(body, bodyCenter, snapToBodyAxis(horizontal, bodyCFrame))
		end
	end

	local label = warnLabel or "[AirVehicleHeuristics]"
	warn(`{label} forward axis ambiguous; defaulting to body LookVector`)
	return safeUnit(flattenY(bodyCFrame.LookVector), Vector3.xAxis)
end

-- Return

return Heuristics

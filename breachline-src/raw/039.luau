local GeometryUtils = require(script.Parent.GeometryUtils)

local DEFAULT_BUFFER = 3
local FACE_RESOLVERS: { [Face]: (CFrame, Vector3) -> (Vector3, number, Vector3) } = {
	Right = function(cf, s) return cf.RightVector, s.X * 0.5, cf.UpVector end,
	Left = function(cf, s) return -cf.RightVector, s.X * 0.5, cf.UpVector end,
	Front = function(cf, s) return cf.LookVector, s.Z * 0.5, cf.UpVector end,
	Back = function(cf, s) return -cf.LookVector, s.Z * 0.5, cf.UpVector end,
	Top = function(cf, s) return cf.UpVector, s.Y * 0.5, cf.LookVector end,
	Bottom = function(cf, s) return -cf.UpVector, s.Y * 0.5, cf.LookVector end,
}

export type Face = "Left" | "Right" | "Front" | "Back" | "Top" | "Bottom"

local function resolveAxis(face: Face, bboxCFrame: CFrame, size: Vector3): (Vector3, number, Vector3)
	local resolver = FACE_RESOLVERS[face]
	if not resolver then
		error("Invalid face: " .. tostring(face))
	end

	return resolver(bboxCFrame, size)
end

---Returns a CFrame positioned just outside a face of an instance's bounding box, oriented to look along the face normal.
---@param instance -- The instance whose bounding box defines the face.
---@param face -- Which face of the bounding box to anchor against ("Left", "Right", "Front", "Back", "Top", "Bottom").
---@param offset -- Optional CFrame applied after positioning. When omitted, a default buffer is added along the face normal.
---@return externalCFrame -- A CFrame outside the chosen face, looking along the outward axis.
return function(instance: PVInstance, face: Face, offset: CFrame?): CFrame
	local bboxCFrame = GeometryUtils.getInstanceCFrame(instance)
	local size = GeometryUtils.getInstanceSize(instance)
	local axisDir, halfExtent, upHint = resolveAxis(face, bboxCFrame, size)
	local pushDistance = halfExtent
	if not offset then pushDistance += DEFAULT_BUFFER end

	local result = CFrame.lookAlong(bboxCFrame.Position + axisDir * pushDistance, axisDir, upHint)
	if offset then
		result *= offset
	end

	return result
end

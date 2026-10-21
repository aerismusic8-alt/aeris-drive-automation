--[[
    GeometryUtils.lua
    Geometry utilities for spatial calculations using Roblox's built-in Vector3.
--]]
local GeometryUtils = {}

---Returns a representative `BasePart` for `instance`. If `instance` is a `Model` with no `PrimaryPart`,
---one is chosen and assigned. Returns `nil` (with a warning) for any other instance type.
---@param instance -- BasePart, Model, or other instance.
---@return primaryPart -- The BasePart itself, the model's PrimaryPart, or `nil`.
function GeometryUtils.getOrSetPrimaryPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if not instance:IsA("Model") then
		warn("Expected a Model or a BasePart, got " .. instance:GetFullName())
		return nil
	end
	if not instance.PrimaryPart then
		instance.PrimaryPart = instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return instance.PrimaryPart
end

---Returns the size of `instance`. For a `BasePart` returns `Size`; for a `Model` returns the
---bounding-box size. Errors for any other instance type.
---@param instance -- BasePart or Model.
---@return size -- Vector3 dimensions of the instance.
function GeometryUtils.getInstanceSize(instance: Instance): Vector3
	if instance:IsA("BasePart") then
		return instance.Size
	elseif instance:IsA("Model") then
		local _, size = instance:GetBoundingBox()
		return size
	else
		error("Expected a BasePart or a Model, got " .. instance:GetFullName())
	end
end

---Returns the CFrame of `instance`. For a `BasePart` returns `CFrame`; for a `Model` returns the
---bounding-box orientation. Errors for any other instance type.
---@param instance -- BasePart or Model.
---@return cframe -- World-space CFrame of the instance.
function GeometryUtils.getInstanceCFrame(instance: Instance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		local orientation, _ = instance:GetBoundingBox()
		return orientation
	else
		error("Expected a BasePart or a Model, got " .. instance:GetFullName())
	end
end

---Returns all `BasePart` descendants of `instance` recursively. For a `BasePart` returns a single-element
---array. Errors for any other instance type.
---@param instance -- BasePart or Model.
---@return parts -- Array of BaseParts found inside the instance.
function GeometryUtils.getInstanceParts(instance: Instance): { BasePart }
	if instance:IsA("BasePart") then
		return { instance }
	elseif instance:IsA("Model") then
		local instanceParts: { BasePart } = {}
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(instanceParts, descendant)
			end
		end
		return instanceParts
	else
		error("Expected a BasePart or a Model, got " .. instance:GetFullName())
	end
end

---Searches descendants of `root` for the first `BasePart` named `Chassis`.
---@param root -- Instance to scan.
---@return chassis -- The Chassis BasePart, or `nil` if none was found.
function GeometryUtils.findRigChassis(root: Instance): BasePart?
	for _, desc in ipairs(root:GetDescendants()) do
		if desc.Name == "Chassis" and desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

---Returns the world-space center and size of `body`. For a `Model` uses the bounding box; for a
---`BasePart` uses its position and size.
---@param body -- BasePart or Model.
---@return center -- World-space center position.
---@return size -- Vector3 dimensions.
function GeometryUtils.getBodyBounds(body: Instance): (Vector3, Vector3)
	if body:IsA("Model") then
		local cf, sz = body:GetBoundingBox()
		return cf.Position, sz
	end
	local part = GeometryUtils.getOrSetPrimaryPart(body)
	return part.Position, part.Size
end

---Returns the unit vector and length of the longest axis of `size`.
---@param size -- Vector3 to inspect.
---@return axis -- Unit vector along the longest axis (X, Y, or Z).
---@return length -- Magnitude of that axis.
function GeometryUtils.getLongestAxis(size: Vector3): (Vector3, number)
	if size.X >= size.Y and size.X >= size.Z then
		return Vector3.new(1, 0, 0), size.X
	elseif size.Z >= size.X and size.Z >= size.Y then
		return Vector3.new(0, 0, 1), size.Z
	else
		return Vector3.new(0, 1, 0), size.Y
	end
end

---Returns the unit vector and length of the shortest axis of `size`.
---@param size -- Vector3 to inspect.
---@return axis -- Unit vector along the shortest axis (X, Y, or Z).
---@return length -- Magnitude of that axis.
function GeometryUtils.getFlattestAxis(size: Vector3): (Vector3, number)
	if size.X <= size.Y and size.X <= size.Z then
		return Vector3.new(1, 0, 0), size.X
	elseif size.Z <= size.X and size.Z <= size.Y then
		return Vector3.new(0, 0, 1), size.Z
	else
		return Vector3.new(0, 1, 0), size.Y
	end
end

---Sums the mass of every non-massless `BasePart` at or beneath `object`.
---@param object -- BasePart, Model, or Folder to sum.
---@return totalMass -- Sum of part masses in mass units. Massless parts contribute zero.
function GeometryUtils.getTotalMass(object: BasePart|Model|Folder): number
	local result = 0

	if object:IsA("BasePart") and not object.Massless then
		result += object.Mass
	end

	for _, part in object:GetDescendants() do
		if not part:IsA("BasePart") or part.Massless then continue end
		result += part.Mass
	end

	return result
end

-- 
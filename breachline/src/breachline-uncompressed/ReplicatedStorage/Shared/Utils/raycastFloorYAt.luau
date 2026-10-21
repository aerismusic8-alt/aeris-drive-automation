-- Raycasts downward to find the floor Y position at a given location
local function raycastFloorYAt(position: Vector3, excluded: { Instance }?): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- A non-collidable overlay is not floor; without this a decal a stud above
	-- the ground reads as the floor.
	params.RespectCanCollide = true
	if excluded then
		params.FilterDescendantsInstances = excluded
	end
	local result = workspace:Raycast(position, Vector3.new(0, -10000, 0), params)
	if result then
		return result.Position.Y
	end
	-- Return nil (not 0) on a miss so callers can tell "no floor" from a real
	-- floor at Y = 0.
	return nil
end

return raycastFloorYAt

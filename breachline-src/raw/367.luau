local WaterUtils = {}

local DEFAULT_SEARCH_RANGE = 40

---Returns the Y-position sea level from the nearest waterbody.
---@param rootPos -- World space position to vertically search from.
---@param searchRange -- Optional range to search on the Y axis.
---@return waterLevel -- The terrain sea level. Returns `nil` if no terrain water was found.
function WaterUtils.getWaterLevel(rootPos: Vector3, searchRange: number?): number?
	local snapX = math.floor(rootPos.X / 4) * 4
	local snapZ = math.floor(rootPos.Z / 4) * 4
	local minY = math.floor((rootPos.Y - (searchRange or DEFAULT_SEARCH_RANGE)) / 4) * 4
	local maxY = math.ceil((rootPos.Y + (searchRange or DEFAULT_SEARCH_RANGE)) / 4) * 4

	local region = Region3.new(
		Vector3.new(snapX, minY, snapZ),
		Vector3.new(snapX + 4, maxY, snapZ + 4)
	)

	local success, channels = pcall(
		workspace.Terrain.ReadVoxelChannels, workspace.Terrain,
		region, 4, { "LiquidOccupancy" }
	)

	if not success or not channels then return nil end

	local liquid = channels.LiquidOccupancy
	if not liquid or not liquid[1] then return nil end

	local yCount = #liquid[1]
	for y = yCount, 1, -1 do
		local occ = liquid[1][y][1]
		if occ and occ > 0 then
			return (minY + (y - 1) * 4) + occ * 4
		end
	end

	return nil
end

return WaterUtils

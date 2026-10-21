--[[
	File: PruneFiltered.luau

	Destroys decorative gun descendants whose names contain any of the
	filtered keywords (muzzle flash / flame / light / fire visuals). Mirrors
	the AirVehicle Plane prune step but scoped to gun source models so that
	turrets and hardpoints scrub the same decoration regardless of host.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

local FILTERED_KEYWORDS = { "flash", "flame", "light", "fire" }

return function(gunModel: Model)
	local matches = ConstructionHelpers.findDescendantsByKeywords(gunModel, FILTERED_KEYWORDS)
	for _, instance in matches do
		instance:Destroy()
	end
end

--[[
	File: PruneFiltered.luau
]]--

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

-- Constants

local FILTERED_KEYWORDS = { "flash", "flame", "light", "fire" }

-- Local Functions

local function isPreserved(instance: Instance, preserve: { Instance }): boolean
	for _, preserved in preserve do
		if instance == preserved or instance:IsDescendantOf(preserved) then
			return true
		end
	end
	return false
end

-- Return

return function(bodyModel: Model, preserve: { Instance }?)
	local preserveList = preserve or {}
	local matches = ConstructionHelpers.findDescendantsByKeywords(bodyModel, FILTERED_KEYWORDS)
	for _, instance in matches do
		if not isPreserved(instance, preserveList) then
			instance:Destroy()
		end
	end
end

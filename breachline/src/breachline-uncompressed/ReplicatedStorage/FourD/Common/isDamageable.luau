--! strict
--[[
isDamageable - Check if a hit part is damageable
This utility checks if a part can receive damage based on:
1. If it belongs to a character with a living humanoid
2. If it or any ancestor has the "WeaponsSystemDamageable" tag
]]

local CollectionService = game:GetService("CollectionService")

local Common = script:FindFirstAncestor("Common")
local getCharacterFromPart = require(Common.getCharacterFromPart)

local function isDamageable(hitPart: BasePart): boolean
	-- First check if it's a character (humanoid)
	local character = getCharacterFromPart(hitPart)
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return true
		end
		return false
	end

	-- If not a character, check for other damageable objects (cars, etc.)
	-- Check if the hit part itself or its ancestors have the damageable tag
	if CollectionService:HasTag(hitPart, "WeaponsSystemDamageable") then
		return true
	end

	local ancestor = hitPart.Parent
	while ancestor and ancestor ~= workspace do
		if CollectionService:HasTag(ancestor, "WeaponsSystemDamageable") then
			return true
		end
		ancestor = ancestor.Parent
	end

	return false
end

return isDamageable

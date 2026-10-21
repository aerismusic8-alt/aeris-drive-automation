---Returns the accurate hip height of a player character. Used
---for placing the character on top of something.
---___
---#### Param(s):
---@param char Model The character `Model` to measure.
---___
---#### Returns:
---@return number hipHeight The accurate hip height of the character.
return function(char: Model): number
	local rootPart = char.PrimaryPart
	if not rootPart then return 0 end

	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid then return 0 end

	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return (rootPart.Size.Y / 2) + humanoid.HipHeight
	end

	local leftLeg = char:WaitForChild("Left Leg", 1)
	if not leftLeg then
		return 0
	end

	return leftLeg.Size.Y + rootPart.Size.Y
end

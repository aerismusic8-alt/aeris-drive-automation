--! strict

local function getCharacterFromPart(part: BasePart)
	local character = part

	while not (character == nil or (character:IsA("Model") and character:FindFirstChildOfClass("Humanoid"))) do
		character = character:FindFirstAncestorWhichIsA("Model")
	end

	return character
end

return getCharacterFromPart

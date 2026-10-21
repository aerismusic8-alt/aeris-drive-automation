local function setCharacterVisible(character: Model, visible: boolean)
	for _, obj in character:GetDescendants() do
		if obj:IsA("BasePart") then
			obj.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

return setCharacterVisible

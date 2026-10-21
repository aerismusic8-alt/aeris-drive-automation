--[[
	recenterModelPivot
	Sets a Model's WorldPivot to its bounding-box center without moving descendant
	parts. Preserves the existing pivot rotation unless resetRotation is true, in
	which case the pivot is also world-axis-aligned (rotation cleared).
--]]

local function recenterModelPivot(model: Model, resetRotation: boolean?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		local got = typeof(model) == "Instance" and model.ClassName or typeof(model)
		error("recenterModelPivot expected a Model, got " .. got)
	end

	local boundingCFrame = model:GetBoundingBox()

	if resetRotation then
		model.WorldPivot = CFrame.new(boundingCFrame.Position)
		return
	end

	local currentPivot = model:GetPivot()
	local rotationOnly = currentPivot - currentPivot.Position
	model.WorldPivot = CFrame.new(boundingCFrame.Position) * rotationOnly
end

return recenterModelPivot

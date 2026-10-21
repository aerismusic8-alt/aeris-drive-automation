local SeatHelpers = {}

-- Places a seat on a model's primary part based on config.seatPosition
-- seatPositionInput: "inside" (default) or "ontop"
function SeatHelpers.placeSeatOnModel(model, seat, seatPositionInput)
	assert(model and model:IsA("Model"), "model must be a Model")
	assert(seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")), "seat must be a Seat or VehicleSeat")

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	local primaryPart = model.PrimaryPart
	local seatHeight = seat.Size.Y

	local forwardVector = primaryPart.CFrame.LookVector
	local seatPosition = seatPositionInput or "inside"

	local rayOrigin, rayDirection
	if seatPosition == "ontop" then
		rayOrigin = primaryPart.Position + Vector3.new(0, (primaryPart.Size.Y / 2) + 1, 0)
		rayDirection = Vector3.new(0, -(primaryPart.Size.Y + 2), 0)
	else
		rayOrigin = primaryPart.Position + Vector3.new(0, -((primaryPart.Size.Y / 2) + 1), 0)
		rayDirection = Vector3.new(0, 20, 0)
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { model }
	params.FilterType = Enum.RaycastFilterType.Include
	params.IgnoreWater = true

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	local seatY
	if result and result.Instance == primaryPart then
		if seatPosition == "ontop" then
			-- on-top positioning...
			-- position seat so that the top of the seat is at the hit point.
			-- This means that the Avatar's bottom when sitting is close to the ray-hit surface
			seatY = result.Position.Y - (seatHeight / 2)
		else
			-- "inside" positioning. position seat so that the bottom of the seat is at the hit point.
			-- This means that the Avatar should be entirely inside the surface.
			seatY = result.Position.Y + (seatHeight / 2)
		end
	else
		-- ray hit nothing, position seat in the center of the model.
		seatY = primaryPart.Position.Y
		print("Seat positioning logic: WARNING. Ray hit nothing. Positioning seat in what might be empty space!")
	end

	seat.CFrame = CFrame.lookAlong(Vector3.new(primaryPart.Position.X, seatY, primaryPart.Position.Z), forwardVector)
end

return SeatHelpers
-
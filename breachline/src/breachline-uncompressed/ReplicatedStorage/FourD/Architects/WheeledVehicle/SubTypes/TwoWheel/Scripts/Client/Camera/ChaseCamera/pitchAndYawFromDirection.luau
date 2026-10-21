local function pitchAndYawFromDirection(direction: Vector3): (number, number)
	direction = direction.Unit
	local pitch = math.asin(direction.Y)
	local yaw = math.atan2(-direction.Z, direction.X) - math.pi / 2
	return pitch, yaw
end

return pitchAndYawFromDirection

local car = script.Parent.Parent.Parent.Parent

local suspension = {
	car.Suspension.WheelFRSuspension,
	car.Suspension.WheelFLSuspension,
	car.Suspension.WheelRRSuspension,
	car.Suspension.WheelRLSuspension,
}

-- Return the total length of all the suspension springs in the car
local function getSuspensionLength(): number
	local totalLength = 0

	for _, spring in suspension do
		totalLength += spring.CurrentLength
	end

	return totalLength
end

return getSuspensionLength

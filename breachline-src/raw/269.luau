local bike = script.Parent.Parent.Parent.Parent

local suspension = {
	bike.Suspension.WheelFSuspension,
	bike.Suspension.WheelRSuspension,
}

local function getSuspensionLength(): number
	local totalLength = 0

	for _, spring in suspension do
		totalLength += spring.CurrentLength
	end

	return totalLength
end

return getSuspensionLength

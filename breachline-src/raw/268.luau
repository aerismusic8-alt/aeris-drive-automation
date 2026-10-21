local bike = script.Parent.Parent.Parent.Parent
local chassis = bike.Chassis

local wheels = {
	bike.Wheels.WheelF.Wheel,
	bike.Wheels.WheelR.Wheel,
}

local function getAverageWheelSlip(): number
	local totalWheelSlip = 0

	local upVector = chassis.CFrame.UpVector

	for _, wheel in wheels do
		local angularVelocity = wheel.AssemblyAngularVelocity
		local linearVelocity = wheel.AssemblyLinearVelocity

		if angularVelocity.Magnitude == 0 then
			local slipAmount = linearVelocity.Magnitude
			totalWheelSlip += slipAmount
			continue
		end

		local wheelRadius = wheel.Size.Y / 2
		local targetSpeed = wheelRadius * angularVelocity.Magnitude
		local forward = angularVelocity.Unit:Cross(upVector)
		local targetVelocity = forward * targetSpeed
		local slipAmount = (targetVelocity - linearVelocity).Magnitude

		totalWheelSlip += slipAmount
	end

	return totalWheelSlip / #wheels
end

return getAverageWheelSlip
T
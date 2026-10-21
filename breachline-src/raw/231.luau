local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis

local wheels = {
	car.Wheels.WheelFR.Wheel,
	car.Wheels.WheelFL.Wheel,
	car.Wheels.WheelRR.Wheel,
	car.Wheels.WheelRL.Wheel,
}

-- Calculate the average amount of slippage of the car's wheels. This will be used to adjust
-- the volume of tire skidding sounds as the car drives.
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

		-- Calculate the target forward velocity based on the wheel's angular velocity
		local wheelRadius = wheel.Size.Y / 2
		local targetSpeed = wheelRadius * angularVelocity.Magnitude
		local forward = angularVelocity.Unit:Cross(upVector)
		local targetVelocity = forward * targetSpeed
		-- The slip amount is the difference between the target velocity and the wheel's actual linear velocity
		local slipAmount = (targetVelocity - linearVelocity).Magnitude

		totalWheelSlip += slipAmount
	end

	return totalWheelSlip / #wheels
end

return getAverageWheelSlip

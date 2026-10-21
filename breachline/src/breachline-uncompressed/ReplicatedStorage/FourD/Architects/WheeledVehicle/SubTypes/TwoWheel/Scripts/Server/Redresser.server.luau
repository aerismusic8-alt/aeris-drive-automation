local car = script.Parent.Parent.Parent
local chassis = car.Chassis
local redress = car.Redress
local redressOrientation = redress.RedressOrientation
local driverSeat = car:FindFirstChild("DriverSeat")

local FLIPPED_LIMIT = 0.5
local UPRIGHT_LIMIT = 0.7
local MOVING_LIMIT = 10

local redressParameters: { [string]: number } = {
	maxTimeFlipped = 2,
	redressMaxTorque = 500000,
	redressResponsiveness = 10,
}

local timeFlipped = 0

local function isFlipped(): boolean
	local chassisUp = chassis.CFrame.UpVector
	return chassisUp:Dot(Vector3.yAxis) < FLIPPED_LIMIT
end

local function isUpright(): boolean
	local chassisUp = chassis.CFrame.UpVector
	return chassisUp:Dot(Vector3.yAxis) > UPRIGHT_LIMIT
end

local function isMoving(): boolean
	return chassis.AssemblyLinearVelocity.Magnitude > MOVING_LIMIT
end

local function redressAsync()
	local forward = chassis.CFrame.LookVector
	if math.abs(forward:Dot(Vector3.yAxis)) > FLIPPED_LIMIT then
		forward = forward:Cross(chassis.CFrame.RightVector) * math.sign(forward:Dot(Vector3.yAxis))
	end
	local cframe = CFrame.lookAt(Vector3.zero, forward, Vector3.yAxis)
	redressOrientation.CFrame = cframe
	repeat
		task.wait()
	until isUpright()
end

local function initialize()
	for parameter in redressParameters do
		redress:GetAttributeChangedSignal(parameter):Connect(function()
			redressParameters[parameter] = redress:GetAttribute(parameter)
		end)

		redressParameters[parameter] = redress:GetAttribute(parameter)
	end

	task.spawn(function()
		while true do
			local deltaTime = task.wait(0.1)
			local isOccupied = driverSeat ~= nil and driverSeat.Occupant ~= nil
			if not isOccupied and isFlipped() and not isMoving() then
				timeFlipped += deltaTime
			else
				timeFlipped = 0
			end
			if timeFlipped >= redressParameters.maxTimeFlipped then
				timeFlipped = 0
				redressAsync()
			end
		end
	end)
end

initialize()

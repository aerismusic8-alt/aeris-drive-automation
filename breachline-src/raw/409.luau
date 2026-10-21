local car = script.Parent.Parent.Parent
local engine = car.Engine
local steering = car.Steering
local suspension = car.Suspension
local antiRoll = car.AntiRoll
local redress = car.Redress

-- Update suspension constraints
local function updateSuspension()
	local frontLength = suspension:GetAttribute("frontSuspensionLength")
	local frontStiffness = suspension:GetAttribute("frontSuspensionStiffness")
	local frontDamping = suspension:GetAttribute("frontSuspensionDamping")
	local rearLength = suspension:GetAttribute("rearSuspensionLength")
	local rearStiffness = suspension:GetAttribute("rearSuspensionStiffness")
	local rearDamping = suspension:GetAttribute("rearSuspensionDamping")
	local frontCamber = suspension:GetAttribute("frontCamber")
	local rearCamber = suspension:GetAttribute("rearCamber")

	suspension.WheelFRSuspension.FreeLength = frontLength
	suspension.WheelFRSuspension.Damping = frontDamping
	suspension.WheelFRSuspension.Stiffness = frontStiffness
	suspension.WheelFLSuspension.FreeLength = frontLength
	suspension.WheelFLSuspension.Stiffness = frontStiffness
	suspension.WheelFLSuspension.Damping = frontDamping
	suspension.WheelRRSuspension.FreeLength = rearLength
	suspension.WheelRRSuspension.Stiffness = rearStiffness
	suspension.WheelRRSuspension.Damping = rearDamping
	suspension.WheelRLSuspension.FreeLength = rearLength
	suspension.WheelRLSuspension.Stiffness = rearStiffness
	suspension.WheelRLSuspension.Damping = rearDamping

	engine.WheelFRMotor.InclinationAngle = 90 + frontCamber
	engine.WheelFLMotor.InclinationAngle = 90 + frontCamber
	engine.WheelRRMotor.InclinationAngle = 90 + rearCamber
	engine.WheelRLMotor.InclinationAngle = 90 + rearCamber
end

-- Update anti roll bar constraints
local function updateAntiRoll()
	local frontDamping = antiRoll:GetAttribute("frontAntiRollBarDamping")
	local frontStiffness = antiRoll:GetAttribute("frontAntiRollBarStiffness")
	local rearStiffness = antiRoll:GetAttribute("rearAntiRollBarStiffness")
	local rearDamping = antiRoll:GetAttribute("rearAntiRollBarDamping")

	antiRoll.AntiRollBarFR.Stiffness = frontStiffness
	antiRoll.AntiRollBarFR.Damping = frontDamping
	antiRoll.AntiRollBarFL.Stiffness = frontStiffness
	antiRoll.AntiRollBarFL.Damping = frontDamping
	antiRoll.AntiRollBarRR.Stiffness = rearStiffness
	antiRoll.AntiRollBarRR.Damping = rearDamping
	antiRoll.AntiRollBarRL.Stiffness = rearStiffness
	antiRoll.AntiRollBarRL.Damping = rearDamping
end

-- Update steering constraints
local function updateSteering()
	local length = steering:GetAttribute("steeringRackLength")
	local responsiveness = steering:GetAttribute("steeringRackResponsiveness")
	local speed = steering:GetAttribute("steeringRackSpeed")
	local maxForce = steering:GetAttribute("steeringRackMaxForce")

	steering.SteeringRack.UpperLimit = length
	steering.SteeringRack.LowerLimit = -length
	steering.SteeringRack.LinearResponsiveness = responsiveness
	steering.SteeringRack.Speed = speed
	steering.SteeringRack.ServoMaxForce = maxForce
end

-- Update redress constraints
local function updateRedress()
	local maxTorque = redress:GetAttribute("redressMaxTorque")
	local responsiveness = redress:GetAttribute("redressResponsiveness")

	redress.RedressOrientation.MaxTorque = maxTorque
	redress.RedressOrientation.Responsiveness = responsiveness
end

local function initialize()
	suspension.AttributeChanged:Connect(updateSuspension)
	antiRoll.AttributeChanged:Connect(updateAntiRoll)
	steering.AttributeChanged:Connect(updateSteering)
	redress.AttributeChanged:Connect(updateRedress)

	updateSuspension()
	updateAntiRoll()
	updateSteering()
	updateRedress()
end

initialize()

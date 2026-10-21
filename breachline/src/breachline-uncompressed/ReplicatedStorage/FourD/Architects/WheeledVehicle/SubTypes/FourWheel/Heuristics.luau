--[[
	File: Heuristics.luau

	Geometry heuristics + rig scaling/welding helpers for FourWheel.
]]--

-- Root

local Heuristics = {}

-- Dependencies

local FourD = script:FindFirstAncestor("FourD")
local Common = FourD.Common
local GeometryUtils = require(Common.GeometryUtils)

-- Types

type Wheel = BasePart | Model

type CarConfig = {
	seatPosition: ("inside" | "ontop")?,
	[string]: any,
}

-- Constants

local RIG_WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }
local SPRING_MASS_SCALE_FACTOR = 0.7

-- Local Functions

local function getWheelDiameter(wheel: Wheel): number
	if wheel:IsA("BasePart") then
		return math.max(wheel.Size.Y, wheel.Size.Z)
	end
	local _, sz = wheel:GetBoundingBox()
	return math.max(sz.X, sz.Y, sz.Z)
end

local function getWheelPrimaryPart(wheel: Wheel): BasePart
	if wheel:IsA("BasePart") then
		return wheel
	end

	local biggest = nil
	local biggestVolume = -1
	for _, descendant in wheel:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
		if volume > biggestVolume then
			biggestVolume = volume
			biggest = descendant
		end
	end

	assert(biggest, `wheel has no BasePart descendants: {wheel.Name}`)
	wheel.PrimaryPart = biggest
	return biggest
end

local function updateWheelPositions(
	frontLeftWheel: Wheel,
	frontRightWheel: Wheel,
	rearLeftWheel: Wheel,
	rearRightWheel: Wheel,
	carCFrame: CFrame,
	root: Model
)
	local frontLeftPart = getWheelPrimaryPart(frontLeftWheel)
	local frontRightPart = getWheelPrimaryPart(frontRightWheel)
	local rearLeftPart = getWheelPrimaryPart(rearLeftWheel)
	local rearRightPart = getWheelPrimaryPart(rearRightWheel)

	local frontDiameter = math.max(
		getWheelDiameter(frontLeftWheel),
		getWheelDiameter(frontRightWheel)
	)
	local rearDiameter = math.max(
		getWheelDiameter(rearLeftWheel),
		getWheelDiameter(rearRightWheel)
	)

	local rootCenter, rootSize = GeometryUtils.measureExtentsInFrame(GeometryUtils.getInstanceParts(root), carCFrame)
	local refFrame = CFrame.fromMatrix(rootCenter, carCFrame.RightVector, carCFrame.UpVector)

	local frontLeftLocal = refFrame:PointToObjectSpace(frontLeftPart.Position)
	local frontRightLocal = refFrame:PointToObjectSpace(frontRightPart.Position)
	local rearLeftLocal = refFrame:PointToObjectSpace(rearLeftPart.Position)
	local rearRightLocal = refFrame:PointToObjectSpace(rearRightPart.Position)

	local frontHalfAxle = math.max(
		math.abs(frontLeftLocal.X),
		math.abs(frontRightLocal.X),
		frontDiameter / 2
	)
	local rearHalfAxle = math.max(
		math.abs(rearLeftLocal.X),
		math.abs(rearRightLocal.X),
		rearDiameter / 2
	)

	local frontAxleZ = math.min(frontLeftLocal.Z, frontRightLocal.Z)
	local rearAxleZ = math.max(rearLeftLocal.Z, rearRightLocal.Z)
	local overlap = (frontAxleZ + frontDiameter / 2) - (rearAxleZ - rearDiameter / 2)
	if overlap > 0 then
		local nudge = overlap / 2
		frontAxleZ -= nudge
		rearAxleZ += nudge
	end

	local frontWheelY = -rootSize.Y / 2 + frontDiameter / 2
	local rearWheelY = -rootSize.Y / 2 + rearDiameter / 2

	local positions = {
		[frontLeftWheel] = refFrame:PointToWorldSpace(Vector3.new(-frontHalfAxle, frontWheelY, frontAxleZ)),
		[frontRightWheel] = refFrame:PointToWorldSpace(Vector3.new(frontHalfAxle, frontWheelY, frontAxleZ)),
		[rearLeftWheel] = refFrame:PointToWorldSpace(Vector3.new(-rearHalfAxle, rearWheelY, rearAxleZ)),
		[rearRightWheel] = refFrame:PointToWorldSpace(Vector3.new(rearHalfAxle, rearWheelY, rearAxleZ)),
	}

	for wheel, position in positions do
		wheel:PivotTo(wheel:GetPivot().Rotation + position)
	end
end

local function computeWorldDistanceBetweenAttachments(attach0: Attachment, attach1: Attachment): number
	return (attach1.WorldPosition - attach0.WorldPosition).Magnitude
end

local function scaleAttachmentPositions(parent: BasePart, scale: Vector3)
	for _, child in parent:GetChildren() do
		if not child:IsA("Attachment") then
			continue
		end

		local scaled = Vector3.new(
			scale.X * child.CFrame.Position.X,
			scale.Y * child.CFrame.Position.Y,
			scale.Z * child.CFrame.Position.Z
		)
		child.CFrame = child.CFrame.Rotation + scaled
	end
end

local function getCarRigMass(rig: Model): number
	local mass = 0
	for _, descendant in rig:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		if not descendant.CustomPhysicalProperties then
			continue
		end

		local density = descendant.CustomPhysicalProperties.Density
		mass += density * descendant.Size.X * descendant.Size.Y * descendant.Size.Z
	end
	return mass
end

local function rescalePartGroup(parts: { BasePart }, scale: number)
	local tempModel = Instance.new("Model")
	local tempPrimary = Instance.new("Part")
	tempPrimary.Size = Vector3.new(1, 1, 1)
	tempPrimary.CFrame = CFrame.new(0, 0, 0)
	tempPrimary.Parent = tempModel
	tempModel.PrimaryPart = tempPrimary

	local oldParents = {}
	for _, part in parts do
		oldParents[part] = part.Parent
		part.Parent = tempModel
	end

	tempModel:ScaleTo(scale)
	for part, parent in oldParents do
		part.Parent = parent
	end

	tempModel:Destroy()
end

-- Public Functions

function Heuristics.computeCarCFrame(
	frontLeftWheel: Wheel,
	frontRightWheel: Wheel,
	rearLeftWheel: Wheel,
	rearRightWheel: Wheel,
	body: Instance,
	asymmetricAxles: boolean?
): CFrame
	local frontLeftPosition = getWheelPrimaryPart(frontLeftWheel).Position
	local frontRightPosition = getWheelPrimaryPart(frontRightWheel).Position
	local rearLeftPosition = getWheelPrimaryPart(rearLeftWheel).Position
	local rearRightPosition = getWheelPrimaryPart(rearRightWheel).Position

	local wheelCentroid = (frontLeftPosition + frontRightPosition + rearLeftPosition + rearRightPosition) / 4
	local bodyCentroid = GeometryUtils.computeVolumeWeightedCentroid(GeometryUtils.getInstanceParts(body))

	local forwardRaw = ((frontLeftPosition + frontRightPosition) - (rearLeftPosition + rearRightPosition)) * 0.5
	local rightRaw = ((frontRightPosition + rearRightPosition) - (frontLeftPosition + rearLeftPosition)) * 0.5

	local up
	if asymmetricAxles then
		up = Vector3.yAxis
	else
		up = rightRaw:Cross(forwardRaw)
		if up.Magnitude < 1e-4 then
			up = Vector3.yAxis
		end
		up = up.Unit
		if up:Dot(bodyCentroid - wheelCentroid) < 0 then
			up = -up
		end
	end

	local forward = forwardRaw - forwardRaw:Dot(up) * up
	assert(forward.Magnitude >= 1e-4, "FourWheel: cannot determine forward axis; front and rear wheels coincide")
	forward = forward.Unit

	local right = forward:Cross(up).Unit

	local center = GeometryUtils.measureExtentsInFrame(
		GeometryUtils.getInstanceParts(body),
		CFrame.fromMatrix(Vector3.zero, right, up)
	)

	return CFrame.fromMatrix(center, right, up)
end

function Heuristics.prepareGeometry(
	root: Model,
	frontLeftWheel: Wheel,
	frontRightWheel: Wheel,
	rearLeftWheel: Wheel,
	rearRightWheel: Wheel,
	body: Instance,
	carCFrame: CFrame
)
	local wheels = { frontLeftWheel, frontRightWheel, rearLeftWheel, rearRightWheel }
	for _, wheel in wheels do
		for _, part in GeometryUtils.getInstanceParts(wheel) do
			part.CanCollide = false
			part.Massless = true
		end
	end

	for _, part in GeometryUtils.getInstanceParts(body) do
		part.Massless = true
	end

	updateWheelPositions(frontLeftWheel, frontRightWheel, rearLeftWheel, rearRightWheel, carCFrame, root)
end

function Heuristics.updateCarRig(
	carRig: Model,
	frontLeftWheel: Wheel,
	frontRightWheel: Wheel,
	rearLeftWheel: Wheel,
	rearRightWheel: Wheel,
	body: Model,
	carCFrame: CFrame
)
	local rigPrimary = carRig.PrimaryPart
	local initialMass = getCarRigMass(carRig)
	carRig:PivotTo(CFrame.new(carRig:GetPivot().Position) * carCFrame.Rotation)

	local bodyCenter, bodySize = GeometryUtils.measureExtentsInFrame(GeometryUtils.getInstanceParts(body), carCFrame)
	carRig:TranslateBy(bodyCenter - rigPrimary.Position)

	local modelWheels = {
		getWheelPrimaryPart(frontLeftWheel),
		getWheelPrimaryPart(frontRightWheel),
		getWheelPrimaryPart(rearLeftWheel),
		getWheelPrimaryPart(rearRightWheel),
	}

	local newFrontWheelSize = math.max(
		getWheelDiameter(frontLeftWheel),
		getWheelDiameter(frontRightWheel)
	)
	local newRearWheelSize = math.max(
		getWheelDiameter(rearLeftWheel),
		getWheelDiameter(rearRightWheel)
	)
	local wheelCentroid = 0.25
		* (modelWheels[1].Position + modelWheels[2].Position + modelWheels[3].Position + modelWheels[4].Position)

	carRig:TranslateBy(
		wheelCentroid
			+ carCFrame.UpVector * (math.max(newFrontWheelSize, newRearWheelSize) * 0.5)
			- rigPrimary.Position
	)

	local wheelsFolder = carRig:WaitForChild("Wheels")
	local frontWheelL = wheelsFolder:WaitForChild("WheelFL")
	local frontWheelR = wheelsFolder:WaitForChild("WheelFR")
	local rearWheelL = wheelsFolder:WaitForChild("WheelRL")
	local rearWheelR = wheelsFolder:WaitForChild("WheelRR")
	local frontAntiRollBar = carRig:WaitForChild("FrontAntiRollBar")
	local rearAntiRollBar = carRig:WaitForChild("RearAntiRollBar")
	local steeringRack = carRig:WaitForChild("SteeringRack")
	local chassis = carRig:WaitForChild("Chassis")

	local frontWheelScale = newFrontWheelSize / frontWheelL.PrimaryPart.Size.X
	local rearWheelScale = newRearWheelSize / rearWheelL.PrimaryPart.Size.X
	rescalePartGroup({ frontWheelL, frontWheelR, frontAntiRollBar, steeringRack }, frontWheelScale)
	rescalePartGroup({ rearWheelL, rearWheelR, rearAntiRollBar }, rearWheelScale)

	local chassisScale = Vector3.new(bodySize.X / chassis.Size.X, 1, bodySize.Z / chassis.Size.Z)
	chassis.Size = Vector3.new(bodySize.X, chassis.Size.Y, bodySize.Z)
	scaleAttachmentPositions(chassis, chassisScale)

	for i, wheelName in RIG_WHEEL_NAMES do
		local wheelModel = wheelsFolder:WaitForChild(wheelName)
		wheelModel.Mount.WeldConstraint.Enabled = false
		wheelModel:TranslateBy(modelWheels[i].Position - wheelModel.PrimaryPart.Position)
		wheelModel.Mount.WeldConstraint.Enabled = true
	end

	for _, wheelName in RIG_WHEEL_NAMES do
		local chassisWheelAttachment = chassis:WaitForChild(wheelName)
		local wheelModel = wheelsFolder:WaitForChild(wheelName)
		local motorAttachment = wheelModel:WaitForChild("Wheel"):WaitForChild("MotorAttachment")
		chassisWheelAttachment.Position = chassis.CFrame:PointToObjectSpace(motorAttachment.WorldCFrame.Position)
	end

	local frontBarLocalZ = chassis.CFrame:PointToObjectSpace(frontWheelL.PrimaryPart.Position).Z
	local rearBarLocalZ = chassis.CFrame:PointToObjectSpace(rearWheelL.PrimaryPart.Position).Z
	frontAntiRollBar.Position = chassis.CFrame:PointToWorldSpace(Vector3.new(0, 0, frontBarLocalZ))
	rearAntiRollBar.Position = chassis.CFrame:PointToWorldSpace(Vector3.new(0, 0, rearBarLocalZ))

	local frontAntiRollBarScale = Vector3.new(chassis.Size.X / frontAntiRollBar.Size.X, 1, 1)
	local rearAntiRollBarScale = Vector3.new(chassis.Size.X / rearAntiRollBar.Size.X, 1, 1)
	frontAntiRollBar.Size = Vector3.new(chassis.Size.X, frontAntiRollBar.Size.Y, frontAntiRollBar.Size.Z)
	rearAntiRollBar.Size = Vector3.new(chassis.Size.X, rearAntiRollBar.Size.Y, rearAntiRollBar.Size.Z)

	scaleAttachmentPositions(frontAntiRollBar, frontAntiRollBarScale)
	scaleAttachmentPositions(rearAntiRollBar, rearAntiRollBarScale)

	local antiRoll = carRig:WaitForChild("AntiRoll")
	for _, springName in { "AntiRollBarFL", "AntiRollBarFR", "AntiRollBarRL", "AntiRollBarRR" } do
		local spring = antiRoll:WaitForChild(springName)
		spring.FreeLength = spring.CurrentLength
	end

	local suspension = carRig:WaitForChild("Suspension")
	for _, springName in { "WheelFLSuspension", "WheelFRSuspension", "WheelRLSuspension", "WheelRRSuspension" } do
		local suspensionSpring = suspension:FindFirstChild(springName)
		if not suspensionSpring then continue end
		suspensionSpring.FreeLength =
			computeWorldDistanceBetweenAttachments(suspensionSpring.Attachment0, suspensionSpring.Attachment1)
	end

	for _, spring in antiRoll:GetChildren() do
		spring.FreeLength = (spring.Attachment0.WorldCFrame.Position - spring.Attachment1.WorldCFrame.Position).Magnitude
	end

	local finalMass = getCarRigMass(carRig)
	local massScale = if initialMass > 0 then finalMass / initialMass else 1
	local springScale = massScale * SPRING_MASS_SCALE_FACTOR

	for _, springName in { "WheelFLSuspension", "WheelFRSuspension", "WheelRLSuspension", "WheelRRSuspension" } do
		local suspensionSpring = suspension:FindFirstChild(springName)
		if not suspensionSpring then continue end
		suspensionSpring.Stiffness *= springScale
		suspensionSpring.Damping *= springScale
	end

	for _, spring in antiRoll:GetChildren() do
		if spring:IsA("SpringConstraint") then
			spring.Stiffness *= springScale
			spring.Damping *= springScale
		end
	end

	local frontSuspensionSpring = suspension.WheelFLSuspension
	local rearSuspensionSpring = suspension.WheelRLSuspension
	suspension:SetAttribute("frontSuspensionDamping", frontSuspensionSpring.Damping)
	suspension:SetAttribute("rearSuspensionDamping", rearSuspensionSpring.Damping)
	suspension:SetAttribute("frontSuspensionLength", frontSuspensionSpring.FreeLength)
	suspension:SetAttribute("rearSuspensionLength", rearSuspensionSpring.FreeLength)
	suspension:SetAttribute("frontSuspensionStiffness", frontSuspensionSpring.Stiffness)
	suspension:SetAttribute("rearSuspensionStiffness", rearSuspensionSpring.Stiffness)
	local scaledTotalSpringConstant = 2 * (frontSuspensionSpring.Stiffness + rearSuspensionSpring.Stiffness)

	local redress = carRig:WaitForChild("Redress")
	redress:SetAttribute("redressMaxTorque", redress.RedressOrientation.MaxTorque)

	local scaledAntiRollSpring = antiRoll.AntiRollBarFL
	antiRoll:SetAttribute("frontAntiRollBarDamping", scaledAntiRollSpring.Damping)
	antiRoll:SetAttribute("rearAntiRollBarDamping", scaledAntiRollSpring.Damping)
	antiRoll:SetAttribute("frontAntiRollBarStiffness", scaledAntiRollSpring.Stiffness)
	antiRoll:SetAttribute("rearAntiRollBarStiffness", scaledAntiRollSpring.Stiffness)

	local wheelFLAttach = frontWheelL.Knuckle.SteeringAttachment
	local wheelFRAttach = frontWheelR.Knuckle.SteeringAttachment
	steeringRack.Position = (wheelFLAttach.WorldCFrame.Position + wheelFRAttach.WorldCFrame.Position) * 0.5
	chassis.SteeringAttachment.Position = chassis.CFrame:PointToObjectSpace(steeringRack.Position)

	for _, rod in steeringRack:GetChildren() do
		if not rod:IsA("RodConstraint") then
			continue
		end

		rod.Length = (rod.Attachment0.WorldCFrame.Position - rod.Attachment1.WorldCFrame.Position).Magnitude
	end

	local maxSteeringDelta = math.min(1, chassis.Size.X / 8)
	local steering = carRig:WaitForChild("Steering")
	steering:SetAttribute("steeringRackLength", maxSteeringDelta)

	local nitroOffset = chassis.CFrame:PointToObjectSpace(bodyCenter) + Vector3.new(0, 0, bodySize.Z * 0.5)
	chassis.LeftNitroEmitterAttachment.Position = nitroOffset
	chassis.RightNitroEmitterAttachment.Position = nitroOffset
	chassis.DrivePromptAttachment.DrivePrompt.MaxActivationDistance = bodySize.X * 0.5 + 10

	local gravityForce = workspace.Gravity
	local chassisMass = chassis.CustomPhysicalProperties.Density
		* chassis.Size.X
		* chassis.Size.Y
		* chassis.Size.Z
	local settleDistance = chassisMass * gravityForce / scaledTotalSpringConstant
	body:TranslateBy(carCFrame.UpVector * settleDistance)

	chassis.HoodCameraAttachment.Position =
		chassis.CFrame:PointToObjectSpace(bodyCenter) - Vector3.new(0, 0, bodySize.Z * 0.5)

	local engine = carRig:WaitForChild("Engine")
	for _, engineAttr in { "minSpeedTorque", "maxSpeedTorque", "handBrakeTorque", "nitroTorque" } do
		engine:SetAttribute(engineAttr, engine:GetAttribute(engineAttr) * massScale)
	end
end

function Heuristics.attachGeometryToCarRig(
	carRig: Model,
	frontLeftWheel: Instance,
	frontRightWheel: Instance,
	rearLeftWheel: Instance,
	rearRightWheel: Instance,
	body: Instance,
	extraParts: { PVInstance }
)
	local function weldPartsToParent(parts: { BasePart }, parent: BasePart, weldName: string)
		for _, part in parts do
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = parent
			weld.Part1 = part
			weld.Name = weldName
			weld.Parent = parent
		end
	end

	local rigChassis = carRig:FindFirstChild("Chassis")
	local bodyParts = GeometryUtils.getInstanceParts(body)
	weldPartsToParent(bodyParts, rigChassis, "BodyWeld")

	local extraPartParts: { BasePart } = {}
	for _, extraPart in extraParts do
		local parts = GeometryUtils.getInstanceParts(extraPart)
		weldPartsToParent(parts, rigChassis, "ExtraPartWeld")
		for _, part in parts do
			table.insert(extraPartParts, part)
		end
	end

	local wheelsFolder = carRig:WaitForChild("Wheels")
	local wheelBindings = {
		{ RigName = "WheelFL", Source = frontLeftWheel },
		{ RigName = "WheelFR", Source = frontRightWheel },
		{ RigName = "WheelRL", Source = rearLeftWheel },
		{ RigName = "WheelRR", Source = rearRightWheel },
	}

	local rigWheelParts: { BasePart } = {}
	for _, binding in wheelBindings do
		local rigWheelModel = wheelsFolder:FindFirstChild(binding.RigName)
		local rigWheel = rigWheelModel:FindFirstChild("Wheel")
		local parts = GeometryUtils.getInstanceParts(binding.Source)
		weldPartsToParent(parts, rigWheel, binding.Source.Name .. "Weld")
		table.insert(rigWheelParts, rigWheel)
	end

	for _, part in bodyParts do
		for _, wheel in rigWheelParts do
			local noCollide = Instance.new("NoCollisionConstraint")
			noCollide.Part0 = part
			noCollide.Part1 = wheel
			noCollide.Parent = part
		end
	end

	local rigParts: { BasePart } = {}
	for _, rigPart in carRig:GetDescendants() do
		if rigPart:IsA("BasePart") then
			table.insert(rigParts, rigPart)
		end
	end

	for _, extraPartPart in extraPartParts do
		for _, rigPart in rigParts do
			local noCollide = Instance.new("NoCollisionConstraint")
			noCollide.Part0 = extraPartPart
			noCollide.Part1 = rigPart
			noCollide.Parent = extraPartPart
		end
	end
end

-- Return

return Heuristics

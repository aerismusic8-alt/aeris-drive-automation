--[[
	File: Heuristics.luau
]]--

-- Root

local Heuristics = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Common = FourD:WaitForChild("Common")
local GeometryUtils = require(Common.GeometryUtils)

-- Constants

local RIG_WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }
local FORWARD_EPSILON = 1e-4
local SIDE_EPSILON = 1e-4

-- Types

export type Wheel = Model | BasePart

-- Local Functions

local function getWheelDiameter(wheel: Wheel): number
	if wheel:IsA("BasePart") then
		return math.max(wheel.Size.X, wheel.Size.Y, wheel.Size.Z)
	end

	local _, sz = wheel:GetBoundingBox()
	return math.max(sz.X, sz.Y, sz.Z)
end

local function getWheelPrimaryPart(wheel: Wheel): BasePart
	if wheel:IsA("BasePart") then
		return wheel
	end

	local biggest: BasePart? = nil
	local biggestVolume = -1
	for _, descendant in wheel:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end

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

local function getBoardForward(
	flWheel: BasePart,
	frWheel: BasePart,
	rlWheel: BasePart,
	rrWheel: BasePart
): Vector3
	local frontMid = (flWheel.Position + frWheel.Position) / 2
	local rearMid = (rlWheel.Position + rrWheel.Position) / 2
	local delta = frontMid - rearMid
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < FORWARD_EPSILON then
		return Vector3.new(0, 0, -1)
	end

	return flat.Unit
end

local function getBoardSide(forward: Vector3): Vector3
	local cross = Vector3.yAxis:Cross(forward)
	if cross.Magnitude < SIDE_EPSILON then
		return Vector3.xAxis
	end

	return cross.Unit
end

local function computeBoardDimensions(body: Instance, forward: Vector3): (number, number)
	local side = getBoardSide(forward)
	local minF, maxF = math.huge, -math.huge
	local minS, maxS = math.huge, -math.huge

	for _, part in GeometryUtils.getInstanceParts(body) do
		local cf = part.CFrame
		local hx = part.Size.X * 0.5
		local hy = part.Size.Y * 0.5
		local hz = part.Size.Z * 0.5

		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local corner = cf * Vector3.new(sx * hx, sy * hy, sz * hz)
					local f = corner:Dot(forward)
					local s = corner:Dot(side)
					if f < minF then minF = f end
					if f > maxF then maxF = f end
					if s < minS then minS = s end
					if s > maxS then maxS = s end
				end
			end
		end
	end

	local length = math.max(maxF - minF, 0.01)
	local width = math.max(maxS - minS, 0.01)
	return length, width
end

local function rescalePartGroup(parts: { BasePart }, scale: number)
	local tempModel = Instance.new("Model")
	local tempPrimary = Instance.new("Part")
	tempPrimary.Size = Vector3.one
	tempPrimary.CFrame = CFrame.new(0, 0, 0)
	tempPrimary.Parent = tempModel
	tempModel.PrimaryPart = tempPrimary

	local oldParents: { [BasePart]: Instance } = {}
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

local function scaleAttachmentPositions(parent: BasePart, scale: Vector3)
	for _, child in parent:GetChildren() do
		if not child:IsA("Attachment") then continue end

		local scaled = Vector3.new(
			scale.X * child.CFrame.Position.X,
			scale.Y * child.CFrame.Position.Y,
			scale.Z * child.CFrame.Position.Z
		)
		child.CFrame = child.CFrame.Rotation + scaled
	end
end

local function updateWheelPositions(
	flWheel: Wheel,
	frWheel: Wheel,
	rlWheel: Wheel,
	rrWheel: Wheel,
	rootCenter: Vector3,
	rootSizeY: number
)
	local frontLeftPart = getWheelPrimaryPart(flWheel)
	local frontRightPart = getWheelPrimaryPart(frWheel)
	local rearLeftPart = getWheelPrimaryPart(rlWheel)
	local rearRightPart = getWheelPrimaryPart(rrWheel)

	local frontDiameter = math.max(getWheelDiameter(flWheel), getWheelDiameter(frWheel))
	local rearDiameter = math.max(getWheelDiameter(rlWheel), getWheelDiameter(rrWheel))

	local frontHalfAxle = math.max(
		math.abs(frontLeftPart.Position.X - rootCenter.X),
		math.abs(frontRightPart.Position.X - rootCenter.X),
		frontDiameter / 2
	)
	local rearHalfAxle = math.max(
		math.abs(rearLeftPart.Position.X - rootCenter.X),
		math.abs(rearRightPart.Position.X - rootCenter.X),
		rearDiameter / 2
	)

	local frontAxleZ = math.min(frontLeftPart.Position.Z, frontRightPart.Position.Z) - rootCenter.Z
	local rearAxleZ = math.max(rearLeftPart.Position.Z, rearRightPart.Position.Z) - rootCenter.Z
	local overlap = (frontAxleZ + frontDiameter / 2) - (rearAxleZ - rearDiameter / 2)
	if overlap > 0 then
		local nudge = overlap / 2
		frontAxleZ -= nudge
		rearAxleZ += nudge
	end

	local frontWheelY = -rootSizeY / 2 + frontDiameter / 2
	local rearWheelY = -rootSizeY / 2 + rearDiameter / 2

	local positions: { [Wheel]: Vector3 } = {
		[flWheel] = rootCenter + Vector3.new(-frontHalfAxle, frontWheelY, frontAxleZ),
		[frWheel] = rootCenter + Vector3.new(frontHalfAxle, frontWheelY, frontAxleZ),
		[rlWheel] = rootCenter + Vector3.new(-rearHalfAxle, rearWheelY, rearAxleZ),
		[rrWheel] = rootCenter + Vector3.new(rearHalfAxle, rearWheelY, rearAxleZ),
	}

	for wheel, position in positions do
		if wheel:IsA("BasePart") then
			wheel.Position = position
		elseif wheel:IsA("Model") then
			wheel:MoveTo(position)
		else
			error("Invalid wheel type: " .. wheel.Name)
		end
	end
end

-- Public Functions

function Heuristics.prepareGeometry(
	root: Model,
	flWheel: Wheel,
	frWheel: Wheel,
	rlWheel: Wheel,
	rrWheel: Wheel,
	body: Instance
)
	local wheels = { flWheel, frWheel, rlWheel, rrWheel }
	for _, wheel in wheels do
		for _, part in GeometryUtils.getInstanceParts(wheel) do
			part.CanCollide = false
			part.Massless = true
			part.Anchored = true
		end
	end

	for _, part in GeometryUtils.getInstanceParts(body) do
		part.Massless = true
		part.Anchored = true
	end

	local rootSize = GeometryUtils.getInstanceSize(root)
	local rootCFrame = GeometryUtils.getInstanceCFrame(root)
	root.PrimaryPart = GeometryUtils.getOrSetPrimaryPart(body)

	updateWheelPositions(
		flWheel, frWheel, rlWheel, rrWheel,
		rootCFrame.Position, rootSize.Y
	)

	local forward = getBoardForward(
		getWheelPrimaryPart(flWheel),
		getWheelPrimaryPart(frWheel),
		getWheelPrimaryPart(rlWheel),
		getWheelPrimaryPart(rrWheel)
	)
	local rotation = -math.acos(math.clamp(forward:Dot(Vector3.new(0, 0, -1)), -1, 1))
	root:PivotTo(root:GetPivot() * CFrame.Angles(0, rotation, 0))
end

function Heuristics.updateBoardRig(
	boardRig: Model,
	flWheel: Wheel,
	frWheel: Wheel,
	rlWheel: Wheel,
	rrWheel: Wheel,
	body: Model
): { wheelRadius: number, totalRigMass: number }
	local rigPrimary = boardRig.PrimaryPart
	assert(rigPrimary, "Board: rig template missing PrimaryPart")
	local bodyCenter = GeometryUtils.getBodyBounds(body)
	boardRig:TranslateBy(bodyCenter - rigPrimary.Position)

	local modelWheels = {
		getWheelPrimaryPart(flWheel),
		getWheelPrimaryPart(frWheel),
		getWheelPrimaryPart(rlWheel),
		getWheelPrimaryPart(rrWheel),
	}

	local newFrontWheelSize = math.max(getWheelDiameter(flWheel), getWheelDiameter(frWheel))
	local newRearWheelSize = math.max(getWheelDiameter(rlWheel), getWheelDiameter(rrWheel))
	local maxWheelSize = math.max(newFrontWheelSize, newRearWheelSize)
	local wheelCentroid = 0.25
		* (modelWheels[1].Position + modelWheels[2].Position + modelWheels[3].Position + modelWheels[4].Position)

	boardRig:TranslateBy(wheelCentroid + Vector3.new(0, maxWheelSize * 0.5, 0) - rigPrimary.Position)

	local wheelsFolder = boardRig:WaitForChild("Wheels")
	local frontWheelL = wheelsFolder:WaitForChild("WheelFL")
	local frontWheelR = wheelsFolder:WaitForChild("WheelFR")
	local rearWheelL = wheelsFolder:WaitForChild("WheelRL")
	local rearWheelR = wheelsFolder:WaitForChild("WheelRR")
	local chassis = boardRig:WaitForChild("Chassis")

	local frontWheelScale = newFrontWheelSize / getWheelPrimaryPart(frontWheelL).Size.X
	local rearWheelScale = newRearWheelSize / getWheelPrimaryPart(rearWheelL).Size.X
	rescalePartGroup({ frontWheelL.Wheel, frontWheelR.Wheel }, frontWheelScale)
	rescalePartGroup({ rearWheelL.Wheel, rearWheelR.Wheel }, rearWheelScale)

	local boardForward = getBoardForward(modelWheels[1], modelWheels[2], modelWheels[3], modelWheels[4])
	local boardLength, boardWidth = computeBoardDimensions(body, boardForward)
	local chassisScale = Vector3.new(boardWidth / chassis.Size.X, 1, boardLength / chassis.Size.Z)
	chassis.Size = Vector3.new(boardWidth, chassis.Size.Y, boardLength)
	scaleAttachmentPositions(chassis, chassisScale)

	for i, wheelName in RIG_WHEEL_NAMES do
		local wheelModel = wheelsFolder:WaitForChild(wheelName)
		wheelModel:TranslateBy(modelWheels[i].Position - getWheelPrimaryPart(wheelModel).Position)
	end

	for _, wheelName in RIG_WHEEL_NAMES do
		local chassisWheelAttachment = chassis:WaitForChild(wheelName)
		local wheelModel = wheelsFolder:WaitForChild(wheelName)
		local motorAttachment = wheelModel:WaitForChild("Wheel"):WaitForChild("MotorAttachment")
		chassisWheelAttachment.Position = chassis.CFrame:PointToObjectSpace(motorAttachment.WorldCFrame.Position)
	end

	local averageRadius = (newFrontWheelSize + newRearWheelSize) * 0.25

	local totalMass = chassis.Mass
	for _, wheelName in RIG_WHEEL_NAMES do
		local wheelPart = (wheelsFolder:WaitForChild(wheelName)):WaitForChild("Wheel")
		totalMass += wheelPart.Mass
	end

	return {
		wheelRadius = averageRadius,
		totalRigMass = totalMass,
	}
end

function Heuristics.attachGeometryToBoardRig(
	boardRig: Model,
	flWheel: Instance,
	frWheel: Instance,
	rlWheel: Instance,
	rrWheel: Instance,
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

	local rigChassis = boardRig:FindFirstChild("Chassis")
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

	local wheelsFolder = boardRig:WaitForChild("Wheels")
	local wheelBindings = {
		{ RigName = "WheelFL", Source = flWheel },
		{ RigName = "WheelFR", Source = frWheel },
		{ RigName = "WheelRL", Source = rlWheel },
		{ RigName = "WheelRR", Source = rrWheel },
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
	for _, rigPart in boardRig:GetDescendants() do
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

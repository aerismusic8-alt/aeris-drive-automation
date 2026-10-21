--[[
	File: Heuristics.luau
]]--

-- Root

local Heuristics = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local Constants = require(Firearm2.Common.Constants)
local RecenterModelPivot = require(FourD.Common.recenterModelPivot)

-- Constants

local VERBOSE_LOGGING = true
local MIN_AXIS_DOT = 1e-3
local BORE_DOMINANCE_RATIO = 1.5

-- Local Functions

local function vwarn(...: any)
	if not VERBOSE_LOGGING then return end
	warn(`[{script.Name}]`, ...)
end

local function getAnchorPart(instance: PVInstance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end

		for _, child in instance:GetDescendants() do
			if child:IsA("BasePart") then
				return child
			end
		end
	end

	return nil
end

local function getExtents(instance: PVInstance): Vector3
	if instance:IsA("BasePart") then
		return instance.Size
	end

	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	end

	return Vector3.one
end

local function pickBoreAxis(barrelCF: CFrame, barrelSize: Vector3, hint: Vector3): Vector3
	local axes = {
		{ Direction = barrelCF.RightVector, Extent = barrelSize.X },
		{ Direction = barrelCF.UpVector, Extent = barrelSize.Y },
		{ Direction = barrelCF.LookVector, Extent = barrelSize.Z },
	}

	table.sort(axes, function(first, second)
		return first.Extent > second.Extent
	end)

	local chosen = axes[1].Direction
	if axes[1].Extent < axes[2].Extent * BORE_DOMINANCE_RATIO then
		local bestScore = -math.huge
		for _, axis in axes do
			local score = axis.Extent * math.abs(axis.Direction:Dot(hint))
			if score > bestScore then
				bestScore = score
				chosen = axis.Direction
			end
		end
	end

	local hintDot = chosen:Dot(hint)
	if math.abs(hintDot) < MIN_AXIS_DOT then
		return if chosen:Dot(barrelCF.LookVector) >= 0 then chosen else -chosen
	end

	return if hintDot >= 0 then chosen else -chosen
end

local function pickBestUp(forward: Vector3, barrelCF: CFrame): Vector3
	local candidates = { barrelCF.RightVector, barrelCF.UpVector, barrelCF.LookVector }
	local bestUp = Vector3.yAxis
	local bestScore = -math.huge

	for _, axis in candidates do
		if math.abs(axis:Dot(forward)) > 0.99 then continue end

		local positiveScore = axis:Dot(Vector3.yAxis)
		if positiveScore > bestScore then
			bestScore = positiveScore
			bestUp = axis
		end

		local negativeScore = -positiveScore
		if negativeScore > bestScore then
			bestScore = negativeScore
			bestUp = -axis
		end
	end

	return bestUp
end

local function projectedHalfExtent(instance: PVInstance, axis: Vector3): number
	local size = getExtents(instance)
	local cf: CFrame
	if instance:IsA("BasePart") then
		cf = instance.CFrame
	elseif instance:IsA("Model") then
		cf = instance:GetPivot()
	else
		cf = CFrame.new()
	end

	local rx = math.abs(cf.RightVector:Dot(axis)) * size.X * 0.5
	local ry = math.abs(cf.UpVector:Dot(axis)) * size.Y * 0.5
	local rz = math.abs(cf.LookVector:Dot(axis)) * size.Z * 0.5
	return rx + ry + rz
end

-- Public Functions

local function compute(bodyModel: Model, schema: { Grip: PVInstance, Frame: PVInstance, Barrel: PVInstance, [string]: any }): {
	OrientedModel: Model,
	ShotOrigin: Attachment,
	LeftHandGrip: Attachment,
	RightHandGrip: Attachment,
	GripPosition: Vector3,
	ForwardDirection: Vector3,
}
	RecenterModelPivot(bodyModel)
	for _, value in schema do
		if typeof(value) == "Instance" and value:IsA("Model") then
			RecenterModelPivot(value)
		end
	end

	local barrelAnchor = getAnchorPart(schema.Barrel)
	assert(barrelAnchor ~= nil, "Sniper Heuristics: schema.Barrel must contain a BasePart")

	local frameAnchor = getAnchorPart(schema.Frame)
	assert(frameAnchor ~= nil, "Sniper Heuristics: schema.Frame must contain a BasePart")

	local gripPos = schema.Grip:GetPivot().Position
	local barrelCF = barrelAnchor.CFrame
	local barrelPos = barrelCF.Position

	local hint = barrelPos - gripPos
	local hintMagnitude = hint.Magnitude
	local desiredFwd: Vector3

	if hintMagnitude < MIN_AXIS_DOT then
		vwarn("Grip and Barrel are coincident; falling back to barrel LookVector")
		desiredFwd = barrelCF.LookVector
	else
		desiredFwd = hint / hintMagnitude
	end

	local barrelForward = pickBoreAxis(barrelCF, barrelAnchor.Size, desiredFwd)
	local barrelUp = pickBestUp(barrelForward, barrelCF)
	local barrelRight = barrelForward:Cross(barrelUp).Unit
	barrelUp = barrelRight:Cross(barrelForward).Unit

	local originalPivot = bodyModel:GetPivot()
	local targetPivot = CFrame.lookAt(originalPivot.Position, originalPivot.Position + barrelForward, barrelUp)
	bodyModel:PivotTo(targetPivot)

	local orientedGripPos = schema.Grip:GetPivot().Position
	local orientedBarrelCF = barrelAnchor.CFrame
	local orientedForward = -orientedBarrelCF.LookVector

	local hintAfter = orientedBarrelCF.Position - orientedGripPos
	if hintAfter.Magnitude > MIN_AXIS_DOT then
		orientedForward = pickBoreAxis(orientedBarrelCF, barrelAnchor.Size, hintAfter.Unit)
	end

	local barrelExtents = getExtents(schema.Barrel)
	local barrelHalfLength = math.max(barrelExtents.X, barrelExtents.Y, barrelExtents.Z) * 0.5
	local tipPos = orientedBarrelCF.Position + orientedForward * barrelHalfLength

	local shotOrigin = Instance.new("Attachment")
	shotOrigin.Name = "ShotOrigin"
	shotOrigin.Parent = barrelAnchor
	shotOrigin.WorldCFrame = CFrame.lookAt(tipPos, tipPos + orientedForward)

	local frameCenter: Vector3
	if schema.Frame:IsA("BasePart") then
		frameCenter = (schema.Frame :: BasePart).Position
	else
		frameCenter = (schema.Frame :: Model):GetPivot().Position
	end

	local frameHalfLength = projectedHalfExtent(schema.Frame, orientedForward)
	local frameFrontPos = frameCenter + orientedForward * frameHalfLength
	local midPos = (orientedGripPos + frameFrontPos) * 0.5
	local leftHandPos = Vector3.new(midPos.X, orientedGripPos.Y, midPos.Z)

	local gripAnchor = getAnchorPart(schema.Grip)
	assert(gripAnchor ~= nil, "Sniper Heuristics: schema.Grip must contain a BasePart")

	local leftHandGrip = Instance.new("Attachment")
	leftHandGrip.Name = Constants.LEFT_HAND_GRIP_NAME
	leftHandGrip.Parent = frameAnchor
	leftHandGrip.WorldCFrame = CFrame.new(leftHandPos)

	local rightHandGrip = Instance.new("Attachment")
	rightHandGrip.Name = Constants.RIGHT_HAND_GRIP_NAME
	rightHandGrip.Parent = gripAnchor
	rightHandGrip.WorldCFrame = CFrame.new(orientedGripPos)

	return {
		OrientedModel = bodyModel,
		ShotOrigin = shotOrigin,
		LeftHandGrip = leftHandGrip,
		RightHandGrip = rightHandGrip,
		GripPosition = orientedGripPos,
		ForwardDirection = orientedForward,
	}
end

Heuristics.compute = compute

-- Return

return Heuristics
ld
--[[
Pushable Behavior - Grab-and-push hand cart

Turns an assembled, welded cart model into something a player can grab by its
handle (via ProximityPrompt) and push by walking. In weld mode the cart is
rigidly welded to the grabbing character's HumanoidRootPart; in ground-align mode
it stays anchored and the pusher's client drives its pose. Either way the player's
hands are driven onto the handle via IK (client). On release the weld is removed
and the cart is left anchored in place.

The passed model MUST already be a single welded assembly with a PrimaryPart,
anchored while idle (the composing capability is responsible for that). handlePart
is the grab point; hand-grip Attachments are created on it if not already present.

Dependencies: FourD/Common (GeometryUtils)
]]

local FourD = script:FindFirstAncestor("FourD")
local Common = FourD.Common
local GeometryUtils = require(Common.GeometryUtils)
local ConstructionHelpers = require(Common.ConstructionHelpers)

local LEFT_GRIP_NAME = "LeftHandGrip"
local RIGHT_GRIP_NAME = "RightHandGrip"
local GROUND_CONTACT_NAME = "PushGroundContact"
local WHEEL_MOTOR_NAME = "PushWheelMotor"
local WHEEL_RADIUS_ATTRIBUTE = "PushWheelRadius"
local WHEEL_STEER_ATTRIBUTE = "PushWheelSteer"
local GRIP_SPREAD_FACTOR = 0.35
-- |Y| of an axis direction above which it counts as vertical and is not a candidate
-- to spread grips along. 0.7 is a little under 45 degrees.
local MAX_GRIP_AXIS_TILT = 0.7
local DEFAULT_HEIGHT_OFFSET = 0
local CONTACT_RAY_LIFT = 8
local CONTACT_RAY_DROP = 20
-- A wheel's resting ground is at or (slightly) below its bottom contact, never
-- well above it. Any surface more than this far above a contact is overhead
-- geometry -- a ceiling, the cart's own frame, or (at edit-time bind) the
-- transactional twin rig-model leaves overlapping the staged model -- and
-- must be skipped, not mistaken for ground. Without this a grab lifts the cart's
-- ground contacts to the frame top and the cart sinks by that gap.
local CONTACT_ABOVE_TOLERANCE = 0.5

export type PushableConfig = {
	FrontOffset: number?,
	HeightOffset: number?,
	ActionText: string?,
	ObjectText: string?,
	ForwardWorld: Vector3?,
	GroundContacts: { Vector3 }?,
	Wheels: { Instance }?,
	WalkSpeed: number?,
}

local Pushable = {}

---The handle's own longest horizontal axis, as a world direction plus its extent.
---With no ForwardWorld there is nothing else to derive "across the handle" from, and
---a bar is widest along its length by construction. Vertical axes are rejected
---however long they are, since two hands sit side by side rather than stacked; of
---three orthogonal axes at most one can be steeper than the limit, so a candidate
---always survives.
local function widestHorizontalAxis(cframe: CFrame, size: Vector3): (Vector3, number)
	local candidates = {
		{ direction = cframe.RightVector, extent = size.X },
		{ direction = cframe.UpVector, extent = size.Y },
		{ direction = cframe.LookVector, extent = size.Z },
	}

	local bestDirection, bestExtent = cframe.RightVector, -1
	for _, candidate in candidates do
		if math.abs(candidate.direction.Y) > MAX_GRIP_AXIS_TILT then continue end
		if candidate.extent > bestExtent then
			bestDirection = candidate.direction
			bestExtent = candidate.extent
		end
	end

	return bestDirection, bestExtent
end

---Spreads two grips across the handle when no ForwardWorld says which way that is.
---Measured against the whole handle -- the Model's bounding box when it is a Model --
---rather than handleAnchor on its own. A handlebar is usually a group, and the part
---that wins getOrSetPrimaryPart can be an end cap: sizing off that put both grips
---inside the cap instead of spanning the bar, and centred them on the cap too.
local function ensureGrips(handleAnchor: BasePart, handleCFrame: CFrame, handleSize: Vector3)
	local hasLeft = handleAnchor:FindFirstChild(LEFT_GRIP_NAME) ~= nil
	local hasRight = handleAnchor:FindFirstChild(RIGHT_GRIP_NAME) ~= nil
	if hasLeft and hasRight then return end

	local spreadAxis, extent = widestHorizontalAxis(handleCFrame, handleSize)
	local offset = spreadAxis * (extent * GRIP_SPREAD_FACTOR)
	local center = handleCFrame.Position

	if not hasLeft then
		local left = Instance.new("Attachment")
		left.Name = LEFT_GRIP_NAME
		left.Position = handleAnchor.CFrame:PointToObjectSpace(center - offset)
		left.Parent = handleAnchor
	end

	if not hasRight then
		local right = Instance.new("Attachment")
		right.Name = RIGHT_GRIP_NAME
		right.Position = handleAnchor.CFrame:PointToObjectSpace(center + offset)
		right.Parent = handleAnchor
	end
end

local function ensureGripsAt(handleAnchor: BasePart, leftPosition: Vector3, rightPosition: Vector3)
	local function place(gripName: string, position: Vector3)
		local existing = handleAnchor:FindFirstChild(gripName)
		local attachment = if existing and existing:IsA("Attachment") then existing else Instance.new("Attachment")
		attachment.Name = gripName
		attachment.Position = position
		attachment.Parent = handleAnchor
	end

	place(LEFT_GRIP_NAME, leftPosition)
	place(RIGHT_GRIP_NAME, rightPosition)
end

---Shifts the wheel-bottom points vertically so their centroid lands on the geometry
---the cart was authored over. Callers derive these points from wheel bounding
---boxes, which routinely include padding around the visible tread, so they can sit
---well above or below the actual surface; the follow loop later plants them on the
---ground, which is what makes a grab jump the cart by that error. One shared offset
---is used rather than planting each point on its own hit, so the authored footprint
---- which also defines the cart's forward/up basis - keeps its shape over uneven
---ground. Returns nil if any contact has nothing beneath it.
local function levelGroundContacts(assembledModel: Model, worldPoints: { Vector3 }): { Vector3 }?
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { assembledModel }
	rayParams.IgnoreWater = true
	-- Decals, puddles and other flat overlays are routinely non-collidable, and a
	-- cart cannot rest on something a character walks through.
	rayParams.RespectCanCollide = true

	-- Cast down from above each contact, but skip any surface that sits well above
	-- the contact: those are overhead geometry (a ceiling, the cart's own frame,
	-- or the transactional source twin that overlaps the staged model during bind),
	-- not the floor the wheels rest on. Re-cast from just under each skipped hit
	-- until the true ground below turns up.
	local function groundBelow(worldPoint: Vector3): RaycastResult?
		local rayTop = worldPoint.Y + CONTACT_RAY_LIFT
		local rayBottom = worldPoint.Y - CONTACT_RAY_DROP
		local originY = rayTop
		for _ = 1, 8 do
			if originY <= rayBottom then return nil end
			local result = workspace:Raycast(Vector3.new(worldPoint.X, originY, worldPoint.Z), Vector3.new(0, rayBottom - originY, 0), rayParams)
			if not result then return nil end
			if result.Position.Y <= worldPoint.Y + CONTACT_ABOVE_TOLERANCE then
				return result
			end
			-- Overhead hit: drop the origin just under it and keep going.
			originY = result.Position.Y - 1e-2
		end
		return nil
	end

	local totalError = 0
	for _, worldPoint in worldPoints do
		local result = groundBelow(worldPoint)
		if not result then return nil end
		totalError += result.Position.Y - worldPoint.Y
	end

	local bias = Vector3.new(0, totalError / #worldPoints, 0)
	local leveled = {}
	for _, worldPoint in worldPoints do
		table.insert(leveled, worldPoint + bias)
	end

	return leveled
end

---Rewrites the wheel-bottom marker attachments on the PrimaryPart.
---These all share one name and carry no corner label, and Roblox does not preserve
---child order across replication - a client reading them back gets an arbitrary
---permutation of what was written here. Consumers must therefore treat the contacts
---as an unordered set and recover any geometry they need from the positions.
local function ensureGroundContacts(primaryPart: BasePart, worldPoints: { Vector3 })
	for _, existing in primaryPart:GetChildren() do
		if existing:IsA("Attachment") and existing.Name == GROUND_CONTACT_NAME then
			existing:Destroy()
		end
	end

	for _, worldPoint in worldPoints do
		local attachment = Instance.new("Attachment")
		attachment.Name = GROUND_CONTACT_NAME
		attachment.Position = primaryPart.CFrame:PointToObjectSpace(worldPoint)
		attachment.Parent = primaryPart
	end
end

local function setupWheelMotors(assembledModel: Model, primaryPart: BasePart, wheels: { Instance }, axleWorld: Vector3, upWorld: Vector3, forwardWorld: Vector3, contactsCentroid: Vector3)
	if axleWorld.Magnitude < 1e-3 then return end
	local axleUnit = axleWorld.Unit
	local upUnit = if upWorld.Magnitude >= 1e-3 then upWorld.Unit else Vector3.yAxis
	local forwardUnit = if forwardWorld.Magnitude >= 1e-3 then forwardWorld.Unit else nil

	for _, wheel in wheels do
		if not (wheel:IsA("Model") or wheel:IsA("BasePart")) then continue end

		local hub = if wheel:IsA("BasePart") then wheel else GeometryUtils.getOrSetPrimaryPart(wheel)
		if not hub then continue end

		local wheelCFrame: CFrame, wheelSize: Vector3
		if wheel:IsA("Model") then
			wheelCFrame, wheelSize = wheel:GetBoundingBox()
		else
			wheelCFrame, wheelSize = wheel.CFrame, wheel.Size
		end

		local diameter = math.abs(upUnit:Dot(wheelCFrame.RightVector)) * wheelSize.X
			+ math.abs(upUnit:Dot(wheelCFrame.UpVector)) * wheelSize.Y
			+ math.abs(upUnit:Dot(wheelCFrame.LookVector)) * wheelSize.Z
		local radius = diameter * 0.5
		if radius < 1e-3 then continue end

		local wheelParts = GeometryUtils.getInstanceParts(wheel)
		local isWheelPart: { [BasePart]: boolean } = {}
		for _, part in wheelParts do
			isWheelPart[part] = true
		end

		for _, descendant in assembledModel:GetDescendants() do
			if descendant:IsA("WeldConstraint") and (isWheelPart[descendant.Part0] or isWheelPart[descendant.Part1]) then
				descendant:Destroy()
			end
		end

		for _, part in wheelParts do
			if part ~= hub then
				ConstructionHelpers.makeWeld(hub, part)
			end
		end

		local pivotWorld = CFrame.lookAlong(wheelCFrame.Position, axleUnit)
		local motor = Instance.new("Motor6D")
		motor.Name = WHEEL_MOTOR_NAME
		motor.Part0 = primaryPart
		motor.Part1 = hub
		motor.C0 = primaryPart.CFrame:ToObjectSpace(pivotWorld)
		motor.C1 = hub.CFrame:ToObjectSpace(pivotWorld)
		motor:SetAttribute(WHEEL_RADIUS_ATTRIBUTE, radius)
		if forwardUnit and (wheelCFrame.Position - contactsCentroid):Dot(forwardUnit) > 0 then
			motor:SetAttribute(WHEEL_STEER_ATTRIBUTE, true)
		end

		motor.Parent = primaryPart
	end
end

function Pushable.setup(assembledModel: Model, handlePart: Instance, config: PushableConfig?)
	local options = config or {}

	local handleAnchor = if handlePart:IsA("BasePart")
		then handlePart
		else GeometryUtils.getOrSetPrimaryPart(handlePart)

	if not handleAnchor then
		warn("[Pushable] setup: no BasePart resolved for handle on " .. assembledModel:GetFullName())
		return
	end

	if options.FrontOffset then
		assembledModel:SetAttribute("PushFrontOffset", options.FrontOffset)
	end
	assembledModel:SetAttribute("PushHeightOffset", options.HeightOffset or DEFAULT_HEIGHT_OFFSET)
	if options.WalkSpeed then
		assembledModel:SetAttribute("PushWalkSpeed", options.WalkSpeed)
	end
	assembledModel:SetAttribute("pushActive", false)

	-- The handle as a whole, which is what the grips and the stand point should be
	-- measured against. handleAnchor is only ever one part of it.
	local handleCFrame, handleSize = handleAnchor.CFrame, handleAnchor.Size
	if handlePart:IsA("Model") then
		handleCFrame, handleSize = handlePart:GetBoundingBox()
	end
	local handleCenter = handleCFrame.Position

	local forwardWorld = options.ForwardWorld
	local forwardFlat = if forwardWorld then Vector3.new(forwardWorld.X, 0, forwardWorld.Z) else nil
	if forwardFlat and forwardFlat.Magnitude >= 1e-3 then
		local forwardUnit = forwardFlat.Unit

		local rightWorld = forwardUnit:Cross(Vector3.yAxis)
		rightWorld = if rightWorld.Magnitude >= 1e-3 then rightWorld.Unit else Vector3.xAxis

		local fullSpan = math.abs(rightWorld:Dot(handleCFrame.RightVector)) * handleSize.X
			+ math.abs(rightWorld:Dot(handleCFrame.UpVector)) * handleSize.Y
			+ math.abs(rightWorld:Dot(handleCFrame.LookVector)) * handleSize.Z
		local offset = fullSpan * GRIP_SPREAD_FACTOR

		ensureGripsAt(handleAnchor,
			handleAnchor.CFrame:PointToObjectSpace(handleCenter - rightWorld * offset),
			handleAnchor.CFrame:PointToObjectSpace(handleCenter + rightWorld * offset))

		assembledModel:SetAttribute("PushForwardLocal", handleAnchor.CFrame:VectorToObjectSpace(forwardUnit))
	else
		ensureGrips(handleAnchor, handleCFrame, handleSize)
	end

	-- Set on both paths. The server places the pusher relative to this point and
	-- measures the grab anchor from it, and the middle of the handle is right in
	-- either case -- where handleAnchor's own origin is an end cap or some other
	-- off-centre piece of the group, it is not.
	assembledModel:SetAttribute("PushGripLocal", handleAnchor.CFrame:PointToObjectSpace(handleCenter))

	local groundContacts = options.GroundContacts
	local primaryPart = assembledModel.PrimaryPart
	if groundContacts and #groundContacts == 4 and primaryPart then
		groundContacts = levelGroundContacts(assembledModel, groundContacts) or groundContacts
		ensureGroundContacts(primaryPart, groundContacts)

		-- Derive the cart's forward/up from wheel-contact POSITIONS (robust against
		-- corrupted part pivots) and store them relative to the PrimaryPart so the
		-- client follow never has to trust the chassis part's own orientation.
		local frontLeft, frontRight, rearLeft, rearRight =
			groundContacts[1], groundContacts[2], groundContacts[3], groundContacts[4]
		local forwardRaw = (frontLeft + frontRight) - (rearLeft + rearRight)
		local rightRaw = (frontRight + rearRight) - (frontLeft + rearLeft)
		local upWorld = rightRaw:Cross(forwardRaw)
		if upWorld.Y < 0 then
			upWorld = -upWorld
		end

		if forwardRaw.Magnitude >= 1e-3 and upWorld.Magnitude >= 1e-3 then
			assembledModel:SetAttribute("PushGroundForwardLocal", primaryPart.CFrame:VectorToObjectSpace(forwardRaw.Unit))
			assembledModel:SetAttribute("PushGroundUpLocal", primaryPart.CFrame:VectorToObjectSpace(upWorld.Unit))
			assembledModel:SetAttribute("PushGroundAlign", true)
		end

		if options.Wheels then
			local contactsCentroid = (frontLeft + frontRight + rearLeft + rearRight) / 4
			setupWheelMotors(assembledModel, primaryPart, options.Wheels, rightRaw, upWorld, forwardRaw, contactsCentroid)
		end
	end

	local pushedBy = Instance.new("ObjectValue")
	pushedBy.Name = "PushedBy"
	-- Runtime ownership slot: the server sets this to the pushing player at Play.
	-- Marked so the edit-time inspect gate does not read its empty value as a
	-- broken serialized reference.
	pushedBy:SetAttribute("FourDRuntimeSlot", true)
	pushedBy.Parent = assembledModel

	local releaseEvent = Instance.new("RemoteEvent")
	releaseEvent.Name = "PushReleaseEvent"
	releaseEvent.Parent = assembledModel

	-- Ground-align pose stream: the pusher's client owns placement, the server
	-- copies it onto the still-anchored cart so every other client sees it move.
	local poseEvent = Instance.new("UnreliableRemoteEvent")
	poseEvent.Name = "PushPoseEvent"
	poseEvent.Parent = assembledModel

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PushPrompt"
	prompt.ActionText = options.ActionText or "Push"
	prompt.ObjectText = options.ObjectText or "Cart"
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0.3
	prompt.RequiresLineOfSight = false
	prompt.Parent = handleAnchor

	local serverScript = script:FindFirstChild("PushableServer")
	if serverScript then
		local serverClone = serverScript:Clone()
		serverClone.Enabled = true
		serverClone.Parent = assembledModel
	end

	local inputScript = script:FindFirstChild("PushableInput")
	if inputScript then
		local inputClone = inputScript:Clone()
		-- PushableInput is a ClientComponent ModuleScript at edit time (no Enabled);
		-- only a real BaseScript needs enabling. The runtime requires the module.
		if inputClone:IsA("BaseScript") then
			inputClone.Enabled = true
		end
		inputClone.Parent = assembledModel
	end
end

return Pushable

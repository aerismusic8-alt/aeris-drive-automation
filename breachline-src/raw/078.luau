-- GENERATED WRAPPER around upstream PushableInput.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: PushableInput.server.luau
	RunContext: Client; see PushableInput.meta.json (Disabled template)

	Runs on the pushing player's client. While the local player is the cart's
	pusher, it binds the Release action through the centralized Keybinds set
	"Pushable" and drives the local character's hands onto the handle grips via
	the shared IKHands helper.

	When the cart exposes PushGroundContact attachments + the PushGroundForwardLocal
	/PushGroundUpLocal basis (ground-align mode), it also drives a per-frame CFrame
	follow: the cart is held in front of the player and raycasts down from each
	wheel-bottom contact so the wheels rest on the ground geometry, pitching/rolling
	to match slopes. The slope comes from a least-squares plane through whichever
	contacts found ground, which treats them as the unordered set they replicate as.
	The cart stays anchored throughout; each pose is streamed to the server over
	PushPoseEvent so other clients see the same movement.

	Horizontal placement is deterministic every frame from the player's yaw frame +
	a fixed anchor offset the server captured at grab (PushGroundAnchorLocal,
	invariant to both the grab-time replication race and the pitch the cart was
	parked at), plus the wheel-derived basis (immune to corrupted chassis pivots). The yaw frame's origin trails the character on a slack leash so
	the root motion baked into the idle animation does not reach the cart. Height is
	taken from the ground under the wheels rather than from the character, plus a
	lift measured against the ground under the pusher so the cart rises with a jump.

	Everything is torn down when the local player stops pushing or the cart is
	destroyed.
]]

if not script.Parent:IsA("Model") then return end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if RunService:IsServer() then return end

local Keybinds = require(ReplicatedStorage.FourD.Common.Keybinds)
local IKHands = require(ReplicatedStorage.FourD.Common.IKHands)

local LEFT_GRIP_NAME = "LeftHandGrip"
local RIGHT_GRIP_NAME = "RightHandGrip"
local GROUND_CONTACT_NAME = "PushGroundContact"
local WHEEL_MOTOR_NAME = "PushWheelMotor"
local WHEEL_RADIUS_ATTRIBUTE = "PushWheelRadius"
local WHEEL_STEER_ATTRIBUTE = "PushWheelSteer"
local KEYBIND_SET_ID = "Pushable"
-- Unique per cart, so this cart's release can only ever unbind its own action. Not
-- GetDebugId, which is not available to ordinary game scripts. GenerateGUID is local
-- and needs no HTTP.
local ACTION_NAME_SUFFIX = "_" .. HttpService:GenerateGUID(false)

local RAY_START_HEIGHT = 8
local RAY_DROP_LENGTH = 20
local R6_HIP_TO_ROOT = 3
local LIFT_DEADZONE = 0.5
local FOLLOW_SLACK = 0.25
local MAX_INCLINE_DEG = 35
local ORIENT_SMOOTH_RATE = 10
local MAX_STEER_DEG = 45
local STEER_SMOOTH_RATE = 8
-- Horizontal shift below which the grip correction is not worth a second set of
-- ground rays. Zero on level ground, where the correction is a no-op.
local CENTROID_CORRECTION_EPSILON = 0.05
local DEFAULT_VERTICAL_DROP = 2.5
local DEFAULT_FRONT_CLEARANCE = 2
local POSE_SEND_INTERVAL = 1 / 30
local EPSILON = 1e-4

local model = script.Parent
local player = Players.LocalPlayer

local releaseEvent = model:FindFirstChild("PushReleaseEvent")
local poseEvent = model:FindFirstChild("PushPoseEvent")
local pushedBy = model:FindFirstChild("PushedBy")

if not releaseEvent or not releaseEvent:IsA("RemoteEvent") then return end
if not poseEvent or not poseEvent:IsA("UnreliableRemoteEvent") then return end
if not pushedBy or not pushedBy:IsA("ObjectValue") then return end

local prompt = model:FindFirstChild("PushPrompt", true)
local handleAnchor = if prompt then prompt.Parent else nil

local bindHandle: Keybinds.BindActionsHandle? = nil
local ikHandle: IKHands.IKHandsHandle? = nil
local followConnection: RBXScriptConnection? = nil

local function findGrip(name: string): Attachment?
	if not handleAnchor then return nil end
	local grip = handleAnchor:FindFirstChild(name)
	if grip and grip:IsA("Attachment") then return grip end
	return nil
end

local function collectContactLocals(primaryPart: BasePart): { Vector3 }
	local locals = {}
	for _, child in primaryPart:GetChildren() do
		if child:IsA("Attachment") and child.Name == GROUND_CONTACT_NAME then
			table.insert(locals, child.Position)
		end
	end
	return locals
end

---Least-squares plane through the ground hits, returned as an upward normal.
---Fits y = ax + bz + c over points centred on their own mean, so the result depends
---only on the set of points, never on the order they arrive in. That matters here:
---the contacts are four identically named attachments, and Roblox does not preserve
---child order across replication, so anything identifying a corner by array index
---reads a different wheel on the client than the server wrote. Returns nil when the
---footprint is degenerate (fewer than three hits, or contacts collinear in XZ).
local function fitGroundNormal(points: { Vector3 }, count: number): Vector3?
	if count < 3 then return nil end

	local centroid = Vector3.zero
	for _, point in points do
		centroid += point
	end
	centroid /= count

	local sumXX, sumXZ, sumZZ, sumXY, sumZY = 0, 0, 0, 0, 0
	for _, point in points do
		local dx, dy, dz = point.X - centroid.X, point.Y - centroid.Y, point.Z - centroid.Z
		sumXX += dx * dx
		sumXZ += dx * dz
		sumZZ += dz * dz
		sumXY += dx * dy
		sumZY += dz * dy
	end

	local determinant = sumXX * sumZZ - sumXZ * sumXZ
	if math.abs(determinant) < EPSILON then return nil end

	local slopeX = (sumZZ * sumXY - sumXZ * sumZY) / determinant
	local slopeZ = (sumXX * sumZY - sumXZ * sumXY) / determinant
	return Vector3.new(-slopeX, 1, -slopeZ).Unit
end

local function flattenToYaw(cframe: CFrame, position: Vector3): CFrame
	local look = cframe.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < EPSILON then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAlong(position, flat.Unit)
end

local function getHumanoidRootPart(): BasePart?
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if hrp and hrp:IsA("BasePart") then return hrp end
	return nil
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function stopFollow()
	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
end

local function startFollow()
	if followConnection then return end

	local primaryPart = model.PrimaryPart
	local hrp = getHumanoidRootPart()
	if not primaryPart or not hrp then return end

	local forwardLocal = model:GetAttribute("PushGroundForwardLocal")
	local upLocal = model:GetAttribute("PushGroundUpLocal")
	if typeof(forwardLocal) ~= "Vector3" or typeof(upLocal) ~= "Vector3" then return end

	local contactLocals = collectContactLocals(primaryPart)
	if #contactLocals < 3 then return end

	local contactCount = #contactLocals
	local localCentroid = Vector3.zero
	for _, localPoint in contactLocals do
		localCentroid += localPoint
	end
	localCentroid /= contactCount

	-- Fixed rotation mapping a canonical (look=forward, up=up) frame into the
	-- PrimaryPart's local frame; its inverse turns a desired world orientation into
	-- the CFrame we assign to the PrimaryPart.
	local localBasisInverse = CFrame.lookAlong(Vector3.zero, forwardLocal, upLocal):Inverse()

	-- Wheel-centroid offset in the player's yaw frame. Prefer the server-captured
	-- value (authoritative, immune to the grab-time replication race), else derive a
	-- reasonable offset from the cart's own footprint.
	local anchorInPlayerFrame = model:GetAttribute("PushGroundAnchorLocal")
	if typeof(anchorInPlayerFrame) ~= "Vector3" then
		local forwardUnit = if forwardLocal.Magnitude >= EPSILON then forwardLocal.Unit else Vector3.new(0, 0, -1)
		local rearDepth = 0
		for _, localPoint in contactLocals do
			local proj = (localPoint - localCentroid):Dot(forwardUnit)
			if -proj > rearDepth then
				rearDepth = -proj
			end
		end
		anchorInPlayerFrame = Vector3.new(0, -DEFAULT_VERTICAL_DROP, -(rearDepth + DEFAULT_FRONT_CLEARANCE))
	end

	-- Midpoint of the hand grips in the PrimaryPart's frame, and where the wheel
	-- centroid sits from there with the cart level. The cart is rigid, so both are
	-- fixed for the whole push. The anchor is expressed from the wheel centroid; these
	-- re-express it from the grips, which is what actually has to stay within reach.
	local gripLocal: Vector3? = nil
	local gripAnchorInPlayerFrame: Vector3? = nil

	local leftGrip, rightGrip = findGrip(LEFT_GRIP_NAME), findGrip(RIGHT_GRIP_NAME)
	if leftGrip and rightGrip then
		gripLocal = primaryPart.CFrame:PointToObjectSpace((leftGrip.WorldPosition + rightGrip.WorldPosition) / 2)
		local levelBasis = CFrame.lookAlong(Vector3.zero, forwardLocal, upLocal)
		local gripToCentroidLevel = levelBasis:VectorToObjectSpace(localCentroid - (gripLocal :: Vector3))
		gripAnchorInPlayerFrame = anchorInPlayerFrame - gripToCentroidLevel
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	-- Only collidable geometry can carry the cart. Non-collidable decals and
	-- overlays sit above the real floor, and resting the wheels on one leaves the
	-- cart hovering over ground the pusher is standing below.
	rayParams.RespectCanCollide = true

	---Drops a vertical ray from each wheel contact for a candidate placement, given
	---where the wheel centroid would sit and how the cart would be rotated. Returns the
	---mean ground height under the contacts that found floor and a plane fitted through
	---them, or nil when none did.
	local function sampleGround(centroid: Vector3, rotation: CFrame): (number?, Vector3?)
		local candidateCF = CFrame.new(centroid - rotation:VectorToWorldSpace(localCentroid)) * rotation

		local hits: { Vector3 } = {}
		local hitCount = 0
		for index, localPoint in contactLocals do
			local footWorld = candidateCF:PointToWorldSpace(localPoint)
			local rayOrigin = footWorld + Vector3.new(0, RAY_START_HEIGHT, 0)
			local result = workspace:Raycast(rayOrigin, Vector3.new(0, -(RAY_START_HEIGHT + RAY_DROP_LENGTH), 0), rayParams)
			if result then
				hits[index] = result.Position
				hitCount += 1
			end
		end

		if hitCount == 0 then
			return nil, nil
		end

		local sumY = 0
		for _, hitPoint in hits do
			sumY += hitPoint.Y
		end

		return sumY / hitCount, fitGroundNormal(hits, hitCount)
	end

	-- Author escape hatch for a cart whose wheel contacts do not describe its true
	-- resting height (a hollow or padded wheel mesh, say).
	local heightOffsetAttribute = model:GetAttribute("PushHeightOffset")
	local heightOffset = if typeof(heightOffsetAttribute) == "number" then heightOffsetAttribute else 0

	-- Horizontal origin the cart is placed from, dragged behind the character rather
	-- than pinned to it. The R15 idle animation carries root motion, so a standing
	-- character's HumanoidRootPart travels about 0.17 studs on a slow cycle; pinned
	-- 1:1 the cart reproduces that as a drift several studs away. Slack wider than
	-- the wobble absorbs it completely, while walking only ever trails by FOLLOW_SLACK
	-- -- there is no lag to accumulate and no snap when the character starts moving.
	local followOrigin: Vector3? = nil

	local maxInclineRad = math.rad(MAX_INCLINE_DEG)
	local currentUp = Vector3.yAxis
	local maxSteerRad = math.rad(MAX_STEER_DEG)
	local currentSteer = 0
	local lastPoseSent = 0

	local wheelMotors: { { Motor: Motor6D, Radius: number, Angle: number, Steer: boolean } } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == WHEEL_MOTOR_NAME then
			local radius = descendant:GetAttribute(WHEEL_RADIUS_ATTRIBUTE)
			if typeof(radius) == "number" and radius > EPSILON then
				table.insert(wheelMotors, {
					Motor = descendant,
					Radius = radius,
					Angle = 0,
					Steer = descendant:GetAttribute(WHEEL_STEER_ATTRIBUTE) == true,
				})
			end
		end
	end
	local lastSpinPosition = primaryPart.Position

	-- PreAnimation, not PreRender. Both run once per frame, but the order is
	-- PreAnimation -> animation + IK solve -> physics -> PreRender -> render, and
	-- the hand IK targets are attachments on this cart. Posing the cart in PreRender
	-- means every frame's IK solved against where the handle was last frame, so the
	-- hands chase the handle and the arms jitter -- measured at 0.39 studs of hand
	-- movement in a single frame while walking, against 0.004 standing still, where
	-- the pose is recomputed to the same place and there is nothing to chase.
	followConnection = RunService.PreAnimation:Connect(function(deltaTime: number)
		local root = getHumanoidRootPart()
		if not primaryPart.Parent or not root then return end

		local humanoid = getHumanoid()
		rayParams.FilterDescendantsInstances = { model, root.Parent }

		local rootPosition = root.Position
		-- Deliberately the character's current position, not a predicted one. Physics
		-- runs after this loop and carries the character about 0.2 studs further, so
		-- the handle does trail the hands by one step; extrapolating by
		-- AssemblyLinearVelocity * deltaTime to cancel it was measured and made things
		-- worse (hand jitter 0.27 -> 0.32 studs), because a walking humanoid's velocity
		-- carries the controller's own stepping oscillation and that noise exceeds the
		-- step being corrected.
		local leashTarget = Vector3.new(rootPosition.X, 0, rootPosition.Z)
		local origin = followOrigin or leashTarget
		local slackDelta = leashTarget - origin
		local slackDistance = slackDelta.Magnitude
		if slackDistance > FOLLOW_SLACK then
			origin += slackDelta.Unit * (slackDistance - FOLLOW_SLACK)
		end
		followOrigin = origin

		-- Leash the origin, not the finished pose: the ground rays are cast from the
		-- placement this frame resolves to, so filtering afterwards would sample the
		-- floor somewhere the cart is not.
		local playerFrame = flattenToYaw(root.CFrame, Vector3.new(origin.X, rootPosition.Y, origin.Z))
		local flatLook = playerFrame.LookVector
		local provisionalCentroid = playerFrame:PointToWorldSpace(anchorInPlayerFrame)

		local provisionalRotation = CFrame.lookAlong(Vector3.zero, flatLook, Vector3.yAxis) * localBasisInverse

		local targetUp = Vector3.yAxis
		local groundCentroid: Vector3? = nil

		local groundY, groundNormal = sampleGround(provisionalCentroid, provisionalRotation)
		if groundY then
			-- Horizontal placement stays with the pusher's yaw frame; only the height
			-- comes from the ground. When every contact hits, this Y is the same
			-- centroid a mean of the hits would give, since the rays are vertical.
			groundCentroid = Vector3.new(provisionalCentroid.X, groundY, provisionalCentroid.Z)
			targetUp = groundNormal or Vector3.yAxis
		end

		-- Resting height comes from the ground under the cart's own wheels, never
		-- from the pusher's Y, and a jump is added back as a lift measured against
		-- the ground under the pusher -- so the cart leaves the floor with them and
		-- settles again on landing. Taking the height from the character directly
		-- would let any server/client disagreement about where the pusher stands
		-- accumulate into the cart's resting height, one grab at a time.
		local lift = 0
		if groundCentroid and humanoid then
			local underPlayer = workspace:Raycast(
				root.Position + Vector3.new(0, RAY_START_HEIGHT, 0),
				Vector3.new(0, -(RAY_START_HEIGHT + RAY_DROP_LENGTH), 0),
				rayParams
			)
			if underPlayer then
				local hipToRoot = if humanoid.RigType == Enum.HumanoidRigType.R6
					then R6_HIP_TO_ROOT
					else humanoid.HipHeight + root.Size.Y * 0.5
				local raised = root.Position.Y - (underPlayer.Position.Y + hipToRoot)
				lift = if raised > LIFT_DEADZONE then raised else 0
			end
		end

		if not groundCentroid then
			groundCentroid = provisionalCentroid
			targetUp = Vector3.yAxis
		end

		local incline = math.acos(math.clamp(targetUp:Dot(Vector3.yAxis), -1, 1))
		if incline > maxInclineRad and incline > EPSILON then
			local clamped = Vector3.yAxis:Lerp(targetUp, maxInclineRad / incline)
			targetUp = if clamped.Magnitude >= EPSILON then clamped.Unit else Vector3.yAxis
		end

		local blended = currentUp:Lerp(targetUp, math.min(deltaTime * ORIENT_SMOOTH_RATE, 1))
		currentUp = if blended.Magnitude >= EPSILON then blended.Unit else Vector3.yAxis

		local forward = flatLook - currentUp * flatLook:Dot(currentUp)
		if forward.Magnitude < EPSILON then
			forward = flatLook
		end
		forward = forward.Unit

		local rotation = CFrame.lookAlong(Vector3.zero, forward, currentUp) * localBasisInverse

		-- Hold the grips a fixed distance from the pusher rather than the wheel
		-- centroid. The grips stand well above the centroid -- 4.57 studs on the
		-- shopping cart -- so tilting the cart swings them horizontally by roughly that
		-- height times sin(pitch): 1.34 studs at 17 degrees, 2.35 at 31. Anchoring the
		-- centroid therefore drew the handle in toward the pusher going uphill and let
		-- it run away downhill, changing how far they had to reach with the slope.
		-- Solving for the centroid that puts the grips where they belong is exact, and
		-- collapses to the old placement whenever the cart is level.
		local placement = groundCentroid
		if gripAnchorInPlayerFrame and gripLocal then
			local centroidFromGrip = rotation:VectorToWorldSpace(localCentroid - (gripLocal :: Vector3))
			local desiredGrip = playerFrame:PointToWorldSpace(gripAnchorInPlayerFrame :: Vector3)
			local correctedX = desiredGrip.X + centroidFromGrip.X
			local correctedZ = desiredGrip.Z + centroidFromGrip.Z

			local shift = Vector3.new(correctedX - placement.X, 0, correctedZ - placement.Z)
			if shift.Magnitude > CENTROID_CORRECTION_EPSILON then
				-- The height above came from rays under the uncorrected footprint, so drop
				-- them again now the wheels have moved. Skipped on the level, where the
				-- correction is zero and this would only repeat the first pass.
				local correctedY = sampleGround(Vector3.new(correctedX, placement.Y, correctedZ), rotation)
				placement = Vector3.new(correctedX, correctedY or placement.Y, correctedZ)
			end
		end

		local position = placement
			+ Vector3.new(0, heightOffset + lift, 0)
			- rotation:VectorToWorldSpace(localCentroid)
		primaryPart.CFrame = CFrame.new(position) * rotation
		if not primaryPart.Anchored then
			primaryPart.AssemblyLinearVelocity = Vector3.zero
			primaryPart.AssemblyAngularVelocity = Vector3.zero
		end

		local now = os.clock()
		if now - lastPoseSent >= POSE_SEND_INTERVAL then
			lastPoseSent = now
			poseEvent:FireServer(primaryPart.CFrame)
		end

		local steerTarget = 0
		if humanoid then
			local moveDirection = humanoid.MoveDirection
			local flatMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
			if flatMove.Magnitude >= EPSILON then
				local moveUnit = flatMove.Unit
				steerTarget = math.clamp(
					math.atan2(flatLook:Cross(moveUnit).Y, flatLook:Dot(moveUnit)),
					-maxSteerRad,
					maxSteerRad
				)
			end
		end
		currentSteer += (steerTarget - currentSteer) * math.min(deltaTime * STEER_SMOOTH_RATE, 1)

		if #wheelMotors > 0 then
			local newPosition = primaryPart.Position
			local travel = (newPosition - lastSpinPosition):Dot(forward)
			lastSpinPosition = newPosition
			for _, entry in wheelMotors do
				entry.Angle += travel / entry.Radius
				local spin = CFrame.fromAxisAngle(Vector3.zAxis, entry.Angle)
				entry.Motor.Transform = if entry.Steer
					then CFrame.fromAxisAngle(Vector3.yAxis, currentSteer) * spin
					else spin
			end
		end
	end)
end

local function onRelease(state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		local primaryPart = model.PrimaryPart
		releaseEvent:FireServer(if followConnection and primaryPart then primaryPart.CFrame else nil)
	end

	return Enum.ContextActionResult.Sink
end

local function teardown()
	stopFollow()

	if bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
	end

	if ikHandle then
		ikHandle:Destroy()
		ikHandle = nil
	end
end

local function isLocalPusher(): boolean
	return pushedBy.Value == player
end

local function refresh()
	if not isLocalPusher() then
		teardown()
		return
	end

	if not bindHandle then
		-- Suffix the action name per cart. The server allows only one pushable per
		-- player, but the release of the outgoing cart and the bind of the incoming
		-- one are both reactions to replicated state and can arrive in either order.
		-- On a shared action name the outgoing teardown's UnbindAction can therefore
		-- land after the new bind and remove it, leaving a cart that cannot be let go.
		bindHandle = Keybinds.bindActions(KEYBIND_SET_ID, { Release = onRelease }, model, {
			ActionNameSuffix = ACTION_NAME_SUFFIX,
		})
	end

	if not ikHandle then
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			ikHandle = IKHands.attach(humanoid, {
				Left = findGrip(LEFT_GRIP_NAME),
				Right = findGrip(RIGHT_GRIP_NAME),
			})
		end
	end

	if model:GetAttribute("PushGroundAlign") == true then
		startFollow()
	end
end

pushedBy:GetPropertyChangedSignal("Value"):Connect(refresh)

model.Destroying:Connect(teardown)

refresh()

end

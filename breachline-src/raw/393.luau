--[[
	File: PushableServer.server.luau
	RunContext: Legacy (server); see PushableServer.meta.json (Disabled template)

	Handles the server side of the Pushable grab: on ProximityPrompt trigger,
	teleports the grabbing character to a stand-point behind the cart's handle
	(the cart itself does not move).

	Two follow modes:
	- Default (weld): rigidly welds the cart to the pusher's HumanoidRootPart and
	  hands network ownership to the pusher.
	- Ground-align (PushGroundAlign attribute): the cart stays anchored for the
	  whole push. The pusher's client drives a terrain-aligned CFrame follow and
	  streams the pose over PushPoseEvent; this script copies each accepted pose
	  onto the anchored cart so other clients see it move. Nothing is simulated, so
	  the cart cannot fall or drift when ownership changes hands.

	On the release RemoteEvent (or the pusher leaving / dying), removes any weld and
	leaves the cart anchored in place.
]]

if not script.Parent:IsA("Model") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PushRegistry = require(ReplicatedStorage.FourD.Behaviors.Pushable.PushRegistry)

local DEFAULT_FRONT_OFFSET = 1.5
local RAY_START_HEIGHT = 8
local RAY_DROP_LENGTH = 20
local R6_HIP_TO_ROOT = 3
local GRAB_WELD_NAME = "Pushable_GrabWeld"
local GROUND_CONTACT_NAME = "PushGroundContact"
local MIN_LOOK_MAGNITUDE = 1e-3
-- Fraction of the arm's true reach to hold the grip at. Short of 1 so the elbow
-- keeps some bend: an arm solved at full stretch sits on the shoulder-to-grip axis,
-- where which way the elbow should bend is ill-conditioned and the IK solver flips it
-- between frames.
local ARM_REACH_EXTENSION = 0.85
-- Only for rigs missing the arm Motor6Ds. Part sizes include the overlap at each
-- joint, so they run about a quarter longer than the limbs they describe.
local ARM_REACH_PART_SIZE_FACTOR = 0.6
local MAX_POSE_DISTANCE = 60

local model = script.Parent

local prompt = model:FindFirstChild("PushPrompt", true)
local releaseEvent = model:FindFirstChild("PushReleaseEvent")
local poseEvent = model:FindFirstChild("PushPoseEvent")
local pushedBy = model:FindFirstChild("PushedBy")

if not prompt or not prompt:IsA("ProximityPrompt") then return end
if not releaseEvent or not releaseEvent:IsA("RemoteEvent") then return end
if not poseEvent or not poseEvent:IsA("UnreliableRemoteEvent") then return end
if not pushedBy or not pushedBy:IsA("ObjectValue") then return end

local handleAnchor = prompt.Parent
local primaryPart = model.PrimaryPart

if not handleAnchor or not handleAnchor:IsA("BasePart") then return end
if not primaryPart then return end

local groundAlign = model:GetAttribute("PushGroundAlign") == true

local grabWeld: WeldConstraint? = nil
local activePlayer: Player? = nil
local activeHumanoid: Humanoid? = nil
local originalWalkSpeed: number? = nil
local releaseWatchers: { RBXScriptConnection } = {}

local function clearReleaseWatchers()
	for _, connection in releaseWatchers do
		connection:Disconnect()
	end
	table.clear(releaseWatchers)
end

local function release()
	local releasingPlayer = activePlayer
	if not releasingPlayer then return end

	PushRegistry.clear(releasingPlayer, model)

	clearReleaseWatchers()

	if grabWeld then
		grabWeld:Destroy()
		grabWeld = nil
	end

	if not groundAlign then
		pcall(function()
			primaryPart:SetNetworkOwner(nil)
		end)
	end
	primaryPart.Anchored = true

	if activeHumanoid and originalWalkSpeed then
		activeHumanoid.WalkSpeed = originalWalkSpeed
	end
	activeHumanoid = nil
	originalWalkSpeed = nil

	pushedBy.Value = nil
	model:SetAttribute("pushActive", false)
	prompt.Enabled = true
	activePlayer = nil
end

---Copies a pose sent by the pusher onto the anchored cart. Rejects anything that is
---not a finite CFrame near that player's character, so a stale or tampered packet
---cannot teleport the cart across the map.
local function applyPose(player: Player, pose: any)
	if not groundAlign or player ~= activePlayer then return end
	if typeof(pose) ~= "CFrame" then return end

	local position = pose.Position
	if position ~= position then return end

	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not hrp or not hrp:IsA("BasePart") then return end
	if (position - hrp.Position).Magnitude > MAX_POSE_DISTANCE then return end

	primaryPart.CFrame = pose
end

---Horizontal distance to hold the handle at, derived from the arm the character
---actually has so the pusher ends up near full stretch on any rig.
---
---Measured between joint pivots, not from part sizes. The R15 arm parts overlap at
---the joints, so summing their Size.Y overstates the real limb by about a quarter
---(2.651 against 2.091 studs on a default rig) -- which is what the old 0.6 factor was
---absorbing, and it left the arms around three-quarters extended. Pivot distances are
---exact and follow resized avatars, which part sizes only do approximately.
---
---This is a horizontal offset from the root whereas reach is from the shoulder, and
---the grips are spread sideways, so the extension actually reached comes out slightly
---above ARM_REACH_EXTENSION.
local function computeArmReach(character: Model): number?
	local upperArm = character:FindFirstChild("RightUpperArm")
	local lowerArm = character:FindFirstChild("RightLowerArm")
	local hand = character:FindFirstChild("RightHand")

	if upperArm and upperArm:IsA("BasePart")
		and lowerArm and lowerArm:IsA("BasePart")
		and hand and hand:IsA("BasePart") then
		local shoulder = upperArm:FindFirstChild("RightShoulder")
		local elbow = lowerArm:FindFirstChild("RightElbow")
		local wrist = hand:FindFirstChild("RightWrist")

		if shoulder and shoulder:IsA("Motor6D")
			and elbow and elbow:IsA("Motor6D")
			and wrist and wrist:IsA("Motor6D") then
			-- Each length is read inside the one part both its joints attach to, so it
			-- holds in any pose: C0 is the pivot in the joint's parent part, C1 the pivot
			-- in its child. The hand contributes wrist-pivot to hand-origin, which is
			-- where IKControl drives the end effector to.
			local upperLength = (elbow.C0.Position - shoulder.C1.Position).Magnitude
			local lowerLength = (wrist.C0.Position - elbow.C1.Position).Magnitude
			local handLength = wrist.C1.Position.Magnitude
			return (upperLength + lowerLength + handLength) * ARM_REACH_EXTENSION
		end

		return (upperArm.Size.Y + lowerArm.Size.Y + hand.Size.Y) * ARM_REACH_PART_SIZE_FACTOR
	end

	local r6Arm = character:FindFirstChild("Right Arm")
	if r6Arm and r6Arm:IsA("BasePart") then
		-- One part spans the whole arm, so its length is the reach with no joint overlap
		-- to discount.
		return r6Arm.Size.Y * ARM_REACH_EXTENSION
	end

	return nil
end

local function grab(player: Player)
	if activePlayer then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then return end
	if not hrp or not hrp:IsA("BasePart") then return end

	local frontOffset = model:GetAttribute("PushFrontOffset") or computeArmReach(character) or DEFAULT_FRONT_OFFSET

	-- One pushable per player. This script instance can only see its own cart, so the
	-- registry is what notices the player already holds another and releases it for
	-- us. Without it they accumulate carts, each contributing its own pair of
	-- IKControls competing for the same two hands.
	PushRegistry.claim(player, model, release)

	activePlayer = player
	prompt.Enabled = false

	local pushWalkSpeed = model:GetAttribute("PushWalkSpeed")
	if typeof(pushWalkSpeed) == "number" then
		originalWalkSpeed = humanoid.WalkSpeed
		activeHumanoid = humanoid
		humanoid.WalkSpeed = pushWalkSpeed
	end

	local hrpLook = hrp.CFrame.LookVector
	local flatLook = Vector3.new(hrpLook.X, 0, hrpLook.Z)
	if flatLook.Magnitude < MIN_LOOK_MAGNITUDE then
		flatLook = Vector3.new(0, 0, -1)
	end
	flatLook = flatLook.Unit

	local handlePos = handleAnchor.Position

	local gripPos = handlePos
	local gripLocal = model:GetAttribute("PushGripLocal")
	if typeof(gripLocal) == "Vector3" then
		gripPos = handleAnchor.CFrame:PointToWorldSpace(gripLocal)
	end

	local forwardRef
	local forwardLocal = model:GetAttribute("PushForwardLocal")
	if typeof(forwardLocal) == "Vector3" then
		local forwardWorld = handleAnchor.CFrame:VectorToWorldSpace(forwardLocal)
		local flatForward = Vector3.new(forwardWorld.X, 0, forwardWorld.Z)
		forwardRef = if flatForward.Magnitude >= MIN_LOOK_MAGNITUDE then flatForward.Unit else flatLook
	else
		-- Measured from the middle of the handle, not handleAnchor's own origin: on a
		-- grouped handlebar the resolved part can sit off to one side, which skews
		-- "forward" sideways and takes the stand point with it.
		local bodyCenter = model:GetBoundingBox().Position
		local cartForward = Vector3.new(bodyCenter.X - gripPos.X, 0, bodyCenter.Z - gripPos.Z)
		forwardRef = if cartForward.Magnitude >= MIN_LOOK_MAGNITUDE then cartForward.Unit else flatLook
	end

	local standX = gripPos.X - forwardRef.X * frontOffset
	local standZ = gripPos.Z - forwardRef.Z * frontOffset

	local standY = hrp.Position.Y
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model, character }
	rayParams.IgnoreWater = true
	-- Only collidable geometry can hold the character up. Landing this ray on a
	-- non-collidable decal puts the stand point above where the client will
	-- actually settle, and that disagreement is what the follow loop inherits.
	rayParams.RespectCanCollide = true
	local rayOrigin = Vector3.new(standX, gripPos.Y + RAY_START_HEIGHT, standZ)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -(RAY_START_HEIGHT + RAY_DROP_LENGTH), 0), rayParams)
	if rayResult then
		local hipToRoot = if humanoid.RigType == Enum.HumanoidRigType.R6
			then R6_HIP_TO_ROOT
			else humanoid.HipHeight + hrp.Size.Y * 0.5
		standY = rayResult.Position.Y + hipToRoot
	end

	character:PivotTo(CFrame.lookAlong(Vector3.new(standX, standY, standZ), forwardRef))

	if not groundAlign then
		primaryPart.Anchored = false

		local weld = Instance.new("WeldConstraint")
		weld.Name = GRAB_WELD_NAME
		weld.Part0 = hrp
		weld.Part1 = handleAnchor
		weld.Parent = handleAnchor
		grabWeld = weld

		pcall(function()
			primaryPart:SetNetworkOwner(player)
		end)
	end

	if groundAlign then
		-- The anchor must describe the cart as the follow loop will drive it -- levelled
		-- onto the ground -- not as it happened to be parked when grabbed. Measuring
		-- grip-to-wheel-centroid between world positions folds the cart's resting pitch
		-- into the horizontal run, and the follow loop then carries that error onto
		-- level ground for the rest of the push. A cart picked up off a 17 degree slope
		-- yielded a run 1.4 studs short of the same cart picked up on the flat, which
		-- put the handle behind the pusher and left the hand IK reaching backwards.
		-- Reading the offset through the cart's own forward/up basis is independent of
		-- how it was parked, so every grab of a given cart produces the same anchor.
		local forwardLocal = model:GetAttribute("PushGroundForwardLocal")
		local upLocal = model:GetAttribute("PushGroundUpLocal")

		local anchorCentroid = Vector3.zero
		local anchorCount = 0
		for _, descendant in primaryPart:GetChildren() do
			if descendant:IsA("Attachment") and descendant.Name == GROUND_CONTACT_NAME then
				anchorCentroid += descendant.Position
				anchorCount += 1
			end
		end

		if anchorCount > 0 and typeof(forwardLocal) == "Vector3" and typeof(upLocal) == "Vector3" then
			anchorCentroid /= anchorCount
			local gripInPrimary = primaryPart.CFrame:PointToObjectSpace(gripPos)
			local levelBasis = CFrame.lookAlong(Vector3.zero, forwardLocal, upLocal)
			local gripToCentroid = levelBasis:VectorToObjectSpace(anchorCentroid - gripInPrimary)
			-- The pusher stands frontOffset behind the grip along the cart's forward, so
			-- the centroid sits that much further ahead in the pusher's yaw frame.
			model:SetAttribute("PushGroundAnchorLocal", gripToCentroid - Vector3.new(0, 0, frontOffset))
		end
	end

	pushedBy.Value = player
	model:SetAttribute("pushActive", true)

	table.insert(releaseWatchers, character.AncestryChanged:Connect(function(_, parent)
		if not parent then release() end
	end))
	table.insert(releaseWatchers, humanoid.Died:Connect(release))
end

prompt.Triggered:Connect(function(player: Player)
	grab(player)
end)

releaseEvent.OnServerEvent:Connect(function(player: Player, finalPose: any)
	if player ~= activePlayer then return end
	-- The release click carries the pose reliably, so the cart is left exactly
	-- where the pusher saw it rather than at the last unreliable packet.
	applyPose(player, finalPose)
	release()
end)

poseEvent.OnServerEvent:Connect(applyPose)

Players.PlayerRemoving:Connect(function(player: Player)
	if player == activePlayer then release() end
end)

model.Destroying:Connect(clearReleaseWatchers)

--[[
IKHands - Shared client-side hand IK helper

Drives a character's hands onto target Attachments via IKControl. Handles both
R15 and R6 rigs, and un-kinematics the character's arm AnimationConstraints
(Roblox's current default character joints) so IK can override the animation
graph while gripping. Everything is restored on teardown.

Client context only. Usage:
	local handle = IKHands.attach(humanoid, { Left = leftAttachment, Right = rightAttachment })
	-- later
	handle:Destroy()
]]

local IKHands = {}

local ARM_PART_NAMES = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
}

local DEFAULT_WEIGHT = 1
local DEFAULT_SMOOTH_TIME = 0
local CONTROL_NAME_PREFIX = "IKHands_"

export type HandSide = "Left" | "Right"

export type HandTargets = {
	Left: Attachment?,
	Right: Attachment?,
}

export type AttachOptions = {
	Weight: number?,
	SmoothTime: number?,
}

export type IKHandsHandle = {
	Destroy: (IKHandsHandle) -> (),
}

local function getArmChainParts(humanoid: Humanoid, side: HandSide): (BasePart?, BasePart?)
	local character = humanoid.Parent
	if not character then return nil, nil end

	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		local upperArmName = if side == "Left" then "LeftUpperArm" else "RightUpperArm"
		local handName = if side == "Left" then "LeftHand" else "RightHand"
		local upperArm = character:FindFirstChild(upperArmName)
		local hand = character:FindFirstChild(handName)
		if upperArm and upperArm:IsA("BasePart") and hand and hand:IsA("BasePart") then
			return upperArm, hand
		end

		return nil, nil
	end

	local armName = if side == "Left" then "Left Arm" else "Right Arm"
	local torso = character:FindFirstChild("Torso")
	local arm = character:FindFirstChild(armName)
	if torso and torso:IsA("BasePart") and arm and arm:IsA("BasePart") then
		return torso, arm
	end

	return nil, nil
end

local function isArmDescendant(instance: Instance, character: Model): boolean
	local current = instance.Parent
	while current and current ~= character do
		if ARM_PART_NAMES[current.Name] then return true end
		current = current.Parent
	end

	return false
end

local function attachHand(humanoid: Humanoid, side: HandSide, target: Attachment, weight: number, smoothTime: number): IKControl?
	local chainRoot, endEffector = getArmChainParts(humanoid, side)
	if not chainRoot or not endEffector then return nil end

	local ikControl = Instance.new("IKControl")
	ikControl.Name = CONTROL_NAME_PREFIX .. side
	ikControl.Type = Enum.IKControlType.Position
	ikControl.ChainRoot = chainRoot
	ikControl.EndEffector = endEffector
	ikControl.Target = target
	ikControl.Weight = weight
	ikControl.SmoothTime = smoothTime
	ikControl.Parent = humanoid

	return ikControl
end

function IKHands.attach(humanoid: Humanoid, targets: HandTargets, options: AttachOptions?): IKHandsHandle
	local resolvedOptions = options or {}
	local weight = resolvedOptions.Weight or DEFAULT_WEIGHT
	local smoothTime = resolvedOptions.SmoothTime or DEFAULT_SMOOTH_TIME

	local cleanups: { () -> () } = {}
	local character = humanoid.Parent

	if character and character:IsA("Model") then
		for _, descendant in character:GetDescendants() do
			if not descendant:IsA("AnimationConstraint") then continue end
			if not descendant.IsKinematic then continue end
			if not isArmDescendant(descendant, character) then continue end

			local constraint = descendant
			constraint.IsKinematic = false
			table.insert(cleanups, function()
				if constraint.Parent then
					constraint.IsKinematic = true
				end
			end)
		end
	end

	local leftTarget = targets.Left
	if leftTarget then
		local ikControl = attachHand(humanoid, "Left", leftTarget, weight, smoothTime)
		if ikControl then
			table.insert(cleanups, function()
				ikControl:Destroy()
			end)
		end
	end

	local rightTarget = targets.Right
	if rightTarget then
		local ikControl = attachHand(humanoid, "Right", rightTarget, weight, smoothTime)
		if ikControl then
			table.insert(cleanups, function()
				ikControl:Destroy()
			end)
		end
	end

	local destroyed = false
	local handle = {}

	function handle:Destroy()
		if destroyed then return end
		destroyed = true
		for _, cleanup in cleanups do
			cleanup()
		end
	end

	return handle
end

return IKHands

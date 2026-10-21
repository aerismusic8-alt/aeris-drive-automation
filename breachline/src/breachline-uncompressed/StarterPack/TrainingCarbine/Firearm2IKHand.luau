-- GENERATED WRAPPER around upstream Firearm2IKHand.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: Firearm2IKHand.server.luau
	RunContext: Client (see Firearm2IKHand.meta.json)
]]--

if not script.Parent:IsA("Tool") then return end

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if RunService:IsServer() then return end

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local Constants = require(Firearm2.Common.Constants)
local Dumpster = require(FourD.Libs.Dumpster)

-- Constants

local IK_CONTROL_NAME = Constants.IK_CONTROL_NAME
local IK_SMOOTH_TIME = Constants.IK_SMOOTH_TIME
local IK_WEIGHT = Constants.IK_WEIGHT
local LEFT_HAND_GRIP_NAME = Constants.LEFT_HAND_GRIP_NAME
local RIGHT_HAND_GRIP_NAME = Constants.RIGHT_HAND_GRIP_NAME
local RIGHT_HAND_IK_CONTROL_NAME = Constants.RIGHT_HAND_IK_CONTROL_NAME

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

-- Types

type DumpsterType = typeof(Dumpster.new())
type HandSide = "Left" | "Right"

-- Variables

local Tool: Tool = script.Parent
local MainDump: DumpsterType = Dumpster.new()
local EquipDump: DumpsterType? = nil

-- Local Functions

local function findAttachmentByName(name: string): Attachment?
	for _, descendant in Tool:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end

	return nil
end

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

local function teardownIK()
	if not EquipDump then return end
	EquipDump:Destroy()
	EquipDump = nil
end

local function setupHandIK(humanoid: Humanoid, dump: DumpsterType, side: HandSide)
	local gripName = if side == "Left" then LEFT_HAND_GRIP_NAME else RIGHT_HAND_GRIP_NAME
	local controlName = if side == "Left" then IK_CONTROL_NAME else RIGHT_HAND_IK_CONTROL_NAME

	local target = findAttachmentByName(gripName)
	if not target then return end

	local chainRoot, endEffector = getArmChainParts(humanoid, side)
	if not chainRoot or not endEffector then return end

	local ikControl = Instance.new("IKControl")
	ikControl.Name = controlName
	ikControl.Type = Enum.IKControlType.Transform
	ikControl.ChainRoot = chainRoot
	ikControl.EndEffector = endEffector
	ikControl.Target = target
	ikControl.Weight = IK_WEIGHT
	ikControl.SmoothTime = IK_SMOOTH_TIME
	ikControl.Parent = humanoid

	dump:Add(ikControl)
end

local function isArmDescendant(instance: Instance, character: Model): boolean
	local current = instance.Parent
	while current and current ~= character do
		if ARM_PART_NAMES[current.Name] then return true end
		current = current.Parent
	end

	return false
end

local function disableKinematicConstraints(character: Model, dump: DumpsterType)
	for _, descendant in character:GetDescendants() do
		if not descendant:IsA("AnimationConstraint") then continue end
		if not descendant.IsKinematic then continue end
		if not isArmDescendant(descendant, character) then continue end

		local constraint = descendant
		constraint.IsKinematic = false
		dump:Add(function()
			if constraint.Parent then
				constraint.IsKinematic = true
			end
		end)
	end
end

local function setupIK()
	teardownIK()

	local character = Tool.Parent
	if not character or not character:IsA("Model") then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	EquipDump = Dumpster.new()
	disableKinematicConstraints(character, EquipDump)
	setupHandIK(humanoid, EquipDump, "Left")
	setupHandIK(humanoid, EquipDump, "Right")
end

local function onAncestryChanged()
	local parent = Tool.Parent
	if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
		setupIK()
	else
		teardownIK()
	end
end

-- Initialization

MainDump:Add(Tool.AncestryChanged:Connect(onAncestryChanged))
MainDump:Add(Tool.Destroying:Connect(function()
	teardownIK()
	MainDump:Destroy()
end))

onAncestryChanged()

end

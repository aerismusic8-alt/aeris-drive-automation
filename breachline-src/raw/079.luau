--[[
Towable Behavior - Adds hitch connect/disconnect to a vehicle

Takes an assembled vehicle model and a hitch part, creates a BallSocketConstraint
attachment point. The tower can be toggled either by a ProximityPrompt (default) or,
when a driver seat is supplied, by driver input (T / DPadDown / mobile button) routed
through a RemoteEvent and the central Keybinds + HelpUI systems.

Dependencies: FourD/Common (GeometryUtils, ConstructionHelpers)
]]

local CollectionService = game:GetService("CollectionService")

local FourD = script:FindFirstAncestor("FourD")
local Common = FourD.Common
local ConstructionHelpers = require(Common.ConstructionHelpers)
local GeometryUtils = require(Common.GeometryUtils)

local RECEIVER_TAG = "TowHitchReceiver"

local Towable = {}

function Towable.setupTower(assembledModel: Model, hitchPart: Instance, config: { SkipWeld: boolean?, DriverSeat: Seat?, MaxAttachDistance: number? }?)
	local options = config or {}

	if options.MaxAttachDistance then
		assembledModel:SetAttribute("HitchMaxAttachDistance", options.MaxAttachDistance)
	end

	local hitchAnchor = if hitchPart:IsA("BasePart")
		then hitchPart
		else GeometryUtils.getOrSetPrimaryPart(hitchPart)

	if not hitchAnchor then
		warn("[Towable] setupTower: no BasePart resolved for hitch on " .. assembledModel:GetFullName())
		return
	end

	hitchAnchor.Anchored = false
	hitchAnchor.CanCollide = false
	hitchAnchor.Massless = true

	if not options.SkipWeld then
		local chassis = GeometryUtils.findRigChassis(assembledModel)
		if chassis then
			ConstructionHelpers.makeWeld(chassis, hitchAnchor)
		end
	end

	local hitchAttachment = Instance.new("Attachment")
	hitchAttachment.Name = "HitchAttachment"
	hitchAttachment.Parent = hitchAnchor

	assembledModel:SetAttribute("hitchConnected", false)

	local driverSeat = options.DriverSeat

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HitchPrompt"
	prompt.ActionText = "Connect"
	prompt.ObjectText = "Hitch"
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.Enabled = driverSeat == nil
	prompt.Parent = hitchAnchor

	if driverSeat then
		local seatRef = Instance.new("ObjectValue")
		seatRef.Name = "Towable_DriverSeatRef"
		seatRef.Value = driverSeat
		seatRef.Parent = assembledModel

		local toggleEvent = Instance.new("RemoteEvent")
		toggleEvent.Name = "HitchToggleEvent"
		toggleEvent.Parent = assembledModel

		local inputScript = script:FindFirstChild("TowableInput")
		if inputScript then
			local inputClone = inputScript:Clone()
			if inputClone:IsA("BaseScript") then
				inputClone.Enabled = true
			end
			inputClone.Parent = assembledModel
		end
	end

	local hitchScript = script:FindFirstChild("TowableServer")
	if hitchScript then
		local clone = hitchScript:Clone()
		clone.Enabled = true
		clone.Parent = assembledModel
	end
end

function Towable.setupReceiverAtPoint(assembledModel: Instance, anchorPart: BasePart, receiverCFrame: CFrame, config: { FixedAlignment: boolean? }?)
	local options = config or {}

	local receiverAttachment = Instance.new("Attachment")
	receiverAttachment.Name = "HitchReceiverAttachment"
	receiverAttachment.Parent = anchorPart
	receiverAttachment.WorldCFrame = receiverCFrame
	receiverAttachment:SetAttribute("FixedAlignment", options.FixedAlignment == true)
	CollectionService:AddTag(receiverAttachment, RECEIVER_TAG)

	local ownerRef = Instance.new("ObjectValue")
	ownerRef.Name = "Towable_OwnerModel"
	ownerRef.Value = assembledModel
	ownerRef.Parent = receiverAttachment

	assembledModel:SetAttribute("isTowReceiver", true)
end

function Towable.setupTowable(assembledModel: Instance, hitchPart: Instance, config: { FixedAlignment: boolean? }?)
	local allParts = GeometryUtils.getInstanceParts(assembledModel)
	local hitchParts = GeometryUtils.getInstanceParts(hitchPart)
	local couplerCFrame, anchorPart = GeometryUtils.findCouplerPoint(allParts, hitchParts)

	Towable.setupReceiverAtPoint(assembledModel, anchorPart, couplerCFrame, config)
end

return Towable
6
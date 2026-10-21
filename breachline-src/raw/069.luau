--[[
	File: Common/ResolveOrigin.luau

	Resolves a `LightOrigin` (BasePart | Attachment | CFrame | Vector3) into
	a concrete parent Instance suitable for parenting a Light to.

	For world-space origins (CFrame / Vector3) a new Attachment is created
	under `workspace.Terrain` and added to the supplied Dumpster so it gets
	cleaned up when the caller class is destroyed.

	For instance origins (BasePart / Attachment) the Dumpster is attached
	to the origin so the caller class auto-destroys with it.
]]--

-- Dependencies

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local Types = require(FourD.Behaviors.Lightable.Common.Types)

-- Public Functions

local function resolveOrigin(
	origin: Types.LightOrigin,
	dumpster: typeof(Dumpster.new())
): (BasePart | Attachment, boolean)
	assert(origin ~= nil, "origin must not be nil")

	local originType = typeof(origin)

	if originType == "Instance" then
		local instance = origin :: any
		if instance:IsA("BasePart") then
			dumpster:AttachTo(instance)
			return instance, false
		end

		if instance:IsA("Attachment") then
			dumpster:AttachTo(instance)
			return instance, false
		end

		error(`origin Instance must be a BasePart or Attachment, got {instance.ClassName}`)
	end

	if originType == "CFrame" then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Lightable_OriginAttachment"
		attachment.WorldCFrame = origin :: CFrame
		attachment.Parent = workspace.Terrain
		dumpster:Add(attachment)
		return attachment, true
	end

	if originType == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Lightable_OriginAttachment"
		attachment.WorldCFrame = CFrame.new(origin :: Vector3)
		attachment.Parent = workspace.Terrain
		dumpster:Add(attachment)
		return attachment, true
	end

	error(`origin must be a BasePart, Attachment, CFrame, or Vector3 (got {originType})`)
end

return resolveOrigin
f
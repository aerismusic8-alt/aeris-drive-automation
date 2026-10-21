 no pruning, no
	welding, no part flag changes. Attachments are used directly as shot
	origins.

	Multi-barrel timing via FireSequence ("Simultaneous" or "Cycled").
]]--

local FourD = script:FindFirstAncestor("FourD")
local Common = script.Parent.Parent.Common
local BuildBulletTemplate = require(Common.BuildBulletTemplate)
local DiscoverMounts = require(Common.DiscoverMounts)
local DetectHardpoints = require(Common.DetectHardpoints)
local PruneFiltered = require(Common.PruneFiltered)
local Types = require(Common.Types)
local GeometryUtils = require(FourD.Common.GeometryUtils)

local Hardpoint = {}

local function isAttachmentList(source: any): boolean
	if typeof(source) ~= "table" then return false end
	if #source == 0 then return false end
	for _, entry in ipairs(source) do
		if typeof(entry) ~= "Instance" or not entry:IsA("Attachment") then
			return false
		end
	end

	return true
end

local function rigModelSource(assembledModel: Model, gunModel: Model): { Attachment }?
	PruneFiltered(gunModel)

	local mounts = DiscoverMounts(assembledModel, gunModel)
	if not mounts then return nil end

	local chassis = mounts.Chassis
	local chassisInverseCFrame = chassis.CFrame:Inverse()
	for _, part in ipairs(GeometryUtils.getInstanceParts(gunModel)) do
		part.CanCollide = false
		part.Massless = true
		local weld = Instance.new("Weld")
		weld.Part0 = chassis
		weld.Part1 = part
		weld.C0 = chassisInverseCFrame * part.CFrame
		weld.C1 = CFrame.new()
		weld.Parent = chassis
		part.Anchored = false
	end
	gunModel.Parent = assembledModel

	return DetectHardpoints(gunModel, mounts.GunForward)
end

local function rigAttachmentSource(source: { Attachment }): { Attachment }
	return source
end

function Hardpoint.rig(assembledModel: Model, source: Model | BasePart | { Attachment }, config: Types.HardpointConfig): boolean
	local attachments: { Attachment }?

	if typeof(source) == "Instance" and source:IsA("BasePart") then
		local part = source
		local wrapper = Instance.new("Model")
		wrapper.Name = part.Name
		wrapper.Parent = part.Parent
		part.Parent = wrapper
		source = wrapper
	end
	if typeof(source) == "Instance" and source:IsA("Model") then
		attachments = rigModelSource(assembledModel, source)
	elseif isAttachmentList(source) then
		attachments = rigAttachmentSource(source :: { Attachment })
	else
		warn("[Hardpoint] source must be a Model, BasePart, or a non-empty list of Attachments")
		return false
	end

	if not attachments or #attachments == 0 then
		warn("[Hardpoint] no shot-origin attachments resolved")
		return false
	end

	local attsFolder = Instance.new("Folder")
	attsFolder.Name = "Gunnable_HardpointAttachments"
	for i, att in ipairs(attachments) do
		local objectValue = Instance.new("ObjectValue")
		objectValue.Name = tostring(i)
		objectValue.Value = att
		objectValue.Parent = attsFolder
	end
	attsFolder.Parent = assembledModel
	assembledModel:SetAttribute("Gunnable_HardpointAttachmentCount", #attachments)
	assembledModel:SetAttribute("Gunnable_HasSeat", config.Seat ~= nil)

	if config.Seat then
		local seatRefValue = Instance.new("ObjectValue")
		seatRefValue.Name = "Gunnable_SeatRef"
		seatRefValue.Value = config.Seat
		seatRefValue.Parent = assembledModel
	end

	assembledModel:SetAttribute("Gunnable_FireSequence", config.FireSequence or "Simultaneous")

	local fireTurretEvent = Instance.new("RemoteEvent")
	fireTurretEvent.Name = "GunnerFire"
	fireTurretEvent.Parent = assembledModel

	BuildBulletTemplate.setup(assembledModel)

	return true
end

function Hardpoint.attachScripts(assembledModel: Model)
	local serverScript = script:FindFirstChild("HardpointServer")
	if serverScript then
		local clone = serverScript:Clone()
		clone.Enabled = true
		clone.Parent = assembledModel
	end

	local clientScript = script:FindFirstChild("HardpointClient")
	if clientScript then
		local clone = clientScript:Clone()
		if clone:IsA("BaseScript") then
			clone.Enabled = true
		end
		clone.Parent = assembledModel
	end

	local hudScript = script:FindFirstChild("HardpointHud")
	if hudScript then
		local clone = hudScript:Clone()
		if clone:IsA("BaseScript") then
			clone.Enabled = true
		end
		clone.Parent = assembledModel
	end
end

return Hardpoint

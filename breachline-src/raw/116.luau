--[[
	File: BuildHandle.luau
]]--

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local Constants = require(script.Parent.Constants)
local Replication = require(script.Parent.Replication)

-- Constants

local ATTRIBUTE_KEYS = Constants.PARAM_KEYS
local BODY_PART_NAME = Constants.BODY_PART_NAME

-- Function

return function(
	orientedModel: Model,
	forwardDirection: Vector3,
	params: { [string]: any }
): Tool
	local boundingCF, boundingSize = orientedModel:GetBoundingBox()
	local bodyCF = CFrame.lookAt(boundingCF.Position, boundingCF.Position + forwardDirection)

	local body = Instance.new("Part")
	body.Name = BODY_PART_NAME
	body.Size = boundingSize
	body.CFrame = bodyCF
	body.Transparency = 1
	body.CanCollide = true
	body.CanQuery = false
	body.Anchored = true
	body.Massless = true

	local tool = Instance.new("Tool")
	tool.Name = orientedModel.Name
	tool.RequiresHandle = false
	tool.CanBeDropped = false

	body.Parent = tool
	orientedModel.Parent = tool

	for _, descendant in orientedModel:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end

		descendant.Anchored = false
		descendant.CanCollide = false
		descendant.Massless = true
		ConstructionHelpers.makeWeld(body, descendant)
	end

	for _, key in ATTRIBUTE_KEYS do
		tool:SetAttribute(key, params[key])
	end

	Replication.attachRemotes(tool)
	CollectionService:AddTag(tool, Constants.FIREARM2_TAG)

	return tool
end


--[[
	File: BuildHull.luau
]]--

-- Root

local BuildHull = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local GeometryUtils = require(FourD.Common.GeometryUtils)

-- Constants

local HULL_ROOT_NAME = "HullRoot"
local HULL_ROOT_SIZE = Vector3.new(2, 2, 2)

-- Local Functions

local function makeRootPart(cf: CFrame, forwardAxis: Vector3): Part
	local part = Instance.new("Part")
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(cf.Position, cf.Position + forwardAxis)
	part.Massless = true
	part.Name = HULL_ROOT_NAME
	part.Size = HULL_ROOT_SIZE
	part.Transparency = 1
	return part
end

-- Public Functions

function BuildHull.rig(
	wrapperModel: Model,
	bodyModel: Model,
	body: PVInstance,
	forwardAxis: Vector3
): HullResult
	local bodyCenter, bodySize = GeometryUtils.getBodyBounds(body)

	local hullRoot = makeRootPart(CFrame.new(bodyCenter), forwardAxis)
	hullRoot.Parent = wrapperModel
	wrapperModel.PrimaryPart = hullRoot

	for _, child in bodyModel:GetChildren() do
		ConstructionHelpers.weldAllParts(child, hullRoot)
	end

	return {
		Root = hullRoot,
		BodyCenter = bodyCenter,
		BodySize = bodySize,
		ForwardAxis = forwardAxis,
		HoldAltitudeY = hullRoot.Position.Y,
	}
end

-- Types

export type HullResult = {
	Root: BasePart,
	BodyCenter: Vector3,
	BodySize: Vector3,
	ForwardAxis: Vector3,
	HoldAltitudeY: number,
}

-- Return

return BuildHull

--[[
	File: Common/DiscoverMounts.luau
]]--

local FourD = script:FindFirstAncestor("FourD")
local GeometryUtils = require(FourD.Common.GeometryUtils)

export type Mounts = {
	Chassis: BasePart,
	PivotCFrame: CFrame,
	GunForward: Vector3,
	MuzzlePart: BasePart?,
	MuzzleTip: Vector3,
	GunSize: Vector3,
}

local function discoverMounts(assembledModel: Model, gunModel: Model): Mounts?
	local chassis = GeometryUtils.findRigChassis(assembledModel)
	if not chassis and assembledModel.PrimaryPart then
		chassis = assembledModel.PrimaryPart
	end
	if not chassis then
		local body = assembledModel:FindFirstChild("body")
		chassis = body and GeometryUtils.getOrSetPrimaryPart(body)
	end

	if not chassis then
		warn("[Gunnable] Could not find chassis or body to attach gun")
		return nil
	end

	local carForward = chassis.CFrame.LookVector
	local gunForward = GeometryUtils.detectGunForward(gunModel, carForward)
	local pivotPos = GeometryUtils.findGunPivot(gunModel, gunForward)
	local pivotCFrame = CFrame.lookAt(pivotPos, pivotPos + gunForward)

	local gunSize = GeometryUtils.getInstanceSize(gunModel)
	local muzzlePart, muzzleTip = GeometryUtils.findGunMuzzle(gunModel, gunForward)

	return {
		Chassis = chassis,
		PivotCFrame = pivotCFrame,
		GunForward = gunForward,
		MuzzlePart = muzzlePart,
		MuzzleTip = muzzleTip,
		GunSize = gunSize,
	}
end

return discoverMounts

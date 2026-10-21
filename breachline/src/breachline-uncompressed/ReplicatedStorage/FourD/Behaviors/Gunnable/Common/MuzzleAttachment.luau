--[[
	File: Common/MuzzleAttachment.luau

	Creates the `GunnerMuzzleAttachment` at the rigged muzzle tip, oriented
	along the gun's forward axis. Consumed by Turret server/client for fire
	origin + direction lookup. Visual FX (BillboardGui + PointLight) are
	spawned client-side per shot via FourD.Common.MuzzleFlashFx, not here.
]]--

local MuzzleAttachment = {}

function MuzzleAttachment.create(muzzlePart: BasePart?, muzzleTip: Vector3, gunForward: Vector3): Attachment?
	if not muzzlePart then return nil end

	local att = Instance.new("Attachment")
	att.Name = "GunnerMuzzleAttachment"
	local worldCF = CFrame.lookAt(muzzleTip, muzzleTip + gunForward)
	att.CFrame = muzzlePart.CFrame:Inverse() * worldCF
	att.Parent = muzzlePart

	return att
end

return MuzzleAttachment

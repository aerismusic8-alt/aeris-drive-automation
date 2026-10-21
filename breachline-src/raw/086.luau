 there is no input detection.
---@param assembledModel -- Vehicle/structure model that hosts the launcher.
---@param originAttachment -- Attachment whose WorldCFrame fixes shot origin position and angle.
---@param projectileTemplate -- BasePart or Model cloned client-side as the visual projectile.
---@param config -- Launcher tuning; see `Types.LauncherConfig`. Invalid numeric values raise an error.
---@return launcher -- Launcher handle exposing `:Fire()` and `:Destroy()`.
function Gunnable.newLauncher(assembledModel: Model, originAttachment: Attachment, projectileTemplate: BasePart | Model, config: LauncherConfig): Launcher
	return Launcher.new(assembledModel, originAttachment, projectileTemplate, config)
end

---Geometrically detects barrel attachment points inside an arbitrary gun Model and
---returns Attachments parented to the appropriate gun parts and oriented along
---`forwardAxis`. Suitable for passing back into `newHardpoint` as the `source` argument
---when the caller wants manual control over pruning and welding.
---@param gunModel -- Gun Model to scan for barrel parts.
---@param forwardAxis -- World-space unit vector indicating the gun's firing direction.
---@return attachments -- Array of Attachments parented to detected barrel parts. Empty if `gunModel` has no BaseParts.
function Gunnable.detectHardpoints(gunModel: Model | BasePart, forwardAxis: Vector3): { Attachment }
	return DetectHardpoints(ensureGunModel(gunModel), forwardAxis)
end

---Geometrically detects the single muzzle tip of `gunModel` (same detection the old
---managed turret used) and creates a `GunnerMuzzleAttachment` there, oriented along the
---gun's forward axis. Suitable for passing into `newHardpoint` as a one-element
---attachment list when a turret-mounted gun should fire from its detected muzzle.
---@param assembledModel -- Host model used to resolve the chassis (defines the forward hint).
---@param gunModel -- Gun Model to scan for the muzzle part.
---@return attachment -- Muzzle Attachment parented to the detected muzzle part. `nil` if discovery failed.
function Gunnable.detectMuzzle(assembledModel: Model, gunModel: Model | BasePart): Attachment?
	local mounts = DiscoverMounts(assembledModel, ensureGunModel(gunModel))
	if not mounts then return nil end

	return MuzzleAttachment.create(mounts.MuzzlePart, mounts.MuzzleTip, mounts.GunForward)
end

---Creates a transparent, massless `GunnerSeat` welded to the chassis at the gun's pivot
---offset. Used by callers that want a co-op turret seat without wiring the full turret
---rig themselves. The seat is parented to `assembledModel`.
---@param assembledModel -- Vehicle model that hosts the gunner seat.
---@param gunModel -- Gun Model whose pivot defines the seat placement.
---@return seat -- Newly created `Seat`. `nil` if mount discovery failed.
function Gunnable.makeGunnerSeat(assembledModel: Model, gunModel: Model | BasePart): Seat?
	local mounts = DiscoverMounts(assembledModel, ensureGunModel(gunModel))
	if not mounts then return nil end

	local seat = Instance.new("Seat")
	seat.Name = "GunnerSeat"
	seat.Size = Vector3.new(1.5, 0.5, 1.5)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.Anchored = false
	seat.CFrame = mounts.PivotCFrame * CFrame.new(0, -mounts.GunSize.Y * 0.5, mounts.GunSize.Z * 0.8)
	seat.Parent = assembledModel

	ConstructionHelpers.makeWeld(mounts.Chassis, seat)

	return seat
end

return Gunnable

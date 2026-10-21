 no firing logic, UI ammo, or projectiles.
---Solo mode (DriverSeat only) lets the driver swap drive/gun roles with `F`. Co-op mode
---(DriverSeat + GunnerSeat) exposes a `GunnerPrompt` on the chassis. Prunes filtered
---decoration on `gunModel` and welds it to the chassis pivot before wiring controls.
---Fireable weapons are attached separately: create Hardpoints/Launchers on the same model
---and link them via the returned handle's `:BindWeapon(weapon)`.
---@param assembledModel -- Vehicle model that hosts the turret. Must contain a chassis or `body` child.
---@param gunModel -- Gun Model whose parts become the swivel barrel(s).
---@param config -- Turret aim tuning + seat references; see `Types.TurretConfig`.
---@return turretHandle -- Handle exposing `:SetController(player?)`, `:BindWeapon(weapon)`, and `:Destroy()`. `nil` if mount discovery failed.
function Gunnable.newTurret(assembledModel: Model, gunModel: Model | BasePart, config: TurretConfig): TurretHandle?
	gunModel = ensureGunModel(gunModel)
	if config.YawModel then
		config = table.clone(config)
		config.YawModel = ensureGunModel(config.YawModel)
	end
	PruneFiltered(gunModel)

	local mounts = DiscoverMounts(assembledModel, gunModel)
	if not mounts then return nil end

	Turret.rig(assembledModel, gunModel, mounts, config)
	Turret.attachScripts(assembledModel)

	return makeTurretHandle(assembledModel, config)
end

---Rigs a fixed-mount weapon on `assembledModel`. Behavior depends on `source`:
---if a `Model`, prunes filtered decoration, welds gun parts to the host chassis, and
---auto-detects multi-barrel attachments via `detectHardpoints`. If a list of `Attachment`s,
---uses them directly as shot origins with no pruning, welding, or part flag changes.
---@param assembledModel -- Vehicle/structure model that hosts the hardpoint.
---@param source -- Either a gun Model (auto-prep) or pre-placed Attachments (caller-prepared).
---@param config -- Hardpoint tuning + optional Seat reference; see `Types.HardpointConfig`. `GunAmmo = -1` disables reload.
---@return controllerHandle -- Handle exposing `:SetController(player?)` and `:Destroy()`. `nil` if rigging failed.
function Gunnable.newHardpoint(assembledModel: Model, source: Model | BasePart | { Attachment }, config: HardpointConfig): ControllerHandle?
	if typeof(source) == "Instance" then
		source = ensureGunModel(source)
	end
	Configure(assembledModel, config)

	if not Hardpoint.rig(assembledModel, source, config) then
		return nil
	end

	Reload.setup(assembledModel)
	Hardpoint.attachScripts(assembledModel)

	return makeHandle(assembledModel)
end

---Rigs an explosive-projectile launcher (cannon / RPG) on `assembledModel`. The
---shot origin and angle are fixed by `originAttachment`; `projectileTemplate` is
---the visual asset clients clone for each shot. The server simulates the path,
---broadcasts one shot for clients to render, and applies impact/explosion damage
---at the calculated impact time. Firing is caller-driven via the returned
---handle's `:Fire()` 
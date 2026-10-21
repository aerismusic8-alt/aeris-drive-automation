--[[
	File: init.luau

	Public API for the Gunnable behavior. Constructors:
	  - newTurret(model, gunModel, config) — mounting + aiming only; no
	    firing logic. Returns a TurretHandle whose :BindWeapon(weapon) links
	    sibling Hardpoints/Launchers so the turret's controlling player can
	    fire them.
	  - newHardpoint(model, source, config) — generic fixed-mount; source is
	    either a gun Model or a list of Attachments. Optional Seat.
	  - newLauncher(model, originAttachment, template, config) — explosive
	    projectile launcher, caller-driven via :Fire().

	Handles expose :SetController(player?) for an explicit override
	(caller-determined controller) and :Destroy() to clear it.

	Set GunAmmo to -1 for infinite ammo (no reload). Hardpoint multi-barrel
	timing: total RPM stays GunFireRate; each barrel fires at GunFireRate / N
	when FireSequence == "Cycled".
]]--

local FourD = script:FindFirstAncestor("FourD")
local Types = require(script.Common.Types)
local DiscoverMounts = require(script.Common.DiscoverMounts)
local DetectHardpoints = require(script.Common.DetectHardpoints)
local Configure = require(script.Common.Configure)
local Controller = require(script.Common.Controller)
local MuzzleAttachment = require(script.Common.MuzzleAttachment)
local PruneFiltered = require(script.Common.PruneFiltered)
local Reload = require(script.Common.Reload)
local Turret = require(script.SubTypes.Turret)
local Hardpoint = require(script.SubTypes.Hardpoint)
local Launcher = require(script.SubTypes.Launcher)

local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

export type FireSequence = Types.FireSequence
export type TurretConfig = Types.TurretConfig
export type HardpointConfig = Types.HardpointConfig
export type LauncherConfig = Types.LauncherConfig
export type ControllerHandle = Types.ControllerHandle
export type Launcher = Launcher.Launcher

export type TurretHandle = {
	SetController: (self: TurretHandle, player: Player?) -> (),
	BindWeapon: (self: TurretHandle, weapon: ControllerHandle | Launcher) -> (),
	Destroy: (self: TurretHandle) -> (),
}

local TURRET_BOUND_ATTR = Controller.TURRET_BOUND_ATTR
-- Server component template (child of the Turret SubType module) cloned into a
-- rig when a launcher is bound, so FourDServerRuntime can reconnect firing at Play.
local TURRET_FIRE_SERVER_NAME = "TurretFireServer"

local Gunnable = {}

local function ensureGunModel(source: Instance): Model
	if source:IsA("Model") then
		return source
	end
	if not source:IsA("BasePart") then
		error("gun source must be a Model or BasePart, got " .. source.ClassName)
	end
	local part = source
	local wrapper = Instance.new("Model")
	wrapper.Name = part.Name
	wrapper.Parent = part.Parent
	part.Parent = wrapper
	return wrapper
end

local handleModels: { [ControllerHandle]: Model } = setmetatable({}, { __mode = "k" }) :: any

local function makeHandle(model: Model): ControllerHandle
	local handle = {}

	function handle:SetController(targetPlayer: Player?)
		Controller.setOverride(model, targetPlayer)
	end

	function handle:Destroy()
		Controller.setOverride(model, nil)
	end

	handleModels[handle] = model

	return handle
end

local function makeTurretHandle(model: Model, config: TurretConfig): TurretHandle
	local seatOpts = {
		PrimarySeat = config.DriverSeat :: any,
		SecondarySeat = config.GunnerSeat,
	}
	local boundLaunchers: { Launcher } = {}
	local launcherConns: { RBXScriptConnection } = {}
	local handle = {}

	local function updateAimArcViewers()
		local controller = Controller.resolve(model, seatOpts)
		for _, launcher in ipairs(boundLaunchers) do
			if typeof((launcher :: any).SetAimArcViewer) == "function" then
				launcher:SetAimArcViewer(controller)
			end
		end
	end

	local function connectLauncherFire()
		-- The fire relay (TurretFire -> launcher:Fire, gated by the controlling
		-- player) and the aim-arc viewer tracking must run at Play, not here in the
		-- edit-time bind(): a connection made now is discarded when the compiler's
		-- RigExec session ends, which is why a compiled tank received TurretFire on
		-- the server with nothing listening. Instead clone the durable
		-- TurretFireServer component into the rig once. It is stamped
		-- FourDServerComponent, registered in the runtime manifest, and started by
		-- ServerScriptService.FourDServerRuntime at Play, where it rehydrates the
		-- launcher from persisted config and reconnects the relay.
		if model:FindFirstChild(TURRET_FIRE_SERVER_NAME) then return end
		local template = script.SubTypes.Turret:FindFirstChild(TURRET_FIRE_SERVER_NAME)
		if not template then return end
		local component = template:Clone()
		component.Parent = model
	end

	function handle:SetController(targetPlayer: Player?)
		Controller.setOverride(model, targetPlayer)
	end

	function handle:BindWeapon(weapon: ControllerHandle | Launcher)
		local weaponModel = handleModels[weapon :: ControllerHandle]
		if weaponModel then
			if weaponModel ~= model then
				error("[Gunnable] BindWeapon: weapon is rigged on a different model than the turret")
			end

			model:SetAttribute(TURRET_BOUND_ATTR, true)
			return
		end

		local launcher = weapon :: any
		if typeof(launcher) == "table" and typeof(launcher.Fire) == "function" then
			table.insert(boundLaunchers, launcher)
			connectLauncherFire()
			updateAimArcViewers()
			return
		end

		error("[Gunnable] BindWeapon: expected a Hardpoint ControllerHandle or a Launcher")
	end

	function handle:Destroy()
		for _, conn in ipairs(launcherConns) do
			conn:Disconnect()
		end

		table.clear(launcherConns)
		table.clear(boundLaunchers)
		Controller.setOverride(model, nil)
	end

	return handle
end

---Rigs a Motor6D yaw/pitch turret mount on `assembledModel` using `gunModel` as the swivel
---assembly. Handles mounting and aiming only — no firing logic, UI ammo, or projectiles.
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
---handle's `:Fire()` — there is no input detection.
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

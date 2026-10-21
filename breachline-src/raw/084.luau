 explosive
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
---assembly. Handles mounting and aiming only 
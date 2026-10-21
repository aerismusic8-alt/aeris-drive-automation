--[[
	File: Common/Configure.luau
]]--

local FourD = script:FindFirstAncestor("FourD")
local Types = require(script.Parent.Types)
local createConfiguration = require(FourD.Common.createConfiguration)

local function configure(assembledModel: Model, config: Types.HardpointConfig)
	local cfg: any = config
	local ammo = cfg.GunAmmo
	if ammo == nil then ammo = 100 end

	createConfiguration(assembledModel, {
		gunDamage = cfg.GunDamage or 30,
		gunFireRate = cfg.GunFireRate or 600,
		gunAmmo = ammo,
		gunReloadTime = cfg.GunReloadTime or 3,
		gunRange = cfg.GunRange or 800,
		projectileSpeed = cfg.ProjectileSpeed or 650,
		projectileName = cfg.ProjectileName or "",
		projectileCatchUp = cfg.ProjectileCatchUp == nil and true or cfg.ProjectileCatchUp,
		projectileGravity = cfg.ProjectileGravity or 0,
		fireSequence = cfg.FireSequence or "Simultaneous",
		spread = cfg.SpreadDegrees or 0,
		convergenceRange = cfg.ConvergenceRange or 0,
		aimHudEnabled = cfg.AimHudEnabled == nil and true or cfg.AimHudEnabled,
		reticleLerp = cfg.ReticleLerp == true,
		hudViewerAttribute = cfg.HudViewerAttribute or "",
		tracerColor = cfg.TracerColor,
	}, "GunnableHardpointConfig")
end

return configure
:
--[[
	File: Common/Types.luau

	Shared config + handle types used by init, Configure, and the SubType
	rigs. Centralized here to avoid cyclic requires between init and SubTypes.
]]--

local Types = {}

export type FireSequence = "Simultaneous" | "Cycled"

export type TurretConfig = {
	DriverSeat: VehicleSeat?,
	GunnerSeat: Seat?,
	YawModel: Model?,
	GunnerPitchUp: number?,
	GunnerPitchDown: number?,
	FirstPerson: boolean?,
	DisablePitch: boolean?,
	DisableYaw: boolean?,
	DisableCrosshair: boolean?,
	TurretSpeed: number?,
}

export type HardpointConfig = {
	Seat: Seat?,
	FireSequence: FireSequence?,
	GunDamage: number?,
	GunFireRate: number?,
	GunAmmo: number?,
	GunReloadTime: number?,
	GunRange: number?,
	ProjectileSpeed: number?,
	ProjectileName: string?,
	ProjectileCatchUp: boolean?,
	ProjectileGravity: number?,
	SpreadDegrees: number?,
	ConvergenceRange: number?,
	AimHudEnabled: boolean?,
	ReticleLerp: boolean?,
	HudViewerAttribute: string?,
	TracerColor: Color3?,
}

export type LauncherExplosionConfig = {
	AffectsTerrain: boolean?,
	Radius: number?,
	Damage: number?,
	Pressure: number?,
}

export type LauncherProjectileConfig = {
	Speed: number?,
	Range: number?,
	Gravity: number?,
}

export type LauncherAimArcConfig = {
	Segments: number?,
	CollisionSegments: number?,
	Width: number?,
	Color: Color3?,
}

export type LauncherReticleConfig = {
	Lerp: boolean?,
}

export type LauncherAimVisual = "None" | "Arc" | "Hud" | "Both"

export type LauncherSmokeConfig = {
	AssetName: string,
	ParticleCount: number?,
}

export type LauncherConfig = {
	ImpactDamage: number?,
	FireRate: number?,
	Explosion: LauncherExplosionConfig?,
	Projectile: LauncherProjectileConfig?,
	AimVisual: LauncherAimVisual?,
	AimArc: LauncherAimArcConfig?,
	Reticle: LauncherReticleConfig?,
	Smoke: LauncherSmokeConfig?,
}

export type TracerShotPayload = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Gravity: number,
	ImpactPoint: Vector3,
	ImpactTime: number,
	TravelTime: number,
	Expired: boolean,
}

export type ControllerHandle = {
	SetController: (self: ControllerHandle, player: Player?) -> (),
	Destroy: (self: ControllerHandle) -> (),
}

return Types

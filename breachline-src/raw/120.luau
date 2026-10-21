--[[
	File: Types.luau
]]--

-- Root

local Types = {}

-- Types

export type AmmoReloadType = "magazine" | "shell"
export type FireType = "auto" | "semi"
export type AimMode = "default" | "scope"

export type Firearm2Params = {
	AimMode: AimMode?,
	AimSpeed: number?,
	AmmoMagSize: number?,
	AmmoReloadTime: number?,
	AmmoReloadEmptyTime: number?,
	AmmoReloadType: AmmoReloadType?,
	DamagePerRound: number?,
	FireRate: number?,
	FireType: FireType?,
	BaseSpread: number?,
	MaxSpread: number?,
	MoveSpreadMult: number?,
	SpreadPerShot: number?,
	SpreadRecovery: number?,
	MaxDistance: number?,
	ShoulderOffset: Vector3?,
	HoldCFrame: CFrame?,
	RecoilVertical: number?,
	RecoilHorizontal: number?,
	RecoilRecovery: number?,
	RecoilMaxAccum: number?,
	RecoilAdsMult: number?,
}

export type Firearm2ParamsMerged = {
	AimMode: AimMode,
	AimSpeed: number,
	AmmoMagSize: number,
	AmmoReloadTime: number,
	AmmoReloadEmptyTime: number,
	AmmoReloadType: AmmoReloadType,
	DamagePerRound: number,
	FireRate: number,
	FireType: FireType,
	BaseSpread: number,
	MaxSpread: number,
	MoveSpreadMult: number,
	SpreadPerShot: number,
	SpreadRecovery: number,
	MaxDistance: number,
	ShoulderOffset: Vector3,
	HoldCFrame: CFrame?,
	RecoilVertical: number,
	RecoilHorizontal: number,
	RecoilRecovery: number,
	RecoilMaxAccum: number,
	RecoilAdsMult: number,
}

export type PistolSchema = {
	Grip: PVInstance,
	Barrel: PVInstance,
	Frame: PVInstance?,
	Slide: PVInstance?,
	Magazine: PVInstance?,
	Trigger: PVInstance?,
}

export type PistolSetupParams = {
	Schema: PistolSchema,
	AimMode: AimMode?,
	AimSpeed: number?,
	AmmoMagSize: number?,
	AmmoReloadTime: number?,
	AmmoReloadEmptyTime: number?,
	AmmoReloadType: AmmoReloadType?,
	DamagePerRound: number?,
	FireRate: number?,
	FireType: FireType?,
	BaseSpread: number?,
	MaxSpread: number?,
	MoveSpreadMult: number?,
	SpreadPerShot: number?,
	SpreadRecovery: number?,
	MaxDistance: number?,
	ShoulderOffset: Vector3?,
	HoldCFrame: CFrame?,
	RecoilVertical: number?,
	RecoilHorizontal: number?,
	RecoilRecovery: number?,
	RecoilMaxAccum: number?,
	RecoilAdsMult: number?,
}

export type SniperSchema = {
	Grip: PVInstance,
	Frame: PVInstance,
	Barrel: PVInstance,
	Scope: PVInstance?,
}

export type SniperSetupParams = {
	Schema: SniperSchema,
	AimMode: AimMode?,
	AimSpeed: number?,
	AmmoMagSize: number?,
	AmmoReloadTime: number?,
	AmmoReloadEmptyTime: number?,
	AmmoReloadType: AmmoReloadType?,
	DamagePerRound: number?,
	FireRate: number?,
	FireType: FireType?,
	BaseSpread: number?,
	MaxSpread: number?,
	MoveSpreadMult: number?,
	SpreadPerShot: number?,
	SpreadRecovery: number?,
	MaxDistance: number?,
	ShoulderOffset: Vector3?,
	HoldCFrame: CFrame?,
	RecoilVertical: number?,
	RecoilHorizontal: number?,
	RecoilRecovery: number?,
	RecoilMaxAccum: number?,
	RecoilAdsMult: number?,
}

export type HeuristicResult = {
	OrientedModel: Model,
	ShotOrigin: Attachment,
	LeftHandGrip: Attachment,
	RightHandGrip: Attachment,
	GripPosition: Vector3,
	ForwardDirection: Vector3,
}

export type PistolInstance = {
	Tool: Tool,
	MainDump: any,
	Destroy: (self: PistolInstance) -> (),
}

export type SniperInstance = {
	Tool: Tool,
	MainDump: any,
	Destroy: (self: SniperInstance) -> (),
}

-- Return

return Types


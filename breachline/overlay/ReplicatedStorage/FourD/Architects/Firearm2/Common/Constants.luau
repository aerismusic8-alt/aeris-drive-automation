--[[
	File: Constants.luau
]]--

-- Root

local Constants = {}

-- Debug & Logging

-- Enables vprint/vwarn output across Firearm2 modules.
Constants.VERBOSE_LOGGING = true
-- Toggles render of raycast/projectile debug parts in workspace.
Constants.DEBUG_VISUALIZER = false
-- Cap on simultaneous debug parts to prevent runaway part allocation.
Constants.DEBUG_VISUALIZER_MAX_PARTS = 25

-- Camera & Aiming

-- Studs the OTS (over-the-shoulder) camera sits behind character when hipfiring.
Constants.OTS_ZOOM_DISTANCE = 9
-- Multiplier applied to OTS_ZOOM_DISTANCE while aiming down sights.
Constants.OTS_ADS_DISTANCE_MULT = 0.85
-- FOV scaler applied while aiming down sights in default (non-scoped) mode.
Constants.OTS_ADS_FOV_MULT = 0.85
-- Zoom multiplier applied while aiming through a scope (e.g. 2.5 = 2.5x zoom).
Constants.SCOPE_ZOOM = 3
-- Zoom multiplier applied when the scope control is held on a weapon that has
-- no optic of its own. Smaller than SCOPE_ZOOM, and enough to make an
-- iron-sight carbine usable at range on a phone.
Constants.SCOPE_ZOOM_OTS = 1.6
-- Seconds for scope shroud (peripheral blackout) to fade out on un-aim.
Constants.SCOPE_SHROUD_FADE_OUT_TIME = 0.1
-- Name of the shroud child Frame inside the scope GUI template.
Constants.SCOPE_SHROUD_NAME = "Shroud"
-- Name of the inner holder frame inside the scope GUI template.
Constants.SCOPE_HOLDER_NAME = "Holder"
-- Default OTS offset (right, up, forward) relative to character root.
Constants.DEFAULT_SHOULDER_OFFSET = Vector3.new(2, 0.5, 0)
-- Max upward/downward torso aim pitch in radians (clamps look angle).
Constants.PITCH_LIMIT_RAD = math.rad(80)

-- Aim Modes

-- Hipfire / OTS aiming mode identifier.
Constants.AIM_MODE_DEFAULT = "default"
-- Scoped aiming mode identifier (uses scope GUI + tighter FOV).
Constants.AIM_MODE_SCOPE = "scope"

-- Ballistics & Spread

-- Studs at which spread cone projects to compute hit deviation.
Constants.CONE_ENGAGEMENT_DISTANCE = 50
-- Lerp rate for movement-based spread multiplier (higher = snappier).
Constants.SPREAD_MOVE_LERP_RATE = 6
-- Threshold below which character is considered stationary for spread calc.
Constants.MIN_AIM_SPEED = 0.0001
-- Max raycast length used for hitscan resolution.
Constants.AMMO_RAYCAST_DISTANCE = 1000
-- Default projectile travel speed (studs/sec) for non-hitscan rounds.
Constants.PROJECTILE_SPEED = 900

-- Shot Validation

-- Server-side max angle delta (degrees) between client-reported and recomputed shot direction.
Constants.SHOT_VALIDATION_ANGLE_TOLERANCE_DEG = 0.5
-- Server-side max distance delta (studs) between client-reported and recomputed hit point.
Constants.SHOT_VALIDATION_DISTANCE_TOLERANCE = 2

-- Tags

-- CollectionService tag marking instances eligible for damage from this weapon system.
Constants.WEAPONS_SYSTEM_DAMAGEABLE_TAG = "WeaponsSystemDamageable"
-- CollectionService tag identifying tools driven by the Firearm2 architect.
Constants.FIREARM2_TAG = "Firearm2"

-- Asset Paths

-- Folder path (joined under ReplicatedStorage) to the crosshair GUI template.
Constants.CROSSHAIR_TEMPLATE_PATH = { "Assets", "UI", "FirearmCrosshair" }
-- Folder path (joined under ReplicatedStorage) to the scope GUI template.
Constants.SCOPE_TEMPLATE_PATH = { "Assets", "UI", "Scope" }
-- Folder path (joined under ReplicatedStorage) to the muzzle flash BillboardGui template.
Constants.FLASH_TEMPLATE_PATH = { "Assets", "UI", "Flash" }
-- Folder path (joined under ReplicatedStorage) to the ammo HUD ScreenGui template.
Constants.AMMO_HUD_TEMPLATE_PATH = { "Assets", "UI", "FirearmAmmo" }
-- Name of the TextLabel inside the ammo HUD that displays current/max ammo.
Constants.AMMO_HUD_LABEL_NAME = "AmmoLabel"

-- Muzzle Flash

-- Seconds the muzzle flash light + billboard remain visible per shot.
Constants.MUZZLE_FLASH_DURATION = 0.03
-- Name assigned to the rigged PointLight under ShotOrigin.
Constants.MUZZLE_FLASH_LIGHT_NAME = "MuzzleFlashLight"
-- Name assigned to the cloned BillboardGui under ShotOrigin.
Constants.MUZZLE_FLASH_BILLBOARD_NAME = "MuzzleFlash"
-- Name of the ImageLabel inside the flash BillboardGui that gets a random rotation per shot.
Constants.MUZZLE_FLASH_TEXTURE_NAME = "Texture"
-- PointLight Brightness applied while the flash is active.
Constants.MUZZLE_FLASH_LIGHT_BRIGHTNESS = 1
-- PointLight Range (studs) applied while the flash is active.
Constants.MUZZLE_FLASH_LIGHT_RANGE = 10
-- PointLight Color (white-yellow).
Constants.MUZZLE_FLASH_LIGHT_COLOR = Color3.fromRGB(252, 244, 141)

-- Rig & Animation

-- Required name for the firearm's primary body MeshPart/Part.
Constants.BODY_PART_NAME = "Body"
-- Attachment name on firearm marking left-hand IK target.
Constants.LEFT_HAND_GRIP_NAME = "LeftHandGrip"
-- Attachment name on firearm marking right-hand IK target.
Constants.RIGHT_HAND_GRIP_NAME = "RightHandGrip"
-- IKControl instance name created for the character's left hand.
Constants.IK_CONTROL_NAME = "Firearm2_LeftHandIK"
-- IKControl instance name created for the character's right hand.
Constants.RIGHT_HAND_IK_CONTROL_NAME = "Firearm2_RightHandIK"
-- Weld name pinning firearm body to character's right hand attachment.
Constants.HOLD_WELD_NAME = "Firearm2_HoldWeld"
-- IKControl Weight value (1 = full IK influence).
Constants.IK_WEIGHT = 1
-- IKControl SmoothTime in seconds (0 = instant snap to target).
Constants.IK_SMOOTH_TIME = 0
-- AnimationTrack weight applied to the idle hold-pose overlay.
Constants.HOLD_OVERLAY_IDLE_STRENGTH = 1

-- Param Schema

-- Whitelist of replicated tunable param keys recognized by client + server.
Constants.PARAM_KEYS = {
	"AimMode",
	"AimSpeed",
	"AmmoMagSize",
	"AmmoReloadTime",
	"AmmoReloadEmptyTime",
	"AmmoReloadType",
	"DamagePerRound",
	"FireRate",
	"FireType",
	"BaseSpread",
	"MaxSpread",
	"MoveSpreadMult",
	"SpreadPerShot",
	"SpreadRecovery",
	"MaxDistance",
	"ShoulderOffset",
	"HoldCFrame",
	"RecoilVertical",
	"RecoilHorizontal",
	"RecoilRecovery",
	"RecoilMaxAccum",
	"RecoilAdsMult",
}

-- Default Params

-- Fallback param values used when a SubType / capability omits a key.
Constants.DEFAULT_PARAMS = {
	AimMode = "default",
	AimSpeed = 0.1,
	AmmoMagSize = 10,
	AmmoReloadTime = 1,
	AmmoReloadEmptyTime = 0.1,
	AmmoReloadType = "magazine",
	DamagePerRound = 30,
	FireRate = 3,
	FireType = "semi",
	BaseSpread = 3,
	MaxSpread = 50,
	MoveSpreadMult = 2,
	SpreadPerShot = 2,
	SpreadRecovery = 6,
	MaxDistance = 200,
	ShoulderOffset = Vector3.new(2, 0.5, 0),
	RecoilVertical = 1.5,
	RecoilHorizontal = 0.5,
	RecoilRecovery = 8,
	RecoilMaxAccum = 10,
	RecoilAdsMult = 0.5,
}

-- Mobile

-- Look sensitivity multiplier applied on top of MouseDeltaSensitivity when the
-- input is a thumb rather than a mouse. A thumb drag across the look band is
-- shorter than a mouse sweep, so the raw delta is scaled up.
Constants.DEFAULT_TOUCH_SENSITIVITY = 1.15

-- Aim assist, touch only. Friction slows the look while the crosshair is near
-- a target; magnetism is a bounded pull toward it. Both are deliberately small
-- enough that a player who is already aiming straight is unaffected.
Constants.AIM_ASSIST_FOV_DEG = 8
Constants.AIM_ASSIST_RANGE = 200
Constants.AIM_ASSIST_MIN_FRICTION = 0.45
Constants.AIM_ASSIST_STRENGTH = 0.35
Constants.AIM_ASSIST_MAX_PULL_DEG = 2.5

-- Crouch. The flag rides on a player attribute so input and camera stay
-- decoupled; these are the eye height and walk speed that go with it.
Constants.CROUCH_ATTRIBUTE = "AXCrouch"
Constants.CROUCH_HEAD_OFFSET_Y = 0.6
Constants.CROUCH_WALK_SPEED = 8


-- Return

return Constants

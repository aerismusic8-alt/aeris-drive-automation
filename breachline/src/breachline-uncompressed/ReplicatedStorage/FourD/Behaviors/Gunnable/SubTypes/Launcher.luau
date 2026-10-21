--[[
	File: SubTypes/Launcher/init.luau

	Launcher SubType — fires a single explosive projectile (cannon ball / RPG)
	from a caller-supplied origin Attachment that fixes the shot position and
	angle.

	Unlike Turret/Hardpoint there is no input detection: the
	server fully simulates the projectile path up front, broadcasts one shot to
	all clients (each renders the projectile + explosion locally), and applies
	impact + explosion damage server-side at the calculated impact time.

	Driven entirely by the caller via `:Fire()`. The class instance is the
	handle returned by `Gunnable.newLauncher`.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local FourD = script:FindFirstAncestor("FourD")
local Common = script.Parent.Parent.Common
local Types = require(Common.Types)
local Trajectory = require(Common.Trajectory)
local CreateConfiguration = require(FourD.Common.createConfiguration)
local GetCharacterFromPart = require(FourD.Common.getCharacterFromPart)
local Dumpster = require(FourD.Libs.Dumpster)

local DEFAULT_IMPACT_DAMAGE = 100
local DEFAULT_FIRE_RATE = 0.5
local DEFAULT_EXPLOSION_RADIUS = 20
local DEFAULT_EXPLOSION_DAMAGE = 0
local DEFAULT_EXPLOSION_PRESSURE = 50000
local DEFAULT_PROJECTILE_SPEED = 400
local DEFAULT_PROJECTILE_RANGE = 2000
local DEFAULT_PROJECTILE_GRAVITY = 0
local IMPACT_RECHECK_DISTANCE = 4
local MAX_ORIGIN_TOLERANCE = 50
local TEMPLATE_FOLDER_NAME = "Gunnable_LauncherProjectiles"
local DAMAGEABLE_TAG = "WeaponsSystemDamageable"
local DEFAULT_AIM_VISUAL = "None"
local VALID_AIM_VISUALS = { None = true, Arc = true, Hud = true, Both = true }
local DEFAULT_AIM_ARC_SEGMENTS = 48
local DEFAULT_AIM_ARC_COLLISION_SEGMENTS = 12
local DEFAULT_AIM_ARC_WIDTH = 0.5
local DEFAULT_AIM_ARC_COLOR = Color3.new(1, 1, 1)
local DEFAULT_SMOKE_PARTICLE_COUNT = 30
local AIM_ARC_VIEWER_ATTR = "Gunnable_AimArcViewer"

local Launcher = {}
Launcher.__index = Launcher

export type Launcher = {
	Fire: (self: Launcher, originHint: Vector3?, directionHint: Vector3?) -> boolean,
	SetAimArcViewer: (self: Launcher, player: Player?) -> (),
	Destroy: (self: Launcher) -> (),
}

local function resolveDamageable(part: BasePart): Instance?
	local character = GetCharacterFromPart(part)
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return character
		end

		return nil
	end

	local ancestor: Instance? = part
	while ancestor and ancestor ~= workspace do
		if CollectionService:HasTag(ancestor, DAMAGEABLE_TAG) then
			return ancestor
		end

		ancestor = ancestor.Parent
	end

	return nil
end

local function applyDamage(entity: Instance, amount: number)
	if amount <= 0 then return end

	local humanoid = entity:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if humanoid.Health > 0 then
			humanoid:TakeDamage(amount)
		end

		return
	end

	local takeDamage = entity:FindFirstChild("TakeDamage")
	if takeDamage and takeDamage:IsA("BindableEvent") then
		takeDamage:Fire(amount)
	end
end

local function getTemplateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = TEMPLATE_FOLDER_NAME
	folder.Parent = ReplicatedStorage

	return folder
end

---Constructs a Launcher on `assembledModel`. `originAttachment` fixes the shot
---origin position and angle; `projectileTemplate` is the visual asset clients
---clone for each shot. Invalid numeric config raises an error.
---@return launcher -- Launcher handle (`:Fire()`, `:Destroy()`).
function Launcher.new(assembledModel: Model, originAttachment: Attachment, projectileTemplate: BasePart | Model, config: Types.LauncherConfig): Launcher
	assert(typeof(assembledModel) == "Instance" and assembledModel:IsA("Model"), "[Launcher] assembledModel must be a Model")
	assert(typeof(originAttachment) == "Instance" and originAttachment:IsA("Attachment"), "[Launcher] originAttachment must be an Attachment")
	assert(
		typeof(projectileTemplate) == "Instance" and (projectileTemplate:IsA("BasePart") or projectileTemplate:IsA("Model")),
		"[Launcher] projectileTemplate must be a BasePart or Model"
	)

	local impactDamage = config.ImpactDamage
	if impactDamage == nil then impactDamage = DEFAULT_IMPACT_DAMAGE end
	if impactDamage < 0 then error("[Launcher] ImpactDamage must be >= 0") end

	local fireRate = config.FireRate or DEFAULT_FIRE_RATE
	if fireRate <= 0 then error("[Launcher] FireRate must be > 0") end

	local explosionConfig = config.Explosion
	local explosionEnabled = explosionConfig ~= nil
	local explosionAffectsTerrain = false
	local explosionRadius = DEFAULT_EXPLOSION_RADIUS
	local explosionDamage = DEFAULT_EXPLOSION_DAMAGE
	local explosionPressure = DEFAULT_EXPLOSION_PRESSURE
	if explosionConfig then
		explosionAffectsTerrain = explosionConfig.AffectsTerrain == true
		explosionRadius = explosionConfig.Radius or DEFAULT_EXPLOSION_RADIUS
		if explosionRadius <= 0 then error("[Launcher] Explosion.Radius must be > 0") end
		explosionDamage = explosionConfig.Damage or DEFAULT_EXPLOSION_DAMAGE
		if explosionDamage < 0 then error("[Launcher] Explosion.Damage must be >= 0") end
		explosionPressure = explosionConfig.Pressure or DEFAULT_EXPLOSION_PRESSURE
	end

	local projectileConfig = config.Projectile
	local projectileSpeed = DEFAULT_PROJECTILE_SPEED
	local projectileRange = DEFAULT_PROJECTILE_RANGE
	local projectileGravity = DEFAULT_PROJECTILE_GRAVITY
	if projectileConfig then
		projectileSpeed = projectileConfig.Speed or DEFAULT_PROJECTILE_SPEED
		projectileRange = projectileConfig.Range or DEFAULT_PROJECTILE_RANGE
		projectileGravity = projectileConfig.Gravity or DEFAULT_PROJECTILE_GRAVITY
	end

	local projectileSize = if projectileTemplate:IsA("BasePart")
		then projectileTemplate.Size
		else projectileTemplate:GetExtentsSize()
	local projectileRadius = math.max(projectileSize.X, projectileSize.Y, projectileSize.Z) / 2

	local aimVisual = config.AimVisual or DEFAULT_AIM_VISUAL
	if not VALID_AIM_VISUALS[aimVisual] then
		error(`[Launcher] AimVisual must be one of "None", "Arc", "Hud", "Both" (got "{aimVisual}")`)
	end

	local aimArcEnabled = aimVisual == "Arc" or aimVisual == "Both"
	local reticleEnabled = aimVisual == "Hud" or aimVisual == "Both"

	local reticleConfig = config.Reticle
	local reticleLerp = reticleConfig ~= nil and reticleConfig.Lerp == true

	local aimArcConfig = config.AimArc
	local aimArcSegments = DEFAULT_AIM_ARC_SEGMENTS
	local aimArcCollisionSegments = DEFAULT_AIM_ARC_COLLISION_SEGMENTS
	local aimArcWidth = DEFAULT_AIM_ARC_WIDTH
	local aimArcColor = DEFAULT_AIM_ARC_COLOR
	if aimArcConfig then
		aimArcSegments = aimArcConfig.Segments or DEFAULT_AIM_ARC_SEGMENTS
		if aimArcSegments < 2 then error("[Launcher] AimArc.Segments must be >= 2") end
		aimArcCollisionSegments = aimArcConfig.CollisionSegments or DEFAULT_AIM_ARC_COLLISION_SEGMENTS
		if aimArcCollisionSegments < 1 then error("[Launcher] AimArc.CollisionSegments must be >= 1") end
		aimArcWidth = aimArcConfig.Width or DEFAULT_AIM_ARC_WIDTH
		if aimArcWidth <= 0 then error("[Launcher] AimArc.Width must be > 0") end
		aimArcColor = aimArcConfig.Color or DEFAULT_AIM_ARC_COLOR
	end

	local smokeConfig = config.Smoke
	local smokeEnabled = smokeConfig ~= nil
	local smokeAssetName = ""
	local smokeParticleCount = DEFAULT_SMOKE_PARTICLE_COUNT
	if smokeConfig then
		smokeAssetName = smokeConfig.AssetName
		if smokeAssetName == nil or smokeAssetName == "" then error("[Launcher] Smoke.AssetName must be provided") end
		smokeParticleCount = smokeConfig.ParticleCount or DEFAULT_SMOKE_PARTICLE_COUNT
		if smokeParticleCount <= 0 then error("[Launcher] Smoke.ParticleCount must be > 0") end
	end

	CreateConfiguration(assembledModel, {
		impactDamage = impactDamage,
		fireRate = fireRate,
		explosionEnabled = explosionEnabled,
		explosionAffectsTerrain = explosionAffectsTerrain,
		explosionRadius = explosionRadius,
		explosionDamage = explosionDamage,
		explosionPressure = explosionPressure,
		projectileSpeed = projectileSpeed,
		projectileRange = projectileRange,
		projectileGravity = projectileGravity,
		aimVisual = aimVisual,
		aimArcEnabled = aimArcEnabled,
		reticleEnabled = reticleEnabled,
		reticleLerp = reticleLerp,
		aimArcSegments = aimArcSegments,
		aimArcCollisionSegments = aimArcCollisionSegments,
		aimArcWidth = aimArcWidth,
		aimArcColor = Vector3.new(aimArcColor.R, aimArcColor.G, aimArcColor.B),
		smokeEnabled = smokeEnabled,
		smokeAssetName = smokeAssetName,
		smokeParticleCount = smokeParticleCount,
	}, "GunnableLauncherConfig")

	local self = setmetatable({}, Launcher)

	self._dumpster = Dumpster.new()
	self._model = assembledModel
	self._originAttachment = originAttachment
	self._fireRate = fireRate
	self._impactDamage = impactDamage
	self._explosionEnabled = explosionEnabled
	self._explosionAffectsTerrain = explosionAffectsTerrain
	self._explosionRadius = explosionRadius
	self._explosionDamage = explosionDamage
	self._explosionPressure = explosionPressure
	self._projectileSpeed = projectileSpeed
	self._projectileRange = projectileRange
	self._projectileGravity = projectileGravity
	self._projectileRadius = projectileRadius
	self._aimArcEnabled = aimArcEnabled
	self._reticleEnabled = reticleEnabled
	self._lastFireTime = 0

	if aimArcEnabled or reticleEnabled then
		assembledModel:SetAttribute(AIM_ARC_VIEWER_ATTR, 0)
	end

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { assembledModel }
	self._castParams = castParams

	local originRef = Instance.new("ObjectValue")
	originRef.Name = "Gunnable_LauncherOrigin"
	originRef.Value = originAttachment
	originRef.Parent = assembledModel

	local templateClone = projectileTemplate:Clone()
	templateClone.Name = assembledModel.Name .. "_LauncherProjectile"
	templateClone.Parent = getTemplateFolder()
	self._dumpster:Add(templateClone)

	local projectileRef = Instance.new("ObjectValue")
	projectileRef.Name = "Gunnable_LauncherProjectile"
	projectileRef.Value = templateClone
	projectileRef.Parent = assembledModel

	local shotEvent = Instance.new("RemoteEvent")
	shotEvent.Name = "LauncherShot"
	shotEvent.Parent = assembledModel
	self._shotEvent = shotEvent

	local clientScript = script:FindFirstChild("LauncherClient")
	if clientScript then
		local clone = clientScript:Clone()
		if clone:IsA("BaseScript") then
			clone.Enabled = true
		end
		clone.Parent = assembledModel
	end

	self._dumpster:AttachTo(assembledModel)

	return self
end

---Rebuilds a Launcher at Play from the state `Launcher.new` persisted at edit
---time, without re-cloning the projectile template, re-creating the LauncherShot
---event, or re-writing the config. `Launcher.new` runs inside the edit-time
---compiler's `bind()`, so the object it returns -- and the fire connection a bound
---turret makes on it -- is gone by Play. A server component calls this to get the
---same object back (reusing `Fire`/`_onImpact`) and reconnect firing. Returns nil
---if the persisted launcher state is missing or malformed.
function Launcher.rehydrate(assembledModel: Model): Launcher?
	if typeof(assembledModel) ~= "Instance" or not assembledModel:IsA("Model") then return nil end
	local configFolder = assembledModel:FindFirstChild("GunnableLauncherConfig")
	local originRef = assembledModel:FindFirstChild("Gunnable_LauncherOrigin")
	local projectileRef = assembledModel:FindFirstChild("Gunnable_LauncherProjectile")
	local shotEvent = assembledModel:FindFirstChild("LauncherShot")
	if not (configFolder and originRef and originRef:IsA("ObjectValue") and projectileRef and projectileRef:IsA("ObjectValue") and shotEvent and shotEvent:IsA("RemoteEvent")) then
		return nil
	end

	local originAttachment = originRef.Value
	local projectileTemplate = projectileRef.Value
	if not (originAttachment and originAttachment:IsA("Attachment")) then return nil end
	if not (projectileTemplate and (projectileTemplate:IsA("BasePart") or projectileTemplate:IsA("Model"))) then return nil end

	local function num(name: string, default: number): number
		local value = configFolder:FindFirstChild(name)
		return if value and value:IsA("NumberValue") then value.Value else default
	end
	local function flag(name: string): boolean
		local value = configFolder:FindFirstChild(name)
		return value ~= nil and value:IsA("BoolValue") and value.Value == true
	end

	local projectileSize = if projectileTemplate:IsA("BasePart")
		then projectileTemplate.Size
		else (projectileTemplate :: Model):GetExtentsSize()
	local projectileRadius = math.max(projectileSize.X, projectileSize.Y, projectileSize.Z) / 2

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { assembledModel }

	local self = setmetatable({}, Launcher)
	self._dumpster = Dumpster.new()
	self._model = assembledModel
	self._originAttachment = originAttachment
	self._fireRate = num("fireRate", DEFAULT_FIRE_RATE)
	self._impactDamage = num("impactDamage", DEFAULT_IMPACT_DAMAGE)
	self._explosionEnabled = flag("explosionEnabled")
	self._explosionAffectsTerrain = flag("explosionAffectsTerrain")
	self._explosionRadius = num("explosionRadius", DEFAULT_EXPLOSION_RADIUS)
	self._explosionDamage = num("explosionDamage", DEFAULT_EXPLOSION_DAMAGE)
	self._explosionPressure = num("explosionPressure", DEFAULT_EXPLOSION_PRESSURE)
	self._projectileSpeed = num("projectileSpeed", DEFAULT_PROJECTILE_SPEED)
	self._projectileRange = num("projectileRange", DEFAULT_PROJECTILE_RANGE)
	self._projectileGravity = num("projectileGravity", DEFAULT_PROJECTILE_GRAVITY)
	self._projectileRadius = projectileRadius
	self._aimArcEnabled = flag("aimArcEnabled")
	self._reticleEnabled = flag("reticleEnabled")
	self._castParams = castParams
	self._shotEvent = shotEvent
	self._lastFireTime = 0
	self._dumpster:AttachTo(assembledModel)

	return self
end

function Launcher:_applyExplosionDamage(center: Vector3)
	if self._explosionDamage <= 0 then return end

	local radius = self._explosionRadius
	local damaged: { [Instance]: boolean } = {}

	for _, part in workspace:GetPartBoundsInRadius(center, radius) do
		local entity = resolveDamageable(part)
		if not entity or damaged[entity] then continue end
		damaged[entity] = true

		local distance = (entity:GetPivot().Position - center).Magnitude
		local falloff = math.clamp(1 - distance / radius, 0, 1)
		applyDamage(entity, self._explosionDamage * falloff)
	end
end

function Launcher:_onImpact(direction: Vector3, gravity: number, impactPoint: Vector3, travelTime: number)
	local model = self._model
	if not model.Parent then return end

	if self._impactDamage > 0 then
		local velocity = Trajectory.velocityAt(direction, self._projectileSpeed, gravity, travelTime)
		local approach = if velocity.Magnitude > 1e-5 then velocity.Unit else direction
		local rayStart = impactPoint - approach * IMPACT_RECHECK_DISTANCE
		local recheck = approach * (IMPACT_RECHECK_DISTANCE * 2)
		local result = if self._projectileRadius > 0
			then workspace:Spherecast(rayStart, self._projectileRadius, recheck, self._castParams)
			else workspace:Raycast(rayStart, recheck, self._castParams)
		if result and result.Instance then
			local entity = resolveDamageable(result.Instance)
			if entity then
				applyDamage(entity, self._impactDamage)
			end
		end
	end

	if self._explosionEnabled then
		local explosion = Instance.new("Explosion")
		explosion.Position = impactPoint
		explosion.BlastRadius = self._explosionRadius
		explosion.BlastPressure = self._explosionPressure
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = if self._explosionAffectsTerrain
			then Enum.ExplosionType.Craters
			else Enum.ExplosionType.NoCraters
		explosion.Visible = false
		explosion.Parent = workspace

		self:_applyExplosionDamage(impactPoint)
	end
end

---Launches a projectile. Returns `false` if the model was destroyed or the
---`1 / FireRate` cooldown has not elapsed; otherwise `true`.
---Optional origin/direction hints let a caller (e.g. a bound turret relaying
---the shooter's client-side barrel ray) override the server-side attachment;
---the origin must be within 50 studs of the attachment or the hints are ignored.
function Launcher:Fire(originHint: Vector3?, directionHint: Vector3?): boolean
	local model = self._model
	if not model.Parent then return false end

	local now = os.clock()
	if now - self._lastFireTime < (1 / self._fireRate) then
		return false
	end
	self._lastFireTime = now

	local originCFrame = self._originAttachment.WorldCFrame
	local origin = originCFrame.Position
	local direction = originCFrame.LookVector

	if typeof(originHint) == "Vector3" and typeof(directionHint) == "Vector3"
		and directionHint.Magnitude > 1e-3
		and (originHint - origin).Magnitude <= MAX_ORIGIN_TOLERANCE then
		origin = originHint
		direction = directionHint.Unit
	end

	local gravity = math.max(self._projectileGravity, 0)

	local impact = Trajectory.solveImpact(
		origin,
		direction,
		self._projectileSpeed,
		gravity,
		self._projectileRange,
		self._castParams,
		self._projectileRadius
	)

	self._shotEvent:FireAllClients({
		Origin = origin,
		Direction = direction,
		Speed = self._projectileSpeed,
		Gravity = gravity,
		ImpactPoint = impact.ImpactPoint,
		ImpactTime = workspace:GetServerTimeNow() + impact.TravelTime,
		TravelTime = impact.TravelTime,
		Expired = impact.Expired,
	})

	if not impact.Expired then
		task.delay(impact.TravelTime, function()
			self:_onImpact(direction, gravity, impact.ImpactPoint, impact.TravelTime)
		end)
	end

	return true
end

---Designates which player's client should render the aim visuals (trajectory
---arc and/or screen reticle, per AimVisual). Pass `nil` to hide them for
---everyone. No-op when AimVisual is "None".
function Launcher:SetAimArcViewer(player: Player?)
	if not self._aimArcEnabled and not self._reticleEnabled then return end

	local model = self._model
	if not model.Parent then return end

	model:SetAttribute(AIM_ARC_VIEWER_ATTR, if player then player.UserId else 0)
end

---Tears down the Launcher: destroys the replicated projectile template and
---freezes the instance.
function Launcher:Destroy()
	assert(table.isfrozen(self) == false, "[Launcher] cannot destroy an already-destroyed Launcher")
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
end

return Launcher

--[[
	File: Common/FireServer.luau

	Shared server-side firing module for Turret + Hardpoint. Resolves each
	shot deterministically via Common/Trajectory (gravity = 0 hitscan),
	broadcasts one TracerShot payload per fired barrel to all clients (each
	renders a local cosmetic bullet via Common/TracerRender), and schedules
	damage at ImpactTime via task.delay + re-raycast. No server-side
	moving parts -- visuals are client-rendered.

	SubType variants supply muzzle attachments, authorization, and the
	per-rig TracerShot UnreliableRemoteEvent.
]]--

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Common = script.Parent

local MuzzleFlashFx = require(FourD:WaitForChild("Common"):WaitForChild("MuzzleFlashFx"))
local GetCharacterFromPart = require(FourD.Common:WaitForChild("getCharacterFromPart"))
local Trajectory = require(Common:WaitForChild("Trajectory"))
local Reload = require(Common:WaitForChild("Reload"))

local MAX_TOL = 50
local IMPACT_RECHECK_DISTANCE = 4
local DAMAGEABLE_TAG = "WeaponsSystemDamageable"

export type FireSequence = "Simultaneous" | "Cycled"

export type BindOptions = {
	FireEvent: RemoteEvent,
	TracerEvent: UnreliableRemoteEvent,
	MuzzleAttachments: { Attachment },
	GetOrigin: ((att: Attachment) -> Vector3)?,
	GetDirection: ((att: Attachment) -> Vector3)?,
	IsAuthorizedPlayer: (player: Player) -> boolean,
	UseClientHints: (boolean | () -> boolean)?,
	FireSequence: FireSequence?,
	RateMultiplier: number?,
}

local FireServer = {}

local function getConfigValue(configFolder: Instance?, name: string, default: any): any
	if configFolder then
		local val = configFolder:FindFirstChild(name)
		if val then return val.Value end
	end

	return default
end

local function defaultGetOrigin(att: Attachment): Vector3
	return att.WorldCFrame.Position
end

local function defaultGetDirection(att: Attachment): Vector3
	return att.WorldCFrame.LookVector
end

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

function FireServer.bind(model: Model, opts: BindOptions)
	local muzzleAttachments = opts.MuzzleAttachments
	assert(muzzleAttachments and #muzzleAttachments > 0,
		"[Gunnable] FireServer.bind requires MuzzleAttachments with at least one Attachment")
	assert(opts.TracerEvent and opts.TracerEvent:IsA("UnreliableRemoteEvent"),
		"[Gunnable] FireServer.bind requires a TracerEvent UnreliableRemoteEvent")

	local configFolder = model:FindFirstChild("GunnableHardpointConfig")
	local tracerColor: Color3? = getConfigValue(configFolder, "tracerColor", nil)
	local projName = getConfigValue(configFolder, "projectileName", "")
	local projectileSource: Instance? = nil
	if projName ~= "" then
		local pf = FourD:FindFirstChild("Projectiles")
		if pf then projectileSource = pf:FindFirstChild(projName) end
	end

	local function getProjAttr(name: string, default: any): any
		if projectileSource and projectileSource:GetAttribute(name) ~= nil then
			return projectileSource:GetAttribute(name)
		end

		return default
	end

	local damage = getProjAttr("ProjectileDamage", getConfigValue(configFolder, "gunDamage", 30))
	local speed = getProjAttr("ProjectileSpeed", getConfigValue(configFolder, "projectileSpeed", 200))
	local projectileCatchUp = getConfigValue(configFolder, "projectileCatchUp", true)
	local projectileGravity = getConfigValue(configFolder, "projectileGravity", 0)
	local maxDist = getConfigValue(configFolder, "gunRange", 200)
	local fireRate = getConfigValue(configFolder, "gunFireRate", 600)
	local rateMultiplier = math.max(1, opts.RateMultiplier or 1)
	local fireInterval = 60 / (fireRate * rateMultiplier)
	local spreadDeg = getConfigValue(configFolder, "spread", 0)
	local spreadRad = math.rad(spreadDeg)

	local getOrigin = opts.GetOrigin or defaultGetOrigin
	local getDirection = opts.GetDirection or defaultGetDirection
	local fireSequence = opts.FireSequence or getConfigValue(configFolder, "fireSequence", "Simultaneous")
	local cycleIdx = 1

	local useClientHintsOpt = opts.UseClientHints
	local function shouldUseClientHints(): boolean
		if typeof(useClientHintsOpt) == "function" then
			return useClientHintsOpt()
		end

		return useClientHintsOpt ~= false
	end

	local function applySpread(direction: Vector3): Vector3
		if spreadRad <= 0 then return direction end
		if direction.Magnitude < 1e-5 then return direction end

		local cosHalf = math.cos(spreadRad)
		local u = cosHalf + (1 - cosHalf) * math.random()
		local sinT = math.sqrt(math.max(0, 1 - u * u))
		local phi = 2 * math.pi * math.random()
		local localOffset = Vector3.new(sinT * math.cos(phi), sinT * math.sin(phi), -u)

		local aimCF = CFrame.lookAt(Vector3.zero, direction.Unit)
		return aimCF:VectorToWorldSpace(localOffset)
	end

	local fireParams = RaycastParams.new()
	fireParams.FilterType = Enum.RaycastFilterType.Exclude

	local function fireBarrel(att: Attachment, player: Player, clientOrigin: Vector3?, clientDirection: Vector3?, char: Instance?)
		local serverOrigin = getOrigin(att)
		local serverDirection = getDirection(att)

		local origin: Vector3
		local direction: Vector3
		if shouldUseClientHints() and typeof(clientOrigin) == "Vector3" and typeof(clientDirection) == "Vector3" then
			if (clientOrigin - serverOrigin).Magnitude <= MAX_TOL then
				origin = clientOrigin
				direction = clientDirection.Unit
			else
				origin = serverOrigin
				direction = serverDirection
			end
		else
			origin = serverOrigin
			direction = serverDirection
		end

		direction = applySpread(direction)

		local effectiveSpeed = speed
		if projectileCatchUp then
			local sourcePart = att.Parent
			if sourcePart and sourcePart:IsA("BasePart") then
				local along = sourcePart.AssemblyLinearVelocity:Dot(direction)
				if along > 0 then
					effectiveSpeed += along
				end
			end
		end

		fireParams.FilterDescendantsInstances = if char then { model, char } else { model }

		MuzzleFlashFx.fire(att, player, tracerColor)

		local gravity = if projectileGravity > 0 then workspace.Gravity * projectileGravity else 0

		local impact = Trajectory.solveImpact(origin, direction, effectiveSpeed, gravity, maxDist, fireParams)

		opts.TracerEvent:FireAllClients({
			Origin = origin,
			Direction = direction,
			Speed = effectiveSpeed,
			Gravity = gravity,
			ImpactPoint = impact.ImpactPoint,
			ImpactTime = workspace:GetServerTimeNow() + impact.TravelTime,
			TravelTime = impact.TravelTime,
			Expired = impact.Expired,
		})

		if not impact.Expired and damage > 0 then
			task.delay(impact.TravelTime, function()
				if not model.Parent then return end

				local approachVelocity = Trajectory.velocityAt(direction, effectiveSpeed, gravity, impact.TravelTime)
				local approach = if approachVelocity.Magnitude > 1e-5 then approachVelocity.Unit else direction
				local rayStart = impact.ImpactPoint - approach * IMPACT_RECHECK_DISTANCE
				local result = workspace:Raycast(rayStart, approach * (IMPACT_RECHECK_DISTANCE * 2), fireParams)
				if result and result.Instance then
					local entity = resolveDamageable(result.Instance)
					if entity then
						applyDamage(entity, damage)
					end
				end
			end)
		end
	end

	local lastFireTime: { [Player]: number } = {}

	opts.FireEvent.OnServerEvent:Connect(function(player: Player, clientOrigin: Vector3?, clientDirection: Vector3?)
		if not opts.IsAuthorizedPlayer(player) then return end

		local now = tick()
		if lastFireTime[player] and (now - lastFireTime[player]) < fireInterval then return end
		lastFireTime[player] = now

		local char = player.Character

		if fireSequence == "Cycled" then
			if not Reload.tryConsume(model) then return end

			local att = muzzleAttachments[cycleIdx]
			cycleIdx = (cycleIdx % #muzzleAttachments) + 1
			if att then
				fireBarrel(att, player, clientOrigin, clientDirection, char)
			end
		else
			for _, att in ipairs(muzzleAttachments) do
				if not Reload.tryConsume(model) then break end
				fireBarrel(att, player, clientOrigin, clientDirection, char)
			end
		end
	end)

	local playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		lastFireTime[player] = nil
	end)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			playerRemovingConn:Disconnect()
		end
	end)
end

return FireServer
	
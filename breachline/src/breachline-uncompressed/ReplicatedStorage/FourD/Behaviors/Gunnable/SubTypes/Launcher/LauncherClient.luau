-- GENERATED WRAPPER around upstream LauncherClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: SubTypes/Launcher/LauncherClient.server.luau

	Client render script for the Launcher SubType. Runs as a Script with
	RunContext = Client (see LauncherClient.meta.json) because a LocalScript
	would not execute when parented to a Workspace model.

	Purely visual: no input, no authorization. Listens for LauncherShot
	broadcasts, clones the projectile template, animates it along the shared
	deterministic parabola timed off the server clock, and plays a cosmetic
	explosion on impact.

	Also drives the aim visuals selected by AimVisual: the trajectory arc, the
	screen reticle, or both. Both read one AimArc solve, so "Hud" builds a hidden
	arc purely as the solver.
]]--

if not script.Parent:IsA("Model") then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local GunnableCommon = ReplicatedStorage.FourD.Behaviors.Gunnable.Common
local Trajectory = require(GunnableCommon.Trajectory)
local AimArc = require(GunnableCommon.AimArc)
local AimReticle = require(GunnableCommon.AimReticle)
local ReplicationReady = require(GunnableCommon.ReplicationReady)

local AIM_ARC_VIEWER_ATTR = "Gunnable_AimArcViewer"
local SMOKE_VFX_PATH = { "Assets", "VFX" }
local SMOKE_CLEANUP_SECONDS = 5

local model = script.Parent

local shotEvent = model:WaitForChild("LauncherShot", 10)
local configFolder = model:WaitForChild("GunnableLauncherConfig", 10)
local projectileRef = model:WaitForChild("Gunnable_LauncherProjectile", 10)
local projectileTemplate = ReplicationReady.waitForObjectValue(model, "Gunnable_LauncherProjectile", "PVInstance")
local originAttachment = ReplicationReady.waitForObjectValue(model, "Gunnable_LauncherOrigin", "Attachment")

if not shotEvent or not configFolder or not projectileRef or not projectileTemplate or not originAttachment then
	warn("[LauncherClient] Replicated rig was not ready, aborting")
	return false
end

type ShotData = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Gravity: number,
	ImpactPoint: Vector3,
	ImpactTime: number,
	TravelTime: number,
	Expired: boolean,
}

local function getConfig(name: string, default: any): any
	local value = ReplicationReady.waitForChild(configFolder, name)
	if value then return value.Value end

	return default
end

local explosionEnabled = getConfig("explosionEnabled", false)
local explosionRadius = getConfig("explosionRadius", 20)

local smokeEnabled = getConfig("smokeEnabled", false)
local smokeAssetName = getConfig("smokeAssetName", "")
local smokeParticleCount = getConfig("smokeParticleCount", 30)

local smokeOriginAttachment: Attachment? = nil
local smokeTemplate: Instance? = nil

local function resolveSmokeTemplate(): Instance?
	local current: Instance = ReplicatedStorage
	for _, segment in SMOKE_VFX_PATH do
		local nextChild = current:FindFirstChild(segment)
		if not nextChild then return nil end
		current = nextChild
	end

	return current:FindFirstChild(smokeAssetName)
end

if smokeEnabled then
	if smokeAssetName == "" then
		smokeEnabled = false
	else
		smokeOriginAttachment = originAttachment

		smokeTemplate = resolveSmokeTemplate()
		if not smokeTemplate then
			warn(`[LauncherClient] Smoke asset "{smokeAssetName}" not found under Assets.VFX; skipping smoke`)
		end

		if not smokeOriginAttachment or not smokeTemplate then
			smokeEnabled = false
		end
	end
end

local function emitSmoke()
	if not smokeEnabled then return end

	local origin = smokeOriginAttachment
	local template = smokeTemplate
	if not origin or not template then return end

	local clone = template:Clone()
	clone.Parent = origin
	if clone:IsA("ParticleEmitter") then
		clone.Enabled = false
		clone:Emit(smokeParticleCount)
	end

	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			descendant:Emit(smokeParticleCount)
		end
	end

	Debris:AddItem(clone, SMOKE_CLEANUP_SECONDS)
end

local renderFolder = Instance.new("Folder")
renderFolder.Name = model.Name .. "_LauncherProjectiles"
renderFolder.Parent = Workspace

local function makeInert(projectile: PVInstance)
	local parts: { BasePart } = {}
	if projectile:IsA("BasePart") then
		table.insert(parts, projectile)
	end

	for _, descendant in projectile:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
end

local function playExplosion(position: Vector3)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = explosionRadius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Visible = true
	explosion.Parent = Workspace
end

local function renderShot(shot: ShotData)
	emitSmoke()

	local template = projectileTemplate

	local projectile = template:Clone()
	makeInert(projectile)
	projectile:PivotTo(CFrame.new(shot.Origin))
	projectile.Parent = renderFolder

	local launchTime = shot.ImpactTime - shot.TravelTime

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not projectile.Parent then
			connection:Disconnect()
			return
		end

		local elapsed = Workspace:GetServerTimeNow() - launchTime
		if elapsed >= shot.TravelTime then
			connection:Disconnect()
			projectile:Destroy()
			if explosionEnabled and not shot.Expired then
				playExplosion(shot.ImpactPoint)
			end

			return
		end

		local position = Trajectory.positionAt(shot.Origin, shot.Direction, shot.Speed, shot.Gravity, elapsed)
		local velocity = Trajectory.velocityAt(shot.Direction, shot.Speed, shot.Gravity, elapsed)
		if velocity.Magnitude > 1e-4 then
			projectile:PivotTo(CFrame.lookAt(position, position + velocity))
		else
			projectile:PivotTo(CFrame.new(position))
		end
	end)
end

shotEvent.OnClientEvent:Connect(renderShot)

model.Destroying:Connect(function()
	renderFolder:Destroy()
end)

local aimArcEnabled = getConfig("aimArcEnabled", false)
local reticleEnabled = getConfig("reticleEnabled", false)

local function hardpointHudActive(): boolean
	local hardpointConfig = model:FindFirstChild("GunnableHardpointConfig")
	local enabledValue = hardpointConfig and hardpointConfig:FindFirstChild("aimHudEnabled")
	return enabledValue ~= nil and enabledValue.Value == true
end

if reticleEnabled and hardpointHudActive() then
	reticleEnabled = false
end

if aimArcEnabled or reticleEnabled then
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local arc: AimArc.AimArc? = nil
		local reticle: AimReticle.AimReticle? = nil
		local renderConnection: RBXScriptConnection? = nil

		local function buildArc(): AimArc.AimArc?
			local gravity = math.max(getConfig("projectileGravity", 0), 0)
			local colorVector = getConfig("aimArcColor", Vector3.one)

			local castParams = RaycastParams.new()
			castParams.FilterType = Enum.RaycastFilterType.Exclude
			castParams.FilterDescendantsInstances = { model, localPlayer.Character }

			return AimArc.new(originAttachment, {
				Speed = getConfig("projectileSpeed", 400),
				Gravity = gravity,
				Range = getConfig("projectileRange", 2000),
				Segments = getConfig("aimArcSegments", 48),
				CollisionSegments = getConfig("aimArcCollisionSegments", 12),
				Width = getConfig("aimArcWidth", 0.5),
				Color = Color3.new(colorVector.X, colorVector.Y, colorVector.Z),
				CastParams = castParams,
				Name = model.Name .. "_AimArc",
				Hidden = not aimArcEnabled,
			})
		end

		local function teardown()
			if renderConnection then
				renderConnection:Disconnect()
				renderConnection = nil
			end

			if reticle then
				reticle:Destroy()
				reticle = nil
			end

			if arc then
				arc:Destroy()
				arc = nil
			end
		end

		local function onRender(deltaTime: number)
			local activeArc = arc
			local activeReticle = reticle
			if not activeArc or not activeReticle then return end

			local impactPoint = activeArc:GetImpactPosition()
			if not impactPoint then
				activeReticle:Hide()
				return
			end

			if activeReticle:Update(impactPoint, deltaTime) then
				activeReticle:SetSpreadRadius(nil)
			end
		end

		local function refreshAimVisuals()
			local isViewer = model:GetAttribute(AIM_ARC_VIEWER_ATTR) == localPlayer.UserId
			if not isViewer then
				teardown()
				return
			end

			local activeArc = arc
			if not activeArc then
				activeArc = buildArc()
				if not activeArc then return end
				arc = activeArc
			end

			activeArc:SetEnabled(true)

			if not reticleEnabled then return end

			if not reticle then
				reticle = AimReticle.new({ Lerp = getConfig("reticleLerp", false) == true })
			end

			if not renderConnection then
				renderConnection = RunService.RenderStepped:Connect(onRender)
			end
		end

		model:GetAttributeChangedSignal(AIM_ARC_VIEWER_ATTR):Connect(refreshAimVisuals)
		refreshAimVisuals()

		model.Destroying:Connect(teardown)
	end
end

end

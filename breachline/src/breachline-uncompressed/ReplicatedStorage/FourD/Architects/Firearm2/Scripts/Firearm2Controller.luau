-- GENERATED WRAPPER around upstream Firearm2Controller.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: Firearm2Controller.server.luau
	RunContext: Client (see Firearm2Controller.meta.json)
]]--

if not script.Parent:IsA("Tool") then return end

-- Roblox Services

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if RunService:IsServer() then return end

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local ConeMath = require(Firearm2.Common.ConeMath)
local Constants = require(Firearm2.Common.Constants)
local Dumpster = require(FourD.Libs.Dumpster)
local MuzzleFlashFx = require(FourD.Common.MuzzleFlashFx)

-- Constants

local MOVE_THRESHOLD = 0.05
local PARAM_KEYS = Constants.PARAM_KEYS

-- Variables

local tool: Tool = script.Parent
local player = Players.LocalPlayer

local clientModulesFolder = tool:WaitForChild("ClientModules")
local ClientAmmoHud = require(clientModulesFolder:WaitForChild("ClientAmmoHud"))
local ClientCamera = require(clientModulesFolder:WaitForChild("ClientCamera"))
local ClientCrosshair = require(clientModulesFolder:WaitForChild("ClientCrosshair"))
local ClientInput = require(clientModulesFolder:WaitForChild("ClientInput"))
local ClientRecoilModel = require(clientModulesFolder:WaitForChild("ClientRecoilModel"))
local ClientSpreadModel = require(clientModulesFolder:WaitForChild("ClientSpreadModel"))

local remotes = tool:WaitForChild("Remotes")
local ammoChangedRemote = remotes:WaitForChild("AmmoChanged")
local fireRemote = remotes:WaitForChild("Fire")
local reloadAckRemote = remotes:WaitForChild("ReloadAck")
local reloadCancelRemote = remotes:WaitForChild("ReloadCancel")
local reloadRemote = remotes:WaitForChild("Reload")
local reloadStartedRemote = remotes:WaitForChild("ReloadStarted")
local shotReplicateRemote = remotes:WaitForChild("ShotReplicate")

local ammoHud = nil
local cameraController = nil
local crosshair = nil
local input = nil
local recoilModel = nil
local spreadModel = nil
local params: {[string]: any} = {}
local currentAmmo = 0
local isReloading = false
local clientLastFire = 0
local lifecycleDumpster = Dumpster.new()
local sessionDumpster = Dumpster.new()
local isEquipped = false
local scopeGui: ScreenGui? = nil
local scopeShroud: Frame? = nil
local scopeHolder: ImageLabel? = nil
local scopeFadeOutT = 0
local scopeAimReleased = false
local scopeHiddenParts: { [BasePart]: number } = {}
local muzzleFlashShotOrigin: Attachment? = nil

-- Local Functions

local function readParams()
	params = {}
	for _, key in PARAM_KEYS do
		params[key] = tool:GetAttribute(key)
	end

	if params.ShoulderOffset == nil then
		params.ShoulderOffset = Constants.DEFAULT_SHOULDER_OFFSET
	end
end

local function getIsMoving(): boolean
	local character = player.Character
	if not character then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	return humanoid.MoveDirection.Magnitude > MOVE_THRESHOLD
end

local function findRightHandGripAttachment(body: BasePart): Attachment?
	for _, descendant in body:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == Constants.RIGHT_HAND_GRIP_NAME then
			return descendant
		end
	end

	return nil
end

local function getRightHand(character: Model, humanoid: Humanoid): BasePart?
	local name = if humanoid.RigType == Enum.HumanoidRigType.R15 then "RightHand" else "Right Arm"
	local part = character:FindFirstChild(name)
	if part and part:IsA("BasePart") then return part end

	return nil
end

local function updateHoldOverlay()
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	local holdWeld = root:FindFirstChild(Constants.HOLD_WELD_NAME)
	if not holdWeld or not holdWeld:IsA("Motor6D") then return end

	local body = holdWeld.Part1
	if not body or not body:IsA("BasePart") then return end

	local rightHand = getRightHand(character, humanoid)
	if not rightHand then return end

	local grip = findRightHandGripAttachment(body)
	if not grip then return end

	local adsT = cameraController:GetAdsT()
	local idleAmount = (1 - adsT) * Constants.HOLD_OVERLAY_IDLE_STRENGTH
	if idleAmount <= 0 then
		holdWeld.Transform = CFrame.identity
		return
	end

	local gripLocalToBody = body.CFrame:Inverse() * grip.WorldCFrame
	local idleBodyWorld = rightHand.CFrame * gripLocalToBody:Inverse()
	local idleTransform = (root.CFrame * holdWeld.C0):Inverse() * idleBodyWorld
	holdWeld.Transform = CFrame.identity:Lerp(idleTransform, idleAmount)
end

local function spawnTracer(origin: Vector3, hitPos: Vector3)
	local totalDistance = (hitPos - origin).Magnitude
	if totalDistance < 0.1 then return end

	local direction = (hitPos - origin) / totalDistance

	local part = Instance.new("Part")
	part.Name = "Firearm2Tracer"
	part.Size = Vector3.new(0.3, 0.3, 0.3)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.CFrame = CFrame.lookAt(origin, origin + direction)

	local front = Instance.new("Attachment")
	front.Name = "Front"
	front.Position = Vector3.new(0, 0, -1.5)
	front.Parent = part

	local rear = Instance.new("Attachment")
	rear.Name = "Rear"
	rear.Position = Vector3.new(0, 0, 1.5)
	rear.Parent = part

	local tracerBeam = Instance.new("Beam")
	tracerBeam.Attachment0 = front
	tracerBeam.Attachment1 = rear
	tracerBeam.Texture = "rbxassetid://14364459325"
	tracerBeam.Color = ColorSequence.new(Color3.fromRGB(255, 200, 50))
	tracerBeam.Brightness = 5.225
	tracerBeam.LightEmission = 1
	tracerBeam.LightInfluence = 0
	tracerBeam.FaceCamera = true
	tracerBeam.Segments = 10
	tracerBeam.TextureLength = 10
	tracerBeam.TextureMode = Enum.TextureMode.Wrap
	tracerBeam.TextureSpeed = 3
	tracerBeam.Width0 = 0.5
	tracerBeam.Width1 = 0.5
	tracerBeam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	tracerBeam.Parent = part

	local glowBeam = Instance.new("Beam")
	glowBeam.Attachment0 = front
	glowBeam.Attachment1 = rear
	glowBeam.Texture = "rbxassetid://14364454897"
	glowBeam.Color = ColorSequence.new(Color3.fromRGB(218, 150, 0))
	glowBeam.Brightness = 3
	glowBeam.LightEmission = 1
	glowBeam.LightInfluence = 0
	glowBeam.FaceCamera = true
	glowBeam.Segments = 10
	glowBeam.TextureLength = 20
	glowBeam.TextureMode = Enum.TextureMode.Wrap
	glowBeam.TextureSpeed = 2
	glowBeam.Width0 = 3
	glowBeam.Width1 = 1
	glowBeam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	glowBeam.Parent = part

	local trailFront = Instance.new("Attachment")
	trailFront.Name = "TrailF"
	trailFront.Position = Vector3.new(0, 0, -0.2)
	trailFront.Parent = part

	local trailRear = Instance.new("Attachment")
	trailRear.Name = "TrailR"
	trailRear.Position = Vector3.new(0, 0, 0.2)
	trailRear.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = trailFront
	trail.Attachment1 = trailRear
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 50))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.15
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = part

	part.Parent = workspace

	local traveled = 0
	local connection: RBXScriptConnection? = nil

	connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		traveled += Constants.PROJECTILE_SPEED * deltaTime
		if traveled >= totalDistance then
			part.CFrame = CFrame.lookAt(hitPos, hitPos + direction)
			if connection then
				connection:Disconnect()
				connection = nil
			end

			Debris:AddItem(part, trail.Lifetime + 0.05)
			return
		end

		local pos = origin + direction * traveled
		part.CFrame = CFrame.lookAt(pos, pos + direction)
	end)

	sessionDumpster:Add(connection)
	sessionDumpster:Add(part)
end

local function findShotOriginAttachment(): Attachment?
	if muzzleFlashShotOrigin and muzzleFlashShotOrigin.Parent then
		return muzzleFlashShotOrigin
	end

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "ShotOrigin" then
			muzzleFlashShotOrigin = descendant
			return descendant
		end
	end

	return nil
end

local function playMuzzleFlash()
	local shotOrigin = findShotOriginAttachment()
	if not shotOrigin then return end

	MuzzleFlashFx.play(shotOrigin)
end

local function fireOnce()
	if currentAmmo <= 0 then return end

	local now = os.clock()
	if (now - clientLastFire) < (1 / params.FireRate) then return end
	clientLastFire = now

	local camera = workspace.CurrentCamera
	local cameraCF = camera.CFrame
	local baseDir = cameraCF.LookVector

	local effectiveSpread = spreadModel:Step(0, getIsMoving())
	effectiveSpread *= (1 - cameraController:GetAdsT())

	local shotSeed = math.random(1, 2 ^ 31 - 2)
	local perturbed = ConeMath.perturbDirection(baseDir, effectiveSpread, shotSeed)

	local maxDistance = params.MaxDistance or Constants.DEFAULT_PARAMS.MaxDistance
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { tool, player.Character }
	raycastParams.IgnoreWater = true

	local cameraResult = workspace:Raycast(cameraCF.Position, perturbed * maxDistance, raycastParams)
	local aimPoint = if cameraResult
		then cameraResult.Position
		else cameraCF.Position + perturbed * maxDistance

	fireRemote:FireServer(cameraCF, aimPoint)
	playMuzzleFlash()
	spreadModel:OnShot()
	recoilModel:OnShot()
end

local function onFireBegan()
	if params.FireType == "semi" then
		fireOnce()
	end
end

local function resolveScopeTemplate(): ScreenGui?
	local current: Instance = ReplicatedStorage
	for _, segment in Constants.SCOPE_TEMPLATE_PATH do
		local nextChild = current:FindFirstChild(segment)
		if not nextChild then return nil end
		current = nextChild
	end

	if not current:IsA("ScreenGui") then return nil end
	return current
end

local function hidePartsForScope()
	table.clear(scopeHiddenParts)

	local character = player.Character
	if character then
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") and scopeHiddenParts[descendant] == nil then
				scopeHiddenParts[descendant] = descendant.LocalTransparencyModifier
			end
		end
	end

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") and scopeHiddenParts[descendant] == nil then
			scopeHiddenParts[descendant] = descendant.LocalTransparencyModifier
		end
	end

	for part in scopeHiddenParts do
		part.LocalTransparencyModifier = 1
	end
end

local function restorePartsFromScope()
	for part, originalModifier in scopeHiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = originalModifier
		end
	end

	table.clear(scopeHiddenParts)
end

local function enableScopeMode()
	if scopeGui then return end

	if crosshair then
		crosshair:Disable()
	end

	local template = resolveScopeTemplate()
	if template then
		local clone = template:Clone()
		clone.ResetOnSpawn = false
		clone.Parent = player:WaitForChild("PlayerGui")
		scopeGui = clone

		local shroud = clone:FindFirstChild(Constants.SCOPE_SHROUD_NAME)
		if shroud and shroud:IsA("Frame") then
			shroud.BackgroundTransparency = 1
			scopeShroud = shroud
		end

		local holder = clone:FindFirstChild(Constants.SCOPE_HOLDER_NAME)
		if holder and holder:IsA("ImageLabel") then
			holder.Visible = false
			scopeHolder = holder
		end
	end

	scopeFadeOutT = 0
	scopeAimReleased = false
	hidePartsForScope()
end

local function destroyScopeGui()
	if scopeGui then
		scopeGui:Destroy()
		scopeGui = nil
	end

	scopeShroud = nil
	scopeHolder = nil
	scopeFadeOutT = 0
	scopeAimReleased = false

	restorePartsFromScope()

	if crosshair then
		crosshair:Enable()
	end
end

local function stepScope(deltaTime: number)
	if not scopeGui then return end

	local adsT = cameraController:GetAdsT()
	local fadeStep = deltaTime / Constants.SCOPE_SHROUD_FADE_OUT_TIME
	local atFullAds = adsT >= 1 and not scopeAimReleased

	if atFullAds then
		scopeFadeOutT = math.min(scopeFadeOutT + fadeStep, 1)
	else
		scopeFadeOutT = math.max(scopeFadeOutT - fadeStep, 0)
	end

	if scopeShroud then
		scopeShroud.BackgroundTransparency = math.max(1 - adsT, scopeFadeOutT)
	end

	if scopeHolder then
		scopeHolder.Visible = atFullAds and scopeFadeOutT > 0
	end

	if scopeAimReleased and adsT <= 0 and scopeFadeOutT <= 0 then
		destroyScopeGui()
	end
end

local function stepRender(deltaTime: number)
	local camera = workspace.CurrentCamera
	local isMoving = getIsMoving()
	local fireHeld = input:IsFireHeld()

	local autoFiring = params.FireType == "auto" and fireHeld
	local totalSpread = spreadModel:Step(deltaTime, isMoving)
	local effective = totalSpread * (1 - cameraController:GetAdsT())
	crosshair:SetSpread(effective, camera)

	local recoilPitch, recoilYaw = recoilModel:Step(deltaTime)
	local adsScale = 1 - cameraController:GetAdsT() * (1 - params.RecoilAdsMult)
	recoilPitch *= adsScale
	recoilYaw *= adsScale
	cameraController:SetRecoilOffset(recoilPitch, recoilYaw)

	updateHoldOverlay()
	stepScope(deltaTime)

	if autoFiring then
		fireOnce()
	end
end

local function onAimBegan()
	local isScopeMode = params.AimMode == Constants.AIM_MODE_SCOPE
	local hasAimSpeed = params.AimSpeed and params.AimSpeed > 0

	if not isScopeMode and not hasAimSpeed then return end

	cameraController:SetAdsTarget(1)
	reloadCancelRemote:FireServer()

	if isScopeMode then
		enableScopeMode()
		scopeAimReleased = false
	end
end

local function onAimEnded()
	cameraController:SetAdsTarget(0)

	if params.AimMode == Constants.AIM_MODE_SCOPE then
		scopeAimReleased = true
		if scopeHolder then
			scopeHolder.Visible = false
		end
	end
end

local function onReloadTriggered()
	if currentAmmo >= params.AmmoMagSize then return end
	reloadRemote:FireServer()
end

local function onShotReplicated(origin: Vector3, _dir: Vector3, hitPos: Vector3, _hitInst: Instance?)
	if typeof(origin) ~= "Vector3" or typeof(hitPos) ~= "Vector3" then return end
	spawnTracer(origin, hitPos)
end

local function onAmmoChanged(newAmmo: number)
	if typeof(newAmmo) ~= "number" then return end
	currentAmmo = newAmmo
	if ammoHud and not isReloading then
		ammoHud:SetAmmo(currentAmmo, params.AmmoMagSize or 0)
	end
end

local function onReloadStarted()
	isReloading = true
	if ammoHud then ammoHud:SetReloading() end
end

local function onReloadAck(newAmmo: number, _fullReload: boolean)
	if typeof(newAmmo) ~= "number" then return end
	currentAmmo = newAmmo
	isReloading = false
	if ammoHud then ammoHud:SetAmmo(currentAmmo, params.AmmoMagSize or 0) end
end

local function connectRemotes()
	sessionDumpster:Connect(shotReplicateRemote.OnClientEvent, onShotReplicated)
	sessionDumpster:Connect(ammoChangedRemote.OnClientEvent, onAmmoChanged)
	sessionDumpster:Connect(reloadStartedRemote.OnClientEvent, onReloadStarted)
	sessionDumpster:Connect(reloadAckRemote.OnClientEvent, onReloadAck)
end

local function onEquipped()
	if isEquipped then return end
	isEquipped = true

	readParams()
	currentAmmo = params.AmmoMagSize or 10
	isReloading = false
	ammoHud = ClientAmmoHud.new()
	cameraController = ClientCamera.new(params)
	crosshair = ClientCrosshair.new()
	input = ClientInput.new()
	recoilModel = ClientRecoilModel.new(params)
	spreadModel = ClientSpreadModel.new(params)

	ammoHud:Enable()
	ammoHud:SetAmmo(currentAmmo, params.AmmoMagSize or 0)
	cameraController:Enable()
	crosshair:Enable()
	input:Enable()

	sessionDumpster:Connect(input.FireBegan.Event, onFireBegan)
	sessionDumpster:Connect(input.AimBegan.Event, onAimBegan)
	sessionDumpster:Connect(input.AimEnded.Event, onAimEnded)
	sessionDumpster:Connect(input.ReloadTriggered.Event, onReloadTriggered)

	connectRemotes()

	sessionDumpster:Connect(RunService.RenderStepped, stepRender)
	sessionDumpster:Add(ammoHud)
	sessionDumpster:Add(input)
	sessionDumpster:Add(crosshair)
	sessionDumpster:Add(recoilModel)
	sessionDumpster:Add(spreadModel)
	sessionDumpster:Add(cameraController)
end

local function onUnequipped()
	if not isEquipped then return end
	isEquipped = false

	destroyScopeGui()

	sessionDumpster:Destroy()
	ammoHud = nil
	input = nil
	crosshair = nil
	recoilModel = nil
	spreadModel = nil
	cameraController = nil
end

-- Connections

lifecycleDumpster:Connect(tool.Equipped, onEquipped)
lifecycleDumpster:Connect(tool.Unequipped, onUnequipped)

lifecycleDumpster:Connect(script.Destroying, function()
	onUnequipped()
	lifecycleDumpster:Destroy()
end)

end

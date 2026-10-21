--[[
	File: Firearm2Server.server.luau
]]--

if not script.Parent:IsA("Tool") then return end

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local Constants = require(Firearm2.Common.Constants)
local MuzzleFlashFx = require(FourD.Common.MuzzleFlashFx)

-- Constants

local DAMAGE_TAG = Constants.WEAPONS_SYSTEM_DAMAGEABLE_TAG
local VERBOSE_LOGGING = Constants.VERBOSE_LOGGING
local BODY_PART_NAME = Constants.BODY_PART_NAME
local HOLD_WELD_NAME = Constants.HOLD_WELD_NAME
local PICKUP_DEBOUNCE_SECONDS = 1

-- Variables

local Tool: Tool = script.Parent
local Remotes = Tool:WaitForChild("Remotes")
local AmmoChangedRemote = Remotes:WaitForChild("AmmoChanged")
local FireRemote = Remotes:WaitForChild("Fire")
local ReloadAckRemote = Remotes:WaitForChild("ReloadAck")
local ReloadCancelRemote = Remotes:WaitForChild("ReloadCancel")
local ReloadRemote = Remotes:WaitForChild("Reload")
local ReloadStartedRemote = Remotes:WaitForChild("ReloadStarted")
local ShotReplicateRemote = Remotes:WaitForChild("ShotReplicate")

local State = {
	Ammo = Tool:GetAttribute("AmmoMagSize") or 10,
	LastFireByUserId = {} :: { [number]: number },
	IsReloading = false,
	ReloadCancelled = false,
	ShellThread = nil,
	DebugParts = {},
	HoldWeld = nil,
	LastPickupClock = 0,
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function getParam(key: string): any
	return Tool:GetAttribute(key)
end

local function findShotOrigin(): Attachment?
	for _, descendant in Tool:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "ShotOrigin" then
			return descendant
		end
	end

	return nil
end

local function findBody(): BasePart?
	local body = Tool:FindFirstChild(BODY_PART_NAME)
	if body and body:IsA("BasePart") then return body end

	return nil
end

local function teardownHoldWeld()
	local weld = State.HoldWeld
	if not weld then return end
	weld:Destroy()
	State.HoldWeld = nil

	local body = findBody()
	if body then
		body.Anchored = true
		body.CanCollide = true
	end
end

local function setupHoldWeld()
	teardownHoldWeld()

	local character = Tool.Parent
	if not character or not character:IsA("Model") then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return end

	local body = findBody()
	if not body then return end

	local holdCFrame = Tool:GetAttribute("HoldCFrame")
	if typeof(holdCFrame) ~= "CFrame" then
		vwarn("HoldCFrame attribute missing or wrong type; skipping weld")
		return
	end

	body.CFrame = rootPart.CFrame * holdCFrame
	body.Anchored = false
	body.CanCollide = false

	local weld = Instance.new("Motor6D")
	weld.Name = HOLD_WELD_NAME
	weld.Part0 = rootPart
	weld.Part1 = body
	weld.C0 = holdCFrame
	weld.C1 = CFrame.identity
	weld.Parent = rootPart

	State.HoldWeld = weld
end

local function getOwner(): Player?
	local character = Tool.Parent
	if not character or not character:IsA("Model") then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character == character then
			return player
		end
	end

	return nil
end

local function validateOwner(player: Player): boolean
	return Tool.Parent == player.Character
end

local function applyDamage(hitPart: BasePart, damage: number)
	local parent = hitPart.Parent
	if parent then
		local humanoid = parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(damage)
			return
		end
	end

	local current = hitPart
	while current and current ~= workspace do
		if CollectionService:HasTag(current, DAMAGE_TAG) then
			local damageEvent = current:FindFirstChild("TakeDamage")
			if damageEvent and damageEvent:IsA("BindableEvent") then
				damageEvent:Fire(damage)
			end

			return
		end

		current = current.Parent
	end
end

local function fireAmmoChanged()
	local owner = getOwner()
	if owner then
		AmmoChangedRemote:FireClient(owner, State.Ammo)
	end
end

local function fireReloadAck(fullReload: boolean)
	local owner = getOwner()
	if owner then
		ReloadAckRemote:FireClient(owner, State.Ammo, fullReload)
	end
end

local function fireReloadStarted()
	local owner = getOwner()
	if owner then
		ReloadStartedRemote:FireClient(owner)
	end
end

local function cancelShellReload()
	if not State.IsReloading then return end
	if getParam("AmmoReloadType") ~= "shell" then return end
	State.ReloadCancelled = true
end

local function startMagazineReload(wasEmpty: boolean)
	if State.IsReloading then return end
	if State.Ammo >= getParam("AmmoMagSize") then return end

	State.IsReloading = true
	local extra = if wasEmpty then getParam("AmmoReloadEmptyTime") else 0
	local totalTime = getParam("AmmoReloadTime") + extra
	fireReloadStarted()

	task.delay(totalTime, function()
		if Tool.Parent == nil then return end
		State.Ammo = getParam("AmmoMagSize")
		State.IsReloading = false
		fireAmmoChanged()
		fireReloadAck(true)
	end)
end

local function startShellReload()
	if State.IsReloading then return end
	if State.Ammo >= getParam("AmmoMagSize") then return end

	State.IsReloading = true
	State.ReloadCancelled = false
	fireReloadStarted()

	State.ShellThread = task.spawn(function()
		local magSize = getParam("AmmoMagSize")
		local perShell = getParam("AmmoReloadTime") / magSize

		while State.Ammo < magSize and not State.ReloadCancelled do
			task.wait(perShell)
			if State.ReloadCancelled then break end
			if Tool.Parent == nil then break end

			State.Ammo += 1
			fireAmmoChanged()
		end

		State.IsReloading = false
		State.ShellThread = nil
		fireReloadAck(false)
	end)
end

local function spawnDebugTracer(origin: Vector3, hitPos: Vector3)
	if not Constants.DEBUG_VISUALIZER then return end

	local delta = hitPos - origin
	local length = delta.Magnitude
	if length <= 0 then return end

	local part = Instance.new("Part")
	part.Name = "Firearm2DebugTracer"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 80, 80)
	part.Transparency = 0.4
	part.Size = Vector3.new(0.15, 0.15, length)
	part.CFrame = CFrame.lookAt(origin + delta * 0.5, hitPos)
	part.Parent = workspace

	table.insert(State.DebugParts, part)

	while #State.DebugParts > Constants.DEBUG_VISUALIZER_MAX_PARTS do
		local oldest = table.remove(State.DebugParts, 1)
		if oldest then oldest:Destroy() end
	end
end

local function handleFire(player: Player, cameraCF: CFrame, aimPoint: Vector3)
	if not validateOwner(player) then return end
	if typeof(cameraCF) ~= "CFrame" then return end
	if typeof(aimPoint) ~= "Vector3" then return end

	local now = os.clock()
	local minInterval = 1 / getParam("FireRate")
	local lastFire = State.LastFireByUserId[player.UserId] or 0
	if (now - lastFire) < minInterval then return end
	if State.Ammo <= 0 then return end

	local cameraPos = cameraCF.Position
	local cameraLook = cameraCF.LookVector
	local toAim = aimPoint - cameraPos
	local aimDistance = toAim.Magnitude
	local maxDistance = getParam("MaxDistance")
	local maxSpread = getParam("MaxSpread")
	local angleTolerance = Constants.SHOT_VALIDATION_ANGLE_TOLERANCE_DEG
	local distanceTolerance = Constants.SHOT_VALIDATION_DISTANCE_TOLERANCE

	if aimDistance < 0.001 then return end
	if aimDistance > maxDistance + distanceTolerance then return end

	local clientDir = toAim / aimDistance
	local maxAngleRad = math.rad(maxSpread * 0.5 + angleTolerance)
	if cameraLook:Dot(clientDir) < math.cos(maxAngleRad) then return end

	State.LastFireByUserId[player.UserId] = now
	State.Ammo -= 1
	fireAmmoChanged()
	cancelShellReload()

	local shotOrigin = findShotOrigin()
	if not shotOrigin then
		vwarn("ShotOrigin attachment missing on Tool; skipping shot")
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { Tool, player.Character }
	raycastParams.IgnoreWater = true

	local cameraResult = workspace:Raycast(cameraPos, clientDir * maxDistance, raycastParams)
	local serverAimPoint = if cameraResult
		then cameraResult.Position
		else cameraPos + clientDir * maxDistance
	local cameraHitInstance = cameraResult and cameraResult.Instance or nil

	local barrelOrigin = shotOrigin.WorldPosition
	local barrelToAim = serverAimPoint - barrelOrigin
	local barrelDistance = barrelToAim.Magnitude
	local barrelDir = if barrelDistance > 0.001 then barrelToAim / barrelDistance else clientDir
	local barrelResult = workspace:Raycast(barrelOrigin, barrelDir * maxDistance, raycastParams)

	local finalHitPos
	local finalHitInstance
	if barrelResult and (barrelResult.Position - barrelOrigin).Magnitude < barrelDistance - 0.05 then
		finalHitPos = barrelResult.Position
		finalHitInstance = barrelResult.Instance
	else
		finalHitPos = serverAimPoint
		finalHitInstance = cameraHitInstance
	end

	if finalHitInstance then
		applyDamage(finalHitInstance, getParam("DamagePerRound"))
	end

	ShotReplicateRemote:FireAllClients(barrelOrigin, barrelDir, finalHitPos, finalHitInstance)
	MuzzleFlashFx.fire(shotOrigin, player)
	spawnDebugTracer(barrelOrigin, finalHitPos)

	if State.Ammo <= 0 and getParam("AmmoReloadType") == "magazine" then
		startMagazineReload(true)
	end
end

local function handleReload(player: Player)
	if not validateOwner(player) then return end
	if State.IsReloading then return end
	if State.Ammo >= getParam("AmmoMagSize") then return end
	if getParam("AmmoReloadType") == "shell" then
		startShellReload()
	else
		startMagazineReload(false)
	end
end

local function handleReloadCancel(player: Player)
	if not validateOwner(player) then return end
	cancelShellReload()
end

local function handleBodyTouched(hit: BasePart)
	local parent = Tool.Parent
	if not parent or not Tool:IsDescendantOf(workspace) then return end
	if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then return end

	local now = os.clock()
	if now - State.LastPickupClock < PICKUP_DEBOUNCE_SECONDS then return end

	local character = hit.Parent
	if not character or not character:IsA("Model") then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	State.LastPickupClock = now
	Tool.Parent = backpack
	vprint(`picked up by "{player.Name}"`)
end

-- Connections

local bodyPart = findBody()
if bodyPart then
	bodyPart.Touched:Connect(handleBodyTouched)
end

FireRemote.OnServerEvent:Connect(handleFire)
ReloadRemote.OnServerEvent:Connect(handleReload)
ReloadCancelRemote.OnServerEvent:Connect(handleReloadCancel)

Tool.Equipped:Connect(function()
	setupHoldWeld()
	fireAmmoChanged()
end)

Tool.Unequipped:Connect(function()
	teardownHoldWeld()
end)

Tool:GetAttributeChangedSignal("HoldCFrame"):Connect(function()
	if not State.HoldWeld then return end
	local holdCFrame = Tool:GetAttribute("HoldCFrame")
	if typeof(holdCFrame) == "CFrame" then
		State.HoldWeld.C0 = holdCFrame
	else
		teardownHoldWeld()
	end
end)

Tool.Destroying:Connect(function()
	State.ReloadCancelled = true
	local thread = State.ShellThread
	if thread then
		State.ShellThread = nil
		pcall(task.cancel, thread)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	State.LastFireByUserId[player.UserId] = nil
end)

Tool.AncestryChanged:Connect(function()
	local parent = Tool.Parent
	if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
		setupHoldWeld()
	else
		teardownHoldWeld()
	end

	if Tool.Parent == nil then
		State.ReloadCancelled = true
		for _, part in State.DebugParts do
			if part then part:Destroy() end
		end

		table.clear(State.DebugParts)
	end
end)

vprint(`Firearm2Server initialized for Tool "{Tool.Name}" with {State.Ammo} rounds`)
_
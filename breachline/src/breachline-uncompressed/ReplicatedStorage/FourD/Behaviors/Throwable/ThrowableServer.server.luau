-- Template guard: only run when cloned into a Tool, not from ReplicatedStorage
if not script.Parent:IsA("Tool") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Common = FourD.Common
local getCharacterFromPart = require(Common.getCharacterFromPart)
local ConstructionHelpers = require(Common.ConstructionHelpers)
local GeometryUtils = require(Common.GeometryUtils)

local tool: Tool = script.Parent
local throwAction = tool:WaitForChild("ThrowAction") :: RemoteEvent
local cloneSpawned = tool:WaitForChild("CloneSpawned") :: BindableEvent

local FORWARD_FORCE = tool:GetAttribute("ForwardThrowForce") or 1000
local UPWARDS_FORCE = tool:GetAttribute("UpwardsThrowForce") or 500
local COMPENSATE_GRAVITY = tool:GetAttribute("CompensateGravity") ~= false
local COMPENSATE_MASS = tool:GetAttribute("CompensateMass") ~= false
local COLLISIONS_ENABLED = tool:GetAttribute("CollisionsEnabled") ~= false
local EXPIRE_TIME = tool:GetAttribute("ExpireTime") or 0
local NOTIFY_ON_HIT = tool:GetAttribute("NotifyOnHit") or "once"
local HIT_FILTER_MODE = tool:GetAttribute("HitFilterMode") or "exclude"

local MIN_ASSEMBLY_MASS = 0.0001

-- Helpers

local function getOwnerPlayer(): Player?
	local parent = tool.Parent
	if not parent then return nil end
	local player = Players:GetPlayerFromCharacter(parent)
	if player then return player end
	if parent:IsA("Backpack") then
		return parent.Parent :: Player
	end
	return nil
end

local function getLookDirection(player: Player, aimDirection: Vector3?): Vector3
	if typeof(aimDirection) == "Vector3" then
		local flat = Vector3.new(aimDirection.X, 0, aimDirection.Z)
		local magnitude = flat.Magnitude
		if magnitude > 0.001 and magnitude < math.huge then
			return flat.Unit
		end
	end

	local character = player.Character
	if not character then return Vector3.new(0, 0, -1) end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return Vector3.new(0, 0, -1) end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then return Vector3.new(0, 0, -1) end
	return flat.Unit
end

local function buildFilterSet(): { [Instance]: boolean }
	local filterSet: { [Instance]: boolean } = {}
	local filterFolder = tool:FindFirstChild("HitFilter")
	if not filterFolder then return filterSet end
	for _, ref in filterFolder:GetChildren() do
		if ref:IsA("ObjectValue") and ref.Value then
			filterSet[ref.Value] = true
		end
	end
	return filterSet
end

local function isInFilter(part: BasePart, filterSet: { [Instance]: boolean }): boolean
	local current: Instance? = part
	while current do
		if filterSet[current] then return true end
		current = current.Parent
	end
	return false
end

local function excludeCharacterCollisions(newHandle: BasePart, character: Model?)
	if not character then return end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			ConstructionHelpers.makeNoCollide(newHandle, descendant)
		end
	end
end

local function cloneHandle(originalHandle: BasePart): BasePart
	local cloned = Instance.new("Part")
	cloned.Name = "Handle"
	cloned.Size = originalHandle.Size
	cloned.CFrame = originalHandle.CFrame
	cloned.Transparency = originalHandle.Transparency
	cloned.CanCollide = originalHandle.CanCollide
	cloned.CanTouch = false
	cloned.Anchored = false
	return cloned
end

-- Throw Logic

local function launchClone(player: Player, aimDirection: Vector3?)
	local originalHandle = tool:FindFirstChild("Handle") :: BasePart?
	if not originalHandle then return end

	local originalModel: Model?
	for _, child in tool:GetChildren() do
		if child:IsA("Model") then
			originalModel = child
			break
		end
	end
	if not originalModel then return end

	local direction = getLookDirection(player, aimDirection)
	local filterSet = buildFilterSet()

	local newHandle = cloneHandle(originalHandle)
	local clonedModel = originalModel:Clone()
	clonedModel:RemoveTag("FourDCapability")

	for _, part in GeometryUtils.getInstanceParts(clonedModel) do
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
		ConstructionHelpers.makeWeld(newHandle, part)
	end

	local onHitEvent = Instance.new("BindableEvent")
	onHitEvent.Name = "OnHit"
	onHitEvent.Parent = newHandle

	local onExpiredEvent = Instance.new("BindableEvent")
	onExpiredEvent.Name = "OnExpired"
	onExpiredEvent.Parent = newHandle

	clonedModel.Parent = newHandle
	excludeCharacterCollisions(newHandle, player.Character)
	newHandle.Parent = Workspace

	cloneSpawned:Fire(newHandle, clonedModel)

	pcall(newHandle.SetNetworkOwner, newHandle, nil)

	local speedScale = if COMPENSATE_MASS then 1 else 1 / math.max(newHandle.AssemblyMass, MIN_ASSEMBLY_MASS)
	local velocity = (direction * FORWARD_FORCE + Vector3.new(0, UPWARDS_FORCE, 0)) * speedScale
	if COMPENSATE_GRAVITY then
		velocity += Vector3.new(0, Workspace.Gravity * speedScale, 0)
	end
	newHandle.AssemblyLinearVelocity = velocity

	newHandle.CanCollide = COLLISIONS_ENABLED
	newHandle.CanTouch = true

	if NOTIFY_ON_HIT ~= "never" then
		local ownerCharacter = player.Character
		local hitConnection: RBXScriptConnection?

		hitConnection = newHandle.Touched:Connect(function(hitPart: BasePart)
			local character = getCharacterFromPart(hitPart)
			if character and character == ownerCharacter then return end

			if HIT_FILTER_MODE == "include" and not isInFilter(hitPart, filterSet) then return end
			if HIT_FILTER_MODE == "exclude" and isInFilter(hitPart, filterSet) then return end

			onHitEvent:Fire(hitPart)

			if NOTIFY_ON_HIT == "once" and hitConnection then
				hitConnection:Disconnect()
				hitConnection = nil
			end
		end)
	end

	if EXPIRE_TIME > 0 then
		task.delay(EXPIRE_TIME, function()
			if not newHandle or not newHandle.Parent then return end
			onExpiredEvent:Fire(newHandle.Position)
			task.wait(0.25)
			newHandle:Destroy()
		end)
	end

	-- Signal client that throw is complete so it can reset state
	throwAction:FireClient(player)
end

-- Connections

throwAction.OnServerEvent:Connect(function(player: Player, aimDirection: Vector3?)
	if getOwnerPlayer() ~= player then return end
	launchClone(player, aimDirection)
end)

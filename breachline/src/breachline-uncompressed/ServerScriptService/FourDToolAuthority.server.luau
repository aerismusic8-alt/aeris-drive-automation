-- Server-authoritative handling for shared FourD Tool controls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local common = ReplicatedStorage:WaitForChild("FourD"):WaitForChild("Common")
local Players = game:GetService("Players")
local ToolInventoryPolicy = require(common:WaitForChild("ToolInventoryPolicy"))
local getCharacterFromPart = require(common:WaitForChild("getCharacterFromPart"))
local dropRemote = common:FindFirstChild("DropToolRequest")
if not dropRemote then
	dropRemote = Instance.new("RemoteEvent")
	dropRemote.Name = "DropToolRequest"
	dropRemote.Parent = common
end

assert(dropRemote:IsA("RemoteEvent"), "FourD.Common.DropToolRequest must be a RemoteEvent")

-- Long tools land partly underneath the dropper, so walk-over pickup has to stay
-- off long enough for them to step away. Read by Firearm2Server's own pickup.
local PICKUP_GUARD_ATTRIBUTE = "FourD_PickupGuardUntil"
local PICKUP_GUARD_SECONDS = 1.5
local DROP_CLEARANCE_STUDS = 2.5
local GROUND_PROBE_HEIGHT = 6
local GROUND_PROBE_DEPTH = 60
local HANDLE_NAME = "Handle"

type Placement = { Part: BasePart, CFrame: CFrame }
type WorldToolState = {
	Parent: Instance,
	Parts: { Placement },
}

-- Set only while a Tool is leaving Workspace. StarterPack grants and scripted
-- inventory transfers are not world pickups and therefore do not consume this
-- gate.
local pendingWorldPickups: { [Tool]: WorldToolState } = setmetatable({}, { __mode = "k" }) :: any

---Poses are snapshotted rather than read back during the move: writing one part
---of a welded assembly drags the rest, so live reads compound the offset.
local function snapshot(tool: Tool): { Placement }
	local parts: { Placement } = {}
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, { Part = descendant, CFrame = descendant.CFrame })
		end
	end

	return parts
end

---World-axis-aligned bounds of the whole tool, so placement accounts for a rifle's
---length rather than just its handle.
local function measure(parts: { Placement }): (Vector3?, Vector3?)
	local min: Vector3? = nil
	local max: Vector3? = nil

	for _, placement in parts do
		local part = placement.Part
		local cf = placement.CFrame
		local half = part.Size * 0.5
		local extent = Vector3.new(
			math.abs(cf.RightVector.X) * half.X
				+ math.abs(cf.UpVector.X) * half.Y
				+ math.abs(cf.LookVector.X) * half.Z,
			math.abs(cf.RightVector.Y) * half.X
				+ math.abs(cf.UpVector.Y) * half.Y
				+ math.abs(cf.LookVector.Y) * half.Z,
			math.abs(cf.RightVector.Z) * half.X
				+ math.abs(cf.UpVector.Z) * half.Y
				+ math.abs(cf.LookVector.Z) * half.Z
		)

		local partMin = cf.Position - extent
		local partMax = cf.Position + extent
		min = if min then min:Min(partMin) else partMin
		max = if max then max:Max(partMax) else partMax
	end

	if not min or not max then return nil, nil end
	return (min + max) * 0.5, max - min
end

local function guardPickup(tool: Tool, parts: { Placement })
	local restore: { [BasePart]: boolean } = {}
	for _, placement in parts do
		restore[placement.Part] = placement.Part.CanTouch
		placement.Part.CanTouch = false
	end

	tool:SetAttribute(PICKUP_GUARD_ATTRIBUTE, os.clock() + PICKUP_GUARD_SECONDS)

	task.delay(PICKUP_GUARD_SECONDS, function()
		for part, canTouch in restore do
			if part.Parent then
				part.CanTouch = canTouch
			end
		end

		if tool.Parent then
			tool:SetAttribute(PICKUP_GUARD_ATTRIBUTE, nil)
		end
	end)
end

-- The engine's own walk-over pickup is bound to a TouchInterest on the child
-- named "Handle", and it moves the Tool into a Backpack before any script can
-- refuse it. Taking the Tool back out afterwards desynchronises the player's
-- backpack UI and leaves them unable to equip anything, so the engine path is
-- switched off at the source and pickup is driven from the rest of the Tool's
-- geometry instead. RequiresHandle does not gate this; only the part name does.
local suppressedHandles: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function findHandle(tool: Tool): BasePart?
	local handle = tool:FindFirstChild(HANDLE_NAME)
	return if handle and handle:IsA("BasePart") then handle else nil
end

---A Tool made of nothing but its Handle has no other part that could report the
---touch, so it keeps the engine pickup and relies on rejectPickupIfFull.
local function hasNonHandlePart(tool: Tool): boolean
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= HANDLE_NAME then
			return true
		end
	end

	return false
end

local function suppressEnginePickup(tool: Tool)
	local handle = findHandle(tool)
	if not handle or suppressedHandles[handle] ~= nil then return end
	if not hasNonHandlePart(tool) then return end

	suppressedHandles[handle] = handle.CanTouch
	handle.CanTouch = false
end

local function restoreEnginePickup(tool: Tool)
	local handle = findHandle(tool)
	if not handle then return end

	local original = suppressedHandles[handle]
	if original == nil then return end

	suppressedHandles[handle] = nil
	handle.CanTouch = original
end

local function restoreRejectedPickup(tool: Tool, state: WorldToolState)
	local parent = if state.Parent:IsDescendantOf(game) then state.Parent else Workspace
	tool.Parent = parent
	for _, placement in state.Parts do
		if placement.Part.Parent then
			placement.Part.CFrame = placement.CFrame
			if not placement.Part.Anchored then
				placement.Part.AssemblyLinearVelocity = Vector3.zero
				placement.Part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	guardPickup(tool, state.Parts)
end

local function rejectPickupIfFull(player: Player, child: Instance)
	if not child:IsA("Tool") then return end

	local state = pendingWorldPickups[child]
	if not state then return end
	pendingWorldPickups[child] = nil

	if ToolInventoryPolicy.canPickup(player, child) then return end
	task.defer(restoreRejectedPickup, child, state)
end

local function watchPlayer(player: Player)
	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(function(child: Instance)
			rejectPickupIfFull(player, child)
		end)
	end

	-- Respawning replaces the Backpack instance, so this has to follow the
	-- current one rather than bind once to the Backpack present at join.
	local function watchBackpack(backpack: Instance)
		backpack.ChildAdded:Connect(function(child: Instance)
			rejectPickupIfFull(player, child)
		end)
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then watchBackpack(backpack) end
	player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then watchBackpack(child) end
	end)

	if player.Character then watchCharacter(player.Character) end
	player.CharacterAdded:Connect(watchCharacter)
end

Workspace.DescendantRemoving:Connect(function(descendant: Instance)
	if not descendant:IsA("Tool") then return end
	local parent = descendant.Parent
	if not parent then return end

	-- Leaving the world: the Handle goes back to behaving normally, so nothing
	-- downstream sees a Tool whose Handle silently refuses touches.
	restoreEnginePickup(descendant)

	pendingWorldPickups[descendant] = {
		Parent = parent,
		Parts = snapshot(descendant),
	}
end)

for _, player in Players:GetPlayers() do
	task.spawn(watchPlayer, player)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Pickup is performed here rather than by the engine, so capacity is checked
-- before ownership changes and a refused Tool is left untouched in the world.
local watchedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local watchedParts: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function watchPickupPart(tool: Tool, part: BasePart)
	-- The Handle is the part the engine watches; it is muted while the Tool is
	-- in the world and so cannot report anything here either.
	if part.Name == HANDLE_NAME then return end
	if watchedParts[part] then return end
	watchedParts[part] = true

	part.Touched:Connect(function(hitPart: BasePart)
		if not tool:IsDescendantOf(Workspace) then return end

		local guardUntil = tool:GetAttribute(PICKUP_GUARD_ATTRIBUTE)
		if typeof(guardUntil) == "number" and os.clock() < guardUntil then return end

		local character = getCharacterFromPart(hitPart)
		if not character then return end

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		ToolInventoryPolicy.tryPickup(player, tool)
	end)
end

local function watchWorldTool(tool: Tool)
	-- Runs on every return to the world, including after a drop, because the
	-- engine rebinds its pickup each time the Tool is parented into Workspace.
	suppressEnginePickup(tool)

	if watchedTools[tool] then return end
	watchedTools[tool] = true

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			watchPickupPart(tool, descendant)
		end
	end

	tool.DescendantAdded:Connect(function(descendant: Instance)
		if not descendant:IsA("BasePart") then return end
		watchPickupPart(tool, descendant)
		if tool:IsDescendantOf(Workspace) then
			suppressEnginePickup(tool)
		end
	end)
end

for _, descendant in Workspace:GetDescendants() do
	if descendant:IsA("Tool") then
		watchWorldTool(descendant)
	end
end

Workspace.DescendantAdded:Connect(function(descendant: Instance)
	if descendant:IsA("Tool") then
		watchWorldTool(descendant)
	end
end)

local function placeInFrontOf(tool: Tool, character: Model, root: BasePart)
	local parts = snapshot(tool)
	local center, size = measure(parts)
	if not center or not size then return end

	local forward = root.CFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.zAxis

	local clearance = DROP_CLEARANCE_STUDS + math.max(size.X, size.Z) * 0.5
	local landing = root.Position + forward * clearance

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tool }
	params.IgnoreWater = true

	local hit = Workspace:Raycast(
		landing + Vector3.new(0, GROUND_PROBE_HEIGHT, 0),
		Vector3.new(0, -GROUND_PROBE_DEPTH, 0),
		params
	)
	local groundY = if hit then hit.Position.Y else root.Position.Y - root.Size.Y
	local target = Vector3.new(landing.X, groundY + size.Y * 0.5 + 0.1, landing.Z)

	local delta = target - center
	for _, placement in parts do
		placement.Part.CFrame = placement.CFrame + delta
	end
	for _, placement in parts do
		if not placement.Part.Anchored then
			placement.Part.AssemblyLinearVelocity = Vector3.zero
			placement.Part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	guardPickup(tool, parts)
end

dropRemote.OnServerEvent:Connect(function(player: Player, tool: Instance)
	if typeof(tool) ~= "Instance" then return end
	if not tool:IsA("Tool") then return end
	if not tool.CanBeDropped then return end

	local character = player.Character
	if not character or tool.Parent ~= character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	tool.Parent = Workspace

	-- Tool scripts unweld and re-anchor on their own AncestryChanged handlers,
	-- which run deferred. Placing before those land would be overwritten.
	RunService.Heartbeat:Wait()
	if tool.Parent ~= Workspace then return end

	placeInFrontOf(tool, character, root)
end)

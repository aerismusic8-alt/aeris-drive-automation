-- Template guard: only run when cloned into a Tool, not from ReplicatedStorage.
-- Mirrors ThrowableServer's pattern (co-located Server Script on the Tool).
if not script.Parent:IsA("Tool") then return end

--[[
	Grenade pin/lever "pop" effect. When the player starts a throw, the safety
	lever and pull pin fly off the equipped grenade; when the thrown clone spawns
	they are stripped from it. This ran as an in-memory connection inside the
	edit-time bind() (Grenade3's MakeFunctional) and did not survive to Play, so
	the pieces never popped. Moving it into this co-located Server Script -- the
	same mechanism ThrowableServer and GrenadeExplosion already use -- makes it run
	at Play. The grenade's core throw + explode were never affected (they always
	lived in ThrowableServer / GrenadeExplosion).
]]

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD:WaitForChild("Common"):WaitForChild("ConstructionHelpers"))

local DESPAWN_SECONDS = 3
local PIN_POP_FORCE = Vector3.new(6, 3, 0)
local LEVER_POP_FORCE = Vector3.new(0, 5, 9)
local MAX_SPIN_TORQUE = 6
local PIN_MATCH = "pull pin"
local LEVER_MATCH = "safety lever"

local tool: Tool = script.Parent
local throwStartAction = tool:WaitForChild("ThrowStartAction", 10)
local cloneSpawned = tool:WaitForChild("CloneSpawned", 10)
if not (throwStartAction and throwStartAction:IsA("RemoteEvent")) then return end
if not (cloneSpawned and cloneSpawned:IsA("BindableEvent")) then return end

local function getModel(): Model?
	for _, child in tool:GetChildren() do
		if child:IsA("Model") then
			return child
		end
	end
	return nil
end

local function FindChildByNameSubstring(parent: Instance, needle: string): Instance?
	for _, descendant in parent:GetDescendants() do
		if not (descendant:IsA("BasePart") or descendant:IsA("Model")) then continue end
		if string.find(string.lower(descendant.Name), needle, 1, true) then
			return descendant
		end
	end
	return nil
end

local function GetRootPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then return instance end
	if instance:IsA("Model") then
		if instance.PrimaryPart then return instance.PrimaryPart end
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				instance.PrimaryPart = descendant
				return descendant
			end
		end
	end
	return nil
end

local function GetWorldCFrame(instance: Instance): CFrame?
	if instance:IsA("BasePart") then return instance.CFrame end
	if instance:IsA("Model") then return instance:GetPivot() end
	return nil
end

local function CollectCharacterParts(character: Model?): { BasePart }
	local parts: { BasePart } = {}
	if not character then return parts end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function PrepClone(clone: Instance, root: BasePart?): { BasePart }
	local parts: { BasePart } = {}
	if clone:IsA("BasePart") then
		table.insert(parts, clone)
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	for _, part in parts do
		part.Anchored = false
		part.CanCollide = true
		part.CanTouch = false
		part.Massless = false
	end

	if root and clone:IsA("Model") then
		for _, part in parts do
			if part ~= root then
				ConstructionHelpers.makeWeld(root, part)
			end
		end
	end

	return parts
end

local function RandomSpin(): Vector3
	return Vector3.new(
		(math.random() * 2 - 1) * MAX_SPIN_TORQUE,
		(math.random() * 2 - 1) * MAX_SPIN_TORQUE,
		(math.random() * 2 - 1) * MAX_SPIN_TORQUE
	)
end

local function PopPiece(handle: BasePart, original: Instance, localForce: Vector3, characterParts: { BasePart }): { BasePart }
	local worldCFrame = GetWorldCFrame(original)
	if not worldCFrame then return {} end

	local clone = original:Clone()

	if clone:IsA("Model") then
		clone.Parent = Workspace
		clone:PivotTo(worldCFrame)
	elseif clone:IsA("BasePart") then
		clone.CFrame = worldCFrame
		clone.Parent = Workspace
	else
		clone:Destroy()
		return {}
	end

	local root = GetRootPart(clone)
	local parts = PrepClone(clone, root)

	for _, part in parts do
		for _, limb in characterParts do
			ConstructionHelpers.makeNoCollide(part, limb)
		end
	end

	if root then
		local worldForce = handle.CFrame:VectorToWorldSpace(localForce)
		local mass = root.AssemblyMass
		root:ApplyImpulse(worldForce * mass)
		root:ApplyAngularImpulse(RandomSpin() * mass)
	end

	Debris:AddItem(clone, DESPAWN_SECONDS)

	return parts
end

local liveDebris: { BasePart } = {}

throwStartAction.OnServerEvent:Connect(function(player: Player)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	local model = getModel()
	if not handle or not model then return end

	local characterParts = CollectCharacterParts(player.Character)
	local pin = FindChildByNameSubstring(model, PIN_MATCH)
	local lever = FindChildByNameSubstring(model, LEVER_MATCH)
	table.clear(liveDebris)
	if pin then
		for _, part in PopPiece(handle, pin, PIN_POP_FORCE, characterParts) do
			table.insert(liveDebris, part)
		end
	end
	if lever then
		for _, part in PopPiece(handle, lever, LEVER_POP_FORCE, characterParts) do
			table.insert(liveDebris, part)
		end
	end
end)

cloneSpawned.Event:Connect(function(newHandle: BasePart, clonedModel: Model)
	for _, part in liveDebris do
		if part.Parent then
			ConstructionHelpers.makeNoCollide(newHandle, part)
		end
	end

	local clonedPin = FindChildByNameSubstring(clonedModel, PIN_MATCH)
	local clonedLever = FindChildByNameSubstring(clonedModel, LEVER_MATCH)
	if clonedPin then clonedPin:Destroy() end
	if clonedLever then clonedLever:Destroy() end
end)

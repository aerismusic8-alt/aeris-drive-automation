--[[
	File: Occupant.server.luau
]]--

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local Constants = require(script.Parent.Parent.Constants)
local GetTrueHipHeight = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("getTrueHipHeight"))

-- Object References

local boardRig = script.Parent.Parent.Parent
local tool = boardRig.Parent
local chassis = boardRig:WaitForChild("Chassis")
local handle = tool:WaitForChild("Handle")
local wheelsFolder = boardRig:WaitForChild("Wheels")
local ownerValue = boardRig:WaitForChild(Constants.OWNER_VALUE_NAME)
local ownerLockValue = boardRig:WaitForChild(Constants.OWNER_LOCK_VALUE_NAME)

-- Constants

local WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }

-- State

local currentOccupant: Player? = nil
local riderWeld: WeldConstraint? = nil
local cachedRootMassless: boolean? = nil
local connections: { RBXScriptConnection } = {}
local isRiding = false
local heldWeld: Weld? = nil
local wheelLockWelds: { WeldConstraint } = {}
local cachedCanCollide: { [BasePart]: boolean } = {}

-- Local Functions

local function setHingeActuator(actuatorType: Enum.ActuatorType)
	for _, wheelName in WHEEL_NAMES do
		local wheelModel = wheelsFolder:FindFirstChild(wheelName)
		if not wheelModel then continue end

		local wheelPart = wheelModel:FindFirstChild("Wheel")
		if not wheelPart then continue end

		local hinge = wheelPart:FindFirstChildOfClass("HingeConstraint")
		if not hinge then continue end

		hinge.AngularVelocity = 0
		hinge.ActuatorType = actuatorType
	end
end

local function getWheelParts(): { BasePart }
	local parts: { BasePart } = {}
	for _, wheelName in WHEEL_NAMES do
		local wheelModel = wheelsFolder:FindFirstChild(wheelName)
		if not wheelModel then continue end

		local wheelPart = wheelModel:FindFirstChild("Wheel")
		if wheelPart and wheelPart:IsA("BasePart") then
			table.insert(parts, wheelPart)
		end
	end

	return parts
end

local function clearConnections()
	for _, conn in connections do
		conn:Disconnect()
	end

	table.clear(connections)
end

local function setBoardCollisions(enabled: boolean)
	if enabled then
		if next(cachedCanCollide) == nil then return end

		for part, canCollide in cachedCanCollide do
			if part.Parent then
				part.CanCollide = canCollide
			end
		end

		table.clear(cachedCanCollide)
		return
	end

	if next(cachedCanCollide) ~= nil then return end

	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") and part ~= handle then
			cachedCanCollide[part] = part.CanCollide
			part.CanCollide = false
		end
	end
end

local function exitHeldState()
	if heldWeld then
		heldWeld:Destroy()
		heldWeld = nil
	end

	for _, weld in wheelLockWelds do
		weld:Destroy()
	end

	table.clear(wheelLockWelds)
end

local function enterHeldState()
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero

	setHingeActuator(Enum.ActuatorType.None)

	for _, wheelPart in getWheelParts() do
		local lockWeld = Instance.new("WeldConstraint")
		lockWeld.Name = "WheelLockWeld"
		lockWeld.Part0 = chassis
		lockWeld.Part1 = wheelPart
		lockWeld.Parent = chassis
		table.insert(wheelLockWelds, lockWeld)
	end

	local weld = Instance.new("Weld")
	weld.Name = "HeldWeld"
	weld.Part0 = handle
	weld.Part1 = chassis
	weld.C0 = CFrame.fromOrientation(math.rad(85), math.rad(-45), math.rad(35))
	weld.C1 = CFrame.new()
	weld.Parent = handle
	heldWeld = weld
end

local function teardown(destroyBoard: boolean)
	if not currentOccupant then return end

	local player = currentOccupant
	currentOccupant = nil
	isRiding = false

	if riderWeld then
		riderWeld:Destroy()
		riderWeld = nil
	end

	local character = player.Character
	if character then
		local root = character.PrimaryPart
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and cachedRootMassless ~= nil then
			root.Massless = cachedRootMassless
		end

		if humanoid then
			humanoid.PlatformStand = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	cachedRootMassless = nil

	setHingeActuator(Enum.ActuatorType.None)

	if chassis.Parent then
		pcall(function()
			chassis:SetNetworkOwner(nil)
		end)
	end

	ownerValue.Value = nil
	boardRig:SetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE, 0)
	boardRig:SetAttribute(Constants.STEERING_INPUT_ATTRIBUTE, 0)

	clearConnections()

	if destroyBoard then
		tool:Destroy()
		return
	end

	enterHeldState()
end

local function tryMount(player: Player): boolean
	if currentOccupant then return false end

	local character = player.Character
	if not character then return false end

	local root = character.PrimaryPart
	if not root then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	if humanoid.Health <= 0 then return false end

	exitHeldState()
	setBoardCollisions(true)

	local levelPosition = chassis.Position
	local _, playerYaw = root.CFrame:ToOrientation()
	local newChassisCFrame = CFrame.new(levelPosition) * CFrame.fromOrientation(0, playerYaw, 0)
	local delta = newChassisCFrame * chassis.CFrame:Inverse()

	boardRig:PivotTo(delta * boardRig:GetPivot())

	for _, wheelPart in getWheelParts() do
		wheelPart.AssemblyLinearVelocity = Vector3.zero
		wheelPart.AssemblyAngularVelocity = Vector3.zero
	end
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero

	currentOccupant = player
	cachedRootMassless = root.Massless
	isRiding = true

	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, true)
	humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
	humanoid.PlatformStand = true

	local hipHeight = GetTrueHipHeight(character)
	local chassisTopWorld = chassis.CFrame * CFrame.new(0, chassis.Size.Y / 2, 0)
	local forward = chassis.CFrame.LookVector
	local placePos = chassisTopWorld.Position + Vector3.new(0, hipHeight, 0)
	root.CFrame = CFrame.lookAt(placePos, placePos + forward)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "RiderWeld"
	weld.Part0 = root
	weld.Part1 = chassis
	weld.Parent = root
	riderWeld = weld

	root.Massless = true

	setHingeActuator(Enum.ActuatorType.Motor)

	pcall(function()
		chassis:SetNetworkOwner(player)
	end)

	ownerValue.Value = player

	table.insert(connections, humanoid.Died:Connect(function()
		teardown(true)
	end))
	table.insert(connections, character.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
		if parent == nil then
			teardown(true)
		end
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(leavingPlayer: Player)
		if leavingPlayer == player then
			teardown(true)
		end
	end))

	return true
end

local function getEquippedPlayer(): Player?
	local character = tool.Parent
	if not character or not character:IsA("Model") then return nil end

	return Players:GetPlayerFromCharacter(character)
end

local function onActivated()
	local player = getEquippedPlayer()
	if not player then return end

	if isRiding then
		if currentOccupant ~= player then return end

		teardown(false)
		setBoardCollisions(false)
		return
	end

	local lockedPlayer = ownerLockValue.Value
	if lockedPlayer and lockedPlayer ~= player then return end

	tryMount(player)
end

local function onEquipped()
	if isRiding then return end

	setBoardCollisions(false)
end

local function onUnequipped()
	if isRiding then
		teardown(false)
	end

	setBoardCollisions(true)
end

local function initialize()
	enterHeldState()
	tool.Activated:Connect(onActivated)
	tool.Equipped:Connect(onEquipped)
	tool.Unequipped:Connect(onUnequipped)
end

initialize()

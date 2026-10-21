-- Persisted authoritative server lifecycle for an edit-time WaterVehicle2 rig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local model = script.Parent
assert(model and model:IsA("Model"), "WaterVehicle2Server must be parented to the vessel")

local root = model:WaitForChild("HullRoot") :: BasePart
local seat = model:WaitForChild("DriverSeat") :: VehicleSeat
local ballasts = model:WaitForChild("Ballasts")
local prompt = seat:FindFirstChild("DrivePrompt")
local surge = root:WaitForChild("SurgeVelocity") :: LinearVelocity
local yaw = root:WaitForChild("YawVelocity") :: AngularVelocity
local WaterUtils = require(ReplicatedStorage.Shared.Utils.WaterUtils)

local BALLAST_KP = 4
local MAX_VERTICAL_SPEED = 20
local PLOP_THRESHOLD = 30
local lastDriver: Player? = nil

local function setOwner(owner: Player?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(descendant.SetNetworkOwner, descendant, owner)
		end
	end
end

local function setCharacterMassless(character: Model, value: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then descendant.Massless = value end
	end
end

local function setCharacterVisible(character: Model, visible: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant.Name ~= "HumanoidRootPart"
			and (descendant:IsA("BasePart") or descendant:IsA("Decal"))
		then
			descendant.Transparency = if visible then 0 else 1
		end
	end
end

local function updateBallasts()
	local draftOffset = root:GetAttribute("DraftOffset") or 0
	for _, ballast in ballasts:GetChildren() do
		if not ballast:IsA("BasePart") then continue end
		local velocity = ballast:FindFirstChild("BuoyancyVelocity")
		if not velocity or not velocity:IsA("LinearVelocity") then continue end
		local waterLevel = WaterUtils.getWaterLevel(ballast.Position)
		if not waterLevel then
			velocity.VectorVelocity = Vector3.zero
			continue
		end
		local error = (waterLevel + draftOffset) - ballast.Position.Y
		if error <= -PLOP_THRESHOLD then
			velocity.VectorVelocity = Vector3.zero
		else
			velocity.VectorVelocity = Vector3.new(
				0,
				math.clamp(error * BALLAST_KP, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED),
				0
			)
		end
	end
end

if prompt and prompt:IsA("ProximityPrompt") then
	prompt.Triggered:Connect(function(player)
		if seat.Occupant then return end
		local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then seat:Sit(humanoid) end
	end)
end

seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local humanoid = seat.Occupant
	if humanoid then
		local player = Players:GetPlayerFromCharacter(humanoid.Parent)
		if not player then return end
		lastDriver = player
		setOwner(player)
		setCharacterMassless(humanoid.Parent, true)
		setCharacterVisible(humanoid.Parent, false)
		if prompt then prompt.Enabled = false end
	else
		if lastDriver and lastDriver.Character then
			local character = lastDriver.Character
			setCharacterMassless(character, false)
			setCharacterVisible(character, true)
			character:PivotTo(model:GetPivot() * CFrame.new(-6, 4, 0))
		end
		lastDriver = nil
		for _, ballast in ballasts:GetChildren() do
			local velocity = ballast:FindFirstChild("BuoyancyVelocity")
			if velocity and velocity:IsA("LinearVelocity") then velocity.VectorVelocity = Vector3.zero end
		end
		surge.VectorVelocity = Vector3.zero
		yaw.AngularVelocity = Vector3.zero
		setOwner(nil)
		if prompt then prompt.Enabled = true end
	end
end)

setOwner(nil)
RunService.Heartbeat:Connect(function()
	if seat.Occupant then return end
	updateBallasts()
	surge.VectorVelocity = Vector3.zero
	yaw.AngularVelocity = Vector3.zero
end)

script:SetAttribute("RuntimeVersion", 1)
script:SetAttribute("RuntimeReady", true)

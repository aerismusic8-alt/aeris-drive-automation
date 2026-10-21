-- Persisted authoritative server lifecycle for an edit-time WaterSubmersible rig.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local model = script.Parent
assert(model and model:IsA("Model"), "WaterSubmersibleServer must be parented to the vessel")

local root = model:WaitForChild("HullRoot") :: BasePart
local seat = model:WaitForChild("DriverSeat") :: VehicleSeat
local prompt = seat:FindFirstChild("DrivePrompt")
local surge = root:WaitForChild("SurgeVelocity") :: LinearVelocity
local yaw = root:WaitForChild("YawVelocity") :: AngularVelocity
local depth = root:WaitForChild("DepthVelocity") :: LinearVelocity
local holdDepthY = root.Position.Y
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
			character:PivotTo(model:GetPivot() * CFrame.new(10, 10, 10))
		end
		lastDriver = nil
		holdDepthY = root.Position.Y
		setOwner(nil)
		if prompt then prompt.Enabled = true end
	end
end)

setOwner(nil)
RunService.Heartbeat:Connect(function()
	if seat.Occupant then return end
	local speed = math.clamp((holdDepthY - root.Position.Y) * 4, -5, 5)
	surge.VectorVelocity = Vector3.zero
	yaw.AngularVelocity = Vector3.zero
	depth.VectorVelocity = Vector3.new(0, speed, 0)
end)

script:SetAttribute("RuntimeVersion", 1)
script:SetAttribute("RuntimeReady", true)

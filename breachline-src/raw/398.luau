if not script.Parent:IsA("Model") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = ReplicatedStorage:WaitForChild("FourD"):WaitForChild("Behaviors"):WaitForChild("Gunnable"):WaitForChild("Common")
local Controller = require(Common:WaitForChild("Controller"))

local model = script.Parent

local updateTurretEvent = model:FindFirstChild("UpdateTurret")

if not updateTurretEvent then
	warn("[TurretServer] Missing required instances, aborting")
	return
end

local driverSeatRef = model:FindFirstChild("Gunnable_DriverSeatRef")
local gunnerSeatRef = model:FindFirstChild("Gunnable_GunnerSeatRef")
local driverSeat: VehicleSeat? = if driverSeatRef and driverSeatRef:IsA("ObjectValue") then driverSeatRef.Value else nil
local gunnerSeat: Seat? = if gunnerSeatRef and gunnerSeatRef:IsA("ObjectValue") then gunnerSeatRef.Value else nil
local swapRoleEvent: RemoteEvent? = model:FindFirstChild("SwapRole")
local gunnerPrompt = model:FindFirstChild("GunnerPrompt", true)

local seatOpts = {
	PrimarySeat = driverSeat,
	SecondarySeat = gunnerSeat,
}

Controller.setOverride(model, nil)

local pitchUpRad = math.rad(model:GetAttribute("gunnerPitchUp") or 60)
local pitchDownRad = math.rad(model:GetAttribute("gunnerPitchDown") or 25)

local firstPersonMode = model:GetAttribute("Gunnable_FirstPerson") == true
local disablePitch = model:GetAttribute("Gunnable_DisablePitch") == true
local disableYaw = model:GetAttribute("Gunnable_DisableYaw") == true

local savedTransparency: { [Instance]: { [Instance]: number } } = {}

local function hideCharacter(character: Instance?)
	if not character then return end
	savedTransparency[character] = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") or part:IsA("Texture") then
			savedTransparency[character][part] = part.Transparency
			part.Transparency = 1
		end
	end
end

local function showCharacter(character: Instance?)
	if not character or not savedTransparency[character] then return end
	for part, t in pairs(savedTransparency[character]) do
		if part and part.Parent then part.Transparency = t end
	end

	savedTransparency[character] = nil
end

local savedCollide: { [Instance]: { [BasePart]: boolean } } = {}
local savedQuery: { [Instance]: { [BasePart]: boolean } } = {}

local function disablePlayerPhysics(character: Instance?)
	if not character then return end
	savedCollide[character] = {}
	savedQuery[character] = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			savedCollide[character][part] = part.CanCollide
			savedQuery[character][part] = part.CanQuery
			part.CanCollide = false
			part.CanQuery = false
		end
	end
end

local function restorePlayerPhysics(character: Instance?)
	if not character then return end
	if savedCollide[character] then
		for part, canCollide in pairs(savedCollide[character]) do
			if part and part.Parent then part.CanCollide = canCollide end
		end

		savedCollide[character] = nil
	end
	if savedQuery[character] then
		for part, canQuery in pairs(savedQuery[character]) do
			if part and part.Parent then part.CanQuery = canQuery end
		end

		savedQuery[character] = nil
	end
end

local currentGunner: Player? = nil
local currentDriverCharacter: Instance? = nil
local swapping = false

local function updateGunnerPrompt()
	if not gunnerPrompt or not gunnerSeat then return end
	local driverTaken = driverSeat and driverSeat.Occupant ~= nil
	local gunnerTaken = gunnerSeat.Occupant ~= nil
	gunnerPrompt.Enabled = driverTaken and not gunnerTaken
end

local function syncGunnerActive()
	local active = false
	if gunnerSeat and gunnerSeat.Occupant then
		active = true
	else
		local override = Controller.getOverridePlayer(model)
		if override then
			local driverPlayer = if driverSeat and driverSeat.Occupant
				then Players:GetPlayerFromCharacter(driverSeat.Occupant.Parent)
				else nil
			active = override ~= driverPlayer
		end
	end

	model:SetAttribute("gunnerActive", active)
end

if gunnerSeat then
	gunnerSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = gunnerSeat.Occupant
		if occupant then
			local character = occupant.Parent
			currentGunner = Players:GetPlayerFromCharacter(character)
			if not swapping then
				hideCharacter(character)
			end
		else
			if currentGunner and currentGunner.Character and not swapping then
				showCharacter(currentGunner.Character)
			end
			currentGunner = nil
			model:SetAttribute("turretYaw", 0)
			model:SetAttribute("turretPitch", 0)
		end

		syncGunnerActive()
		updateGunnerPrompt()
	end)
end

if driverSeat then
	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if firstPersonMode then
			local occupant = driverSeat.Occupant
			if occupant then
				currentDriverCharacter = occupant.Parent
				hideCharacter(currentDriverCharacter)
				disablePlayerPhysics(currentDriverCharacter)
			elseif currentDriverCharacter then
				showCharacter(currentDriverCharacter)
				restorePlayerPhysics(currentDriverCharacter)
				currentDriverCharacter = nil
			end
		end

		updateGunnerPrompt()
	end)
end

model:GetAttributeChangedSignal(Controller.OVERRIDE_ATTR):Connect(syncGunnerActive)
syncGunnerActive()

if gunnerPrompt and gunnerSeat then
	gunnerPrompt.Triggered:Connect(function(triggerPlayer: Player)
		if gunnerSeat.Occupant then return end
		if driverSeat and driverSeat.Occupant then
			local driverChar = driverSeat.Occupant.Parent
			if driverChar == triggerPlayer.Character then return end
		end

		local humanoid = triggerPlayer.Character and triggerPlayer.Character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			gunnerSeat:Sit(humanoid)
		end
	end)
end

if swapRoleEvent and gunnerSeat then
	swapRoleEvent.OnServerEvent:Connect(function(player: Player)
		if swapping then return end
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then return end

		local isInDriver = driverSeat and driverSeat.Occupant and driverSeat.Occupant.Parent == character
		local isInGunner = gunnerSeat.Occupant and gunnerSeat.Occupant.Parent == character

		if isInDriver and not gunnerSeat.Occupant then
			swapping = true
			hideCharacter(character)
			humanoid.Sit = false
			task.wait()
			gunnerSeat:Sit(humanoid)
			swapping = false
		elseif isInGunner and driverSeat and not driverSeat.Occupant then
			swapping = true
			showCharacter(character)
			humanoid.Sit = false
			task.wait()
			driverSeat:Sit(humanoid)
			swapping = false
		end
	end)
end

updateTurretEvent.OnServerEvent:Connect(function(player: Player, yaw: number, pitch: number)
	local controller = Controller.resolve(model, seatOpts)
	if controller ~= player then return end
	if typeof(yaw) ~= "number" or typeof(pitch) ~= "number" then return end
	if yaw ~= yaw or pitch ~= pitch then return end

	yaw = if disableYaw then 0 else yaw
	pitch = if disablePitch then 0 else math.clamp(pitch, -pitchDownRad, pitchUpRad)

	model:SetAttribute("turretYaw", yaw)
	model:SetAttribute("turretPitch", pitch)
end)

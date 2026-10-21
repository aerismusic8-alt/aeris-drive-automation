--[[
	File: MountAuthority.server.luau
]]--

if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then
	return
end

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Object References

local scriptsFolder = script.Parent
local rotorModel = scriptsFolder.Parent :: Model
local root = rotorModel:WaitForChild("HullRoot") :: BasePart
local mountPrompt = root:WaitForChild("MountPrompt") :: ProximityPrompt
local unmountRemote = rotorModel:WaitForChild("UnmountRequest") :: RemoteEvent
local swapRemote = rotorModel:WaitForChild("SwapSeatRequest") :: RemoteEvent
local bodyVelocity = root:WaitForChild("BodyVelocity") :: LinearVelocity
local bodyOrientation = root:WaitForChild("BodyOrientation") :: AlignOrientation

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local AirVehicleCommon = FourD.Architects.AirVehicle.Common
local Dumpster = require(FourD.Libs.Dumpster)
local Mounting = require(AirVehicleCommon.Mounting)
local NetworkOwnership = require(AirVehicleCommon.NetworkOwnership)
local SeatSwap = require(AirVehicleCommon.SeatSwap)
local InputConstants = require(AirVehicleCommon.Scripts.InputConstants)

-- Constants

local GUNNER_SEAT_REF_NAME = "AirVehicle_GunnerSeatRef"
local RIDER_VISIBLE_ATTRIBUTE = "RiderVisible"
local RIDER_PLATFORM_STAND_ATTRIBUTE = "RiderPlatformStand"
local MIN_DISMOUNT_IMPULSE_SPEED = 1

-- Module State

local mainDump = Dumpster.new()
local mountSession: Mounting.MountSession? = nil
local swapping = false

-- Local Functions

local function applyDismountImpulse(exitVelocity: Vector3)
	if exitVelocity.Magnitude < MIN_DISMOUNT_IMPULSE_SPEED then return end

	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		if connection then
			connection:Disconnect()
			connection = nil
		end

		if mountSession or not root.Parent then return end

		local mass = root.AssemblyMass
		if mass <= 0 then return end

		root:ApplyImpulse((exitVelocity - root.AssemblyLinearVelocity) * mass)
	end)
end

local function mountPlayer(player: Player)
	if mountSession then return end

	local riderVisible = root:GetAttribute(RIDER_VISIBLE_ATTRIBUTE)
	local riderPlatformStand = root:GetAttribute(RIDER_PLATFORM_STAND_ATTRIBUTE)

	mountSession = Mounting.tryMount({
		Player = player,
		Root = root,
		VehicleModel = rotorModel,
		ParentDump = mainDump,
		PilotUserIdAttribute = InputConstants.PILOT_USER_ID_ATTRIBUTE,
		HideCharacter = not riderVisible,
		PlatformStand = riderPlatformStand,
		OnMounted = function()
			mountPrompt.Enabled = false
			bodyOrientation.CFrame = root.CFrame
			bodyVelocity.VectorVelocity = Vector3.zero
			bodyVelocity.Enabled = true
			bodyOrientation.Enabled = true
		end,
		OnUnmounted = function(skipTeleport: boolean)
			local exitVelocity = root.AssemblyLinearVelocity
			bodyVelocity.VectorVelocity = Vector3.zero
			bodyVelocity.Enabled = false
			bodyOrientation.CFrame = root.CFrame
			bodyOrientation.Enabled = false
			if mountPrompt.Parent then
				mountPrompt.Enabled = true
			end
			mountSession = nil
			applyDismountImpulse(exitVelocity)
			if not skipTeleport then
				unmountRemote:FireClient(player)
			end
		end,
	})
end

local function unmountPlayer(skipTeleport: boolean?)
	local session = mountSession
	if not session then return end
	session.Unmount(skipTeleport == true)
end

local function getGunnerSeat(): Seat?
	local ref = rotorModel:FindFirstChild(GUNNER_SEAT_REF_NAME)
	if ref and ref:IsA("ObjectValue") and ref.Value and ref.Value:IsA("Seat") then
		return ref.Value :: Seat
	end
	return nil
end

local function handleSeatSwap(player: Player)
	local gunnerSeat = getGunnerSeat()
	if not gunnerSeat then return end
	if swapping then return end

	local humanoid = SeatSwap.getHumanoid(player)
	if not humanoid then return end

	local session = mountSession
	local isPilot = session ~= nil and session.Player == player

	if isPilot then
		if gunnerSeat.Occupant ~= nil then return end

		swapping = true
		unmountPlayer(true)
		SeatSwap.forceSit(gunnerSeat, humanoid)
		swapping = false
		return
	end

	if SeatSwap.occupiedBy(gunnerSeat, player) then
		if mountSession ~= nil then return end

		swapping = true
		SeatSwap.eject(humanoid)
		RunService.Heartbeat:Wait()
		if player.Parent ~= nil and mountSession == nil then
			mountPlayer(player)
		end
		swapping = false
	end
end

-- Startup

NetworkOwnership.setOwner(rotorModel, nil)

mainDump:Connect(mountPrompt.Triggered, function(player: Player)
	mountPlayer(player)
end)

mainDump:Connect(unmountRemote.OnServerEvent, function(player: Player)
	local session = mountSession
	if not session then return end
	if player ~= session.Player then return end
	unmountPlayer(false)
end)

mainDump:Connect(swapRemote.OnServerEvent, function(player: Player)
	handleSeatSwap(player)
end)

mainDump:Connect(RunService.Heartbeat, function()
	if mountSession then return end

	bodyVelocity.VectorVelocity = Vector3.zero
end)

mainDump:Connect(rotorModel.Destroying, function()
	if mountSession then
		unmountPlayer(true)
	end
end)

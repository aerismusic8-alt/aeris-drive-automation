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
local planeModel = scriptsFolder.Parent :: Model
local root = planeModel:WaitForChild("HullRoot") :: BasePart
local mountPrompt = root:WaitForChild("MountPrompt") :: ProximityPrompt
local unmountRemote = planeModel:WaitForChild("UnmountRequest") :: RemoteEvent
local swapRemote = planeModel:WaitForChild("SwapSeatRequest") :: RemoteEvent
local surgeVelocity = root:WaitForChild("SurgeVelocity") :: LinearVelocity
local liftForce = root:WaitForChild("LiftForce") :: VectorForce
local orientationAngularVelocity = root:WaitForChild("OrientationAngularVelocity") :: AngularVelocity

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

	mountSession = Mounting.tryMount({
		Player = player,
		Root = root,
		VehicleModel = planeModel,
		ParentDump = mainDump,
		PilotUserIdAttribute = InputConstants.PILOT_USER_ID_ATTRIBUTE,
		OnMounted = function()
			mountPrompt.Enabled = false
			surgeVelocity.VectorVelocity = Vector3.zero
			surgeVelocity.Enabled = true
			liftForce.Force = Vector3.zero
			liftForce.Enabled = true
			orientationAngularVelocity.AngularVelocity = Vector3.zero
			orientationAngularVelocity.Enabled = true
		end,
		OnUnmounted = function(skipTeleport: boolean)
			local exitVelocity = root.AssemblyLinearVelocity
			surgeVelocity.VectorVelocity = Vector3.zero
			surgeVelocity.Enabled = false
			liftForce.Force = Vector3.zero
			liftForce.Enabled = false
			orientationAngularVelocity.AngularVelocity = Vector3.zero
			orientationAngularVelocity.Enabled = false
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
	local ref = planeModel:FindFirstChild(GUNNER_SEAT_REF_NAME)
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

NetworkOwnership.setOwner(planeModel, nil)

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

mainDump:Connect(planeModel.Destroying, function()
	if mountSession then
		unmountPlayer(true)
	end
end)

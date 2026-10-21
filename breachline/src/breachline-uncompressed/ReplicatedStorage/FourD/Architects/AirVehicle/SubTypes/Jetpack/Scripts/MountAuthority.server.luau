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
local jetpackModel = scriptsFolder.Parent :: Model
local root = jetpackModel:WaitForChild("HullRoot") :: BasePart
local mountPrompt = root:WaitForChild("MountPrompt") :: ProximityPrompt
local unmountRemote = jetpackModel:WaitForChild("UnmountRequest") :: RemoteEvent
local bodyVelocity = root:WaitForChild("BodyVelocity") :: LinearVelocity
local bodyOrientation = root:WaitForChild("BodyOrientation") :: AlignOrientation

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local AirVehicleCommon = FourD.Architects.AirVehicle.Common
local Dumpster = require(FourD.Libs.Dumpster)
local Mounting = require(AirVehicleCommon.Mounting)
local NetworkOwnership = require(AirVehicleCommon.NetworkOwnership)
local InputConstants = require(AirVehicleCommon.Scripts.InputConstants)

-- Constants

local BACK_OFFSET_ATTRIBUTE = "BackOffset"
-- Prefix mirrors Construction/BuildThrusters.luau VFX_CLONE_PREFIX; VFX clones are
-- discovered by name because the rig has no serialized reference list.
local VFX_CLONE_PREFIX = "JetFlameRoot_"

-- Module State

local mainDump = Dumpster.new()
local mountSession: Mounting.MountSession? = nil

-- Local Functions

local function collectVfxClones(): { Model }
	local clones: { Model } = {}
	for _, child in jetpackModel:GetChildren() do
		if child:IsA("Model") and string.sub(child.Name, 1, #VFX_CLONE_PREFIX) == VFX_CLONE_PREFIX then
			table.insert(clones, child)
		end
	end
	return clones
end

local function setVfxClonesEnabled(vfxClones: { Model }, enabled: boolean)
	for _, clone in vfxClones do
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
				descendant.Enabled = enabled
			end
		end
	end
end

local vfxClones = collectVfxClones()

local function mountPlayer(player: Player)
	if mountSession then return end

	local backOffset = root:GetAttribute(BACK_OFFSET_ATTRIBUTE) :: number?

	mountSession = Mounting.tryWear({
		Player = player,
		Root = root,
		VehicleModel = jetpackModel,
		ParentDump = mainDump,
		PilotUserIdAttribute = InputConstants.PILOT_USER_ID_ATTRIBUTE,
		BackOffset = backOffset,
		OnMounted = function()
			mountPrompt.Enabled = false
			bodyOrientation.CFrame = root.CFrame
			bodyVelocity.VectorVelocity = Vector3.zero
			bodyVelocity.Enabled = true
			bodyOrientation.Enabled = true
			setVfxClonesEnabled(vfxClones, true)
		end,
		OnUnmounted = function(_skipTeleport: boolean)
			bodyVelocity.VectorVelocity = Vector3.zero
			bodyVelocity.Enabled = false
			bodyOrientation.CFrame = root.CFrame
			bodyOrientation.Enabled = false
			setVfxClonesEnabled(vfxClones, false)
			if mountPrompt.Parent then
				mountPrompt.Enabled = true
			end
			mountSession = nil
		end,
	})
end

local function unmountPlayer(skipTeleport: boolean?)
	local session = mountSession
	if not session then return end
	session.Unmount(skipTeleport == true)
end

-- Startup

NetworkOwnership.setOwner(jetpackModel, nil)

mainDump:Connect(mountPrompt.Triggered, function(player: Player)
	mountPlayer(player)
end)

mainDump:Connect(unmountRemote.OnServerEvent, function(player: Player)
	local session = mountSession
	if not session then return end
	if player ~= session.Player then return end
	unmountPlayer(false)
end)

mainDump:Connect(RunService.Heartbeat, function()
	if mountSession then return end

	bodyVelocity.VectorVelocity = Vector3.zero
end)

mainDump:Connect(jetpackModel.Destroying, function()
	if mountSession then
		unmountPlayer(true)
	end
end)

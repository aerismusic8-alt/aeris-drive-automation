-- GENERATED WRAPPER around upstream Controller.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: Controller.server.luau
]]--

if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then
	return
end

-- Roblox Services

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Object References

local scriptsFolder = script.Parent
local rotorModel = scriptsFolder.Parent
local root = rotorModel:WaitForChild("HullRoot") :: BasePart
local mountPrompt = root:FindFirstChild("MountPrompt") :: ProximityPrompt?
local unmountRemote = rotorModel:WaitForChild("UnmountRequest") :: RemoteEvent
local bodyVelocity = root:WaitForChild("BodyVelocity") :: LinearVelocity
local bodyOrientation = root:WaitForChild("BodyOrientation") :: AlignOrientation

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Constants = require(scriptsFolder:WaitForChild("Constants"))
local Performance = require(scriptsFolder:WaitForChild("Performance"))
local Camera = require(scriptsFolder:WaitForChild("Camera"))
local Physics = require(scriptsFolder:WaitForChild("Physics"))
local FX = require(scriptsFolder:WaitForChild("FX"))
local Hud = require(scriptsFolder:WaitForChild("Hud"))
local Input = require(scriptsFolder:WaitForChild("Input"))
local SeatSwapInput = require(FourD.Architects.AirVehicle.Common.Scripts.SeatSwapInput)
local HelpUI = require(FourD.Common.HelpUI)
local Keybinds = require(FourD.Common.Keybinds)
local getExternalCFrame = require(FourD.Common.getExternalCFrame)

-- Constants

local PILOT_WELD_NAME = "PilotWeld"
local WELD_REMOVAL_TIMEOUT = 1

-- Module State

local localPlayer = Players.LocalPlayer
local active = false
local steppedConnection: RBXScriptConnection? = nil
local PromptSuppression = require(game:GetService("ReplicatedStorage"):WaitForChild("FourD"):WaitForChild("Common"):WaitForChild("PromptSuppression"))
local promptSuppressionHeld = false

-- Local Functions

local function vprint(...: any)
	if not Constants.VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function pilotHelpFilter(): { string }?
	local gunnerSeatRef = rotorModel:FindFirstChild("AirVehicle_GunnerSeatRef")
	local hasGunnerSeat = gunnerSeatRef ~= nil
		and gunnerSeatRef:IsA("ObjectValue")
		and gunnerSeatRef.Value ~= nil
	if hasGunnerSeat then
		return nil
	end

	local ids: { string } = {}
	for _, bind in Keybinds.resolve("AirVehicle.Rotor", rotorModel).Binds do
		if bind.Id ~= "SwapSeat" then
			table.insert(ids, bind.Id)
		end
	end

	return ids
end

local function activate()
	if active then return end
	active = true
	vprint("Activating rotor controller")

	if mountPrompt then
		mountPrompt.Enabled = false
	end

	if not promptSuppressionHeld then
		promptSuppressionHeld = true
		PromptSuppression.acquire()
	end

	local performance = Performance.read(root)

	Camera.enable(rotorModel, root, performance)
	Physics.enable(root, bodyVelocity, bodyOrientation, performance)
	FX.enable(rotorModel, root)
	Hud.enable(rotorModel, root)
	Input.enable(unmountRemote, performance.PitchFollow)

	steppedConnection = RunService.Stepped:Connect(function(_: number, dt: number)
		local inputs = Input.poll()
		local intensityRatio, speedRatio = Physics.step(dt, inputs)
		Camera.setSpeedRatio(speedRatio)
		FX.update(intensityRatio, speedRatio, dt)
	end)

	HelpUI.applyRole(rotorModel, "AirVehicle.Rotor", "HelpUI_PilotState", { Filter = pilotHelpFilter() })
end

local function deactivate()
	if not active then return end
	active = false
	vprint("Deactivating rotor controller")

	if steppedConnection then
		steppedConnection:Disconnect()
		steppedConnection = nil
	end

	Input.disable()
	Hud.disable()
	FX.disable()
	Physics.disable()
	Camera.disable()

	if mountPrompt and mountPrompt.Parent then
		mountPrompt.Enabled = true
	end

	if promptSuppressionHeld then
		promptSuppressionHeld = false
		PromptSuppression.release()
	end

	HelpUI.clearRole(rotorModel)
end

local function onPilotChanged()
	local pilotUserId = root:GetAttribute(Constants.PILOT_USER_ID_ATTRIBUTE) or 0
	if pilotUserId == localPlayer.UserId then
		activate()
	else
		deactivate()
	end
end

local function teleportOutsideVehicle()
	local character = localPlayer.Character
	if not character then return end

	local rootPart = character.PrimaryPart
	if not rootPart then return end

	local elapsed = 0
	while rootPart:FindFirstChild(PILOT_WELD_NAME) and elapsed < WELD_REMOVAL_TIMEOUT do
		elapsed += RunService.Heartbeat:Wait()
	end

	character:PivotTo(getExternalCFrame(rotorModel, "Left"))
end

unmountRemote.OnClientEvent:Connect(teleportOutsideVehicle)

SeatSwapInput.start({
	Root = root,
	VehicleModel = rotorModel,
	SetId = "AirVehicle.Rotor",
})

root:GetAttributeChangedSignal(Constants.PILOT_USER_ID_ATTRIBUTE):Connect(onPilotChanged)
rotorModel.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
	if parent == nil then
		deactivate()
	end
end)

onPilotChanged()

end
i

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
local jetpackModel = scriptsFolder.Parent
local root = jetpackModel:WaitForChild("HullRoot") :: BasePart
local mountPrompt = root:FindFirstChild("MountPrompt") :: ProximityPrompt?
local unmountRemote = jetpackModel:WaitForChild("UnmountRequest") :: RemoteEvent
local bodyVelocity = root:WaitForChild("BodyVelocity") :: LinearVelocity
local bodyOrientation = root:WaitForChild("BodyOrientation") :: AlignOrientation

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local HelpUI = require(FourD.Common.HelpUI)

local Constants = require(scriptsFolder:WaitForChild("Constants"))
local Performance = require(scriptsFolder:WaitForChild("Performance"))
local Camera = require(scriptsFolder:WaitForChild("Camera"))
local Physics = require(scriptsFolder:WaitForChild("Physics"))
local FX = require(scriptsFolder:WaitForChild("FX"))
local Hud = require(scriptsFolder:WaitForChild("Hud"))
local Input = require(scriptsFolder:WaitForChild("Input"))

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

local function activate()
	if active then return end
	active = true
	vprint("Activating jetpack controller")

	if mountPrompt then
		mountPrompt.Enabled = false
	end

	if not promptSuppressionHeld then
		promptSuppressionHeld = true
		PromptSuppression.acquire()
	end

	local performance = Performance.read(root)

	Camera.enable(jetpackModel, root, performance)
	Physics.enable(root, bodyVelocity, bodyOrientation, performance)
	FX.enable(jetpackModel, root)
	Hud.enable(jetpackModel, root)
	Input.enable(unmountRemote)

	steppedConnection = RunService.Stepped:Connect(function(_time: number, dt: number)
		local inputs = Input.poll()
		local intensityRatio, speedRatio = Physics.step(dt, inputs)
		FX.update(intensityRatio, speedRatio, dt)
	end)

	HelpUI.applyRole(jetpackModel, "AirVehicle.Jetpack", "HelpUI_PilotState")
end

local function deactivate()
	if not active then return end
	active = false
	vprint("Deactivating jetpack controller")

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

	HelpUI.clearRole(jetpackModel)
end

local function onPilotChanged()
	local pilotUserId = root:GetAttribute(Constants.PILOT_USER_ID_ATTRIBUTE) or 0
	if pilotUserId == localPlayer.UserId then
		activate()
	else
		deactivate()
	end
end

root:GetAttributeChangedSignal(Constants.PILOT_USER_ID_ATTRIBUTE):Connect(onPilotChanged)
jetpackModel.AncestryChanged:Connect(function(_child: Instance, parent: Instance?)
	if parent == nil then
		deactivate()
	end
end)

onPilotChanged()

end

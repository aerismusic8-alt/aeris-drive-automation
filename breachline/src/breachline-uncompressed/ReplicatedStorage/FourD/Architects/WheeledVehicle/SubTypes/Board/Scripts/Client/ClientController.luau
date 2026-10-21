-- GENERATED WRAPPER around upstream ClientController.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: ClientController/init.server.luau
	RunContext: Client
]]--

if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then return end

-- Roblox Services

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local Animator = require(script.Parent.Parent.Animator)
local Constants = require(script.Parent.Parent.Constants)
local Controller = require(script.Parent.Parent.Controller)
local Input = require(script.Parent.Input)
local HelpUI = require(ReplicatedStorage:WaitForChild("FourD").Common.HelpUI)

-- Object References

local localPlayer = Players.LocalPlayer
local boardRig = script.Parent.Parent.Parent
local board = boardRig.Parent
local ownerValue = boardRig:WaitForChild(Constants.OWNER_VALUE_NAME)

-- State

local isControlling = false
local connections: { RBXScriptConnection } = {}
local controllerStop: (() -> ())? = nil
local inputStop: (() -> ())? = nil
local animatorStop: (() -> ())? = nil
local PromptSuppression = require(game:GetService("ReplicatedStorage"):WaitForChild("FourD"):WaitForChild("Common"):WaitForChild("PromptSuppression"))
local promptSuppressionHeld = false

-- Local Functions

local function startControlling()
	if isControlling then return end

	local character = localPlayer.Character
	if not character then return end

	isControlling = true

	-- Hide all proximity prompts (including any mount prompt) while riding.
	if not promptSuppressionHeld then
		promptSuppressionHeld = true
		PromptSuppression.acquire()
	end

	controllerStop = Controller.start(boardRig, character)
	inputStop = Input.start(boardRig, character)
	animatorStop = Animator.start(boardRig, character)

	HelpUI.applyRole(board, "WheeledVehicle.Board", "HelpUI_DriverState")
end

local function stopControlling()
	if not isControlling then return end

	isControlling = false

	if promptSuppressionHeld then
		promptSuppressionHeld = false
		PromptSuppression.release()
	end

	HelpUI.clearRole(board)

	if animatorStop then
		animatorStop()
		animatorStop = nil
	end

	if inputStop then
		inputStop()
		inputStop = nil
	end

	if controllerStop then
		controllerStop()
		controllerStop = nil
	end
end

local function onOwnerChanged()
	if ownerValue.Value == localPlayer then
		startControlling()
	else
		stopControlling()
	end
end

local function initialize()
	table.insert(connections, ownerValue.Changed:Connect(onOwnerChanged))
	table.insert(connections, board.Destroying:Connect(stopControlling))

	onOwnerChanged()
end

initialize()

end

--[[
GunnerCoop - Runtime gunner state machine cloned into the assembled plane
model. Manages: gunner prompt visibility (gated on pilot presence + seat
empty), character hide/show on seat occupant change, and dynamic firer
override (gunner seated -> gunner; else pilot if mounted; else nobody).
]]

if not script.Parent:IsA("Model") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local CharacterUtils = require(FourD:WaitForChild("Architects"):WaitForChild("AirVehicle"):WaitForChild("Common"):WaitForChild("CharacterUtils"))
local Controller = require(FourD:WaitForChild("Behaviors"):WaitForChild("Gunnable"):WaitForChild("Common"):WaitForChild("Controller"))
local HelpUI = require(FourD:WaitForChild("Common"):WaitForChild("HelpUI"))

local PILOT_USER_ID_ATTR = "PilotUserId"

local planeModel = script.Parent
local helpStatePilotNoGunner = planeModel:GetAttribute("HelpUI_State_PilotNoGunner")
local helpStatePilotWithGunner = planeModel:GetAttribute("HelpUI_State_PilotWithGunner")
local helpStateGunner = planeModel:GetAttribute("HelpUI_State_Gunner")
local hullRoot = planeModel.PrimaryPart
local gunnerSeat = planeModel:FindFirstChild("GunnerSeat")
local gunnerPrompt = if gunnerSeat then gunnerSeat:FindFirstChild("GunnerPrompt") else nil

if not hullRoot then
	warn("[GunnerCoop] planeModel has no PrimaryPart; aborting")
	return
end

if not gunnerSeat or not gunnerSeat:IsA("Seat") then
	warn("[GunnerCoop] GunnerSeat missing; aborting")
	return
end

if not gunnerPrompt or not gunnerPrompt:IsA("ProximityPrompt") then
	warn("[GunnerCoop] GunnerPrompt missing; aborting")
	return
end

local activeGunner: Player? = nil

local function getPilot(): Player?
	local userId = hullRoot:GetAttribute(PILOT_USER_ID_ATTR)
	if typeof(userId) ~= "number" or userId == 0 then return nil end
	return Players:GetPlayerByUserId(userId)
end

local function updatePromptVisibility()
	local pilotPresent = getPilot() ~= nil
	local seatEmpty = gunnerSeat.Occupant == nil
	gunnerPrompt.Enabled = pilotPresent and seatEmpty
end

local function updateOverride()
	if activeGunner then
		Controller.setOverride(planeModel, activeGunner)
		return
	end

	Controller.setOverride(planeModel, getPilot())
end

local lastHelpPilot: Player? = nil
local lastHelpGunner: Player? = nil

local function updateHelpStates()
	if not helpStateGunner then return end

	local pilot = getPilot()
	local gunner = activeGunner

	if lastHelpPilot and lastHelpPilot ~= pilot then
		HelpUI.setStateFor(planeModel, lastHelpPilot, nil)
	end

	if lastHelpGunner and lastHelpGunner ~= gunner then
		HelpUI.setStateFor(planeModel, lastHelpGunner, nil)
	end

	lastHelpPilot = pilot
	lastHelpGunner = gunner

	if pilot then
		HelpUI.setStateFor(planeModel, pilot, if gunner then helpStatePilotWithGunner else helpStatePilotNoGunner)
	end

	if gunner then
		HelpUI.setStateFor(planeModel, gunner, helpStateGunner)
	end
end

local function clearActiveGunner()
	if activeGunner and activeGunner.Character then
		CharacterUtils.showCharacter(activeGunner.Character)
	end
	activeGunner = nil
end

local function onSeatOccupantChanged()
	local occupant = gunnerSeat.Occupant
	if occupant then
		local character = occupant.Parent
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		if not player or not character then
			gunnerSeat:Sit(nil)
			return
		end

		activeGunner = player
		CharacterUtils.hideCharacter(character)
	else
		clearActiveGunner()
	end

	updateOverride()
	updatePromptVisibility()
	updateHelpStates()
end

local function onPromptTriggered(player: Player)
	if not gunnerPrompt.Enabled then return end
	if gunnerSeat.Occupant ~= nil then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if humanoid.SeatPart then return end

	gunnerSeat:Sit(humanoid)
end

local function onPilotChanged()
	updatePromptVisibility()
	if not activeGunner then
		updateOverride()
	end

	updateHelpStates()
end

local function onPlayerRemoving(leaving: Player)
	if leaving ~= activeGunner then return end
	clearActiveGunner()
	gunnerSeat:Sit(nil)
	updateOverride()
	updatePromptVisibility()
	updateHelpStates()
end

gunnerSeat:GetPropertyChangedSignal("Occupant"):Connect(onSeatOccupantChanged)
hullRoot:GetAttributeChangedSignal(PILOT_USER_ID_ATTR):Connect(onPilotChanged)
gunnerPrompt.Triggered:Connect(onPromptTriggered)
Players.PlayerRemoving:Connect(onPlayerRemoving)

updatePromptVisibility()
updateOverride()
updateHelpStates()

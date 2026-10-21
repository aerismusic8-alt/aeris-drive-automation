-- GENERATED WRAPPER around upstream FlyingCarpetSeat.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
local Players = game:GetService("Players")

local PILOT_ATTRIBUTE = "PilotUserId"
local ROOT_NAME = "HullRoot"
local ROOT_WAIT_TIMEOUT = 10

local model = script.Parent
local localPlayer = Players.LocalPlayer

local root = model:WaitForChild(ROOT_NAME, ROOT_WAIT_TIMEOUT)
if not root then return end

local seated = false
local seatedHumanoid: Humanoid? = nil
local stateConnection: RBXScriptConnection? = nil

local function getLocalHumanoid(): Humanoid?
	local character = localPlayer.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function endSeated()
	if not seated then return end
	seated = false

	if stateConnection then
		stateConnection:Disconnect()
		stateConnection = nil
	end

	local humanoid = seatedHumanoid or getLocalHumanoid()
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		humanoid.Sit = false
	end

	seatedHumanoid = nil
end

local function beginSeated()
	if seated then return end

	local humanoid = getLocalHumanoid()
	if not humanoid then return end

	seated = true
	seatedHumanoid = humanoid

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.Sit = true

	stateConnection = humanoid.StateChanged:Connect(function(_: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
		if not seated then return end
		if newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics
			or newState == Enum.HumanoidStateType.GettingUp then
			humanoid.Sit = true
		end
	end)
end

local function refresh()
	local pilotUserId = root:GetAttribute(PILOT_ATTRIBUTE)
	if pilotUserId == localPlayer.UserId then
		beginSeated()
	else
		endSeated()
	end
end

root:GetAttributeChangedSignal(PILOT_ATTRIBUTE):Connect(refresh)

localPlayer.CharacterAdded:Connect(function(_: Model)
	if seated then
		seated = false
		seatedHumanoid = nil
		if stateConnection then
			stateConnection:Disconnect()
			stateConnection = nil
		end
	end
	refresh()
end)

refresh()

end

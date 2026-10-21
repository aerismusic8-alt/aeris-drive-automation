-- GENERATED WRAPPER around upstream WheelchairClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if RunService:IsServer() then
	return
end

local CHILD_WAIT_TIMEOUT = 10
local PROMPT_POLL_INTERVAL = 0.25

local model = script.Parent
if not model or not model:IsA("Model") then
	return
end

local localPlayer = Players.LocalPlayer

local riderSeat = model:WaitForChild("RiderSeat", CHILD_WAIT_TIMEOUT)
if not riderSeat or not riderSeat:IsA("Seat") then
	return
end

local pushedBy = model:WaitForChild("PushedBy", CHILD_WAIT_TIMEOUT)
if not pushedBy or not pushedBy:IsA("ObjectValue") then
	return
end

local prompt: ProximityPrompt? = nil
local promptHidden = false
local pushing = false
local pushingHumanoid: Humanoid? = nil
local seatConnection: RBXScriptConnection? = nil

local function getLocalHumanoid(): Humanoid?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function setPromptHidden(shouldHide: boolean)
	if promptHidden == shouldHide then
		return
	end

	promptHidden = shouldHide
	if not prompt then
		return
	end

	if shouldHide then
		prompt.Enabled = false
	else
		prompt.Enabled = model:GetAttribute("pushActive") ~= true
	end
end

local function refreshSeated()
	local humanoid = getLocalHumanoid()
	setPromptHidden(humanoid ~= nil and humanoid.SeatPart == riderSeat)
end

local function refreshPusher()
	local humanoid = getLocalHumanoid()
	local isPusher = pushedBy.Value == localPlayer and humanoid ~= nil

	if isPusher == pushing then
		return
	end

	pushing = isPusher
	if isPusher and humanoid then
		if humanoid.SeatPart then
			humanoid.Sit = false
		end

		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		pushingHumanoid = humanoid
	else
		local target = pushingHumanoid or humanoid
		if target then
			target:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
		end

		pushingHumanoid = nil
	end
end

local function watchCharacter(character: Model)
	if seatConnection then
		seatConnection:Disconnect()
		seatConnection = nil
	end

	pushing = false
	pushingHumanoid = nil

	local humanoid = character:WaitForChild("Humanoid", CHILD_WAIT_TIMEOUT)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	seatConnection = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(refreshSeated)
	refreshSeated()
	refreshPusher()
end

local function findPrompt(): ProximityPrompt?
	local deadline = os.clock() + CHILD_WAIT_TIMEOUT
	while os.clock() < deadline do
		local found = model:FindFirstChild("PushPrompt", true)
		if found and found:IsA("ProximityPrompt") then
			return found
		end

		task.wait(PROMPT_POLL_INTERVAL)
	end

	return nil
end

pushedBy.Changed:Connect(refreshPusher)

local characterConnection = localPlayer.CharacterAdded:Connect(watchCharacter)

model.Destroying:Connect(function()
	characterConnection:Disconnect()
	if seatConnection then
		seatConnection:Disconnect()
		seatConnection = nil
	end

	if pushing and pushingHumanoid then
		pushingHumanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
	end

	pushing = false
	pushingHumanoid = nil
end)

if localPlayer.Character then
	task.spawn(watchCharacter, localPlayer.Character)
end

local foundPrompt = findPrompt()
if foundPrompt then
	prompt = foundPrompt
	foundPrompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if promptHidden and foundPrompt.Enabled then
			foundPrompt.Enabled = false
		end
	end)

	refreshSeated()
end

end

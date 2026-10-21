-- GENERATED WRAPPER around upstream TurretExit.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
Turret5 TurretExit - binds a dedicated exit key while the local player is
operating the turret, instead of relying on jump-to-exit. Cloned into each
Turret5 model by the capability's bind(). Runs with RunContext = Client.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local getExternalCFrame = require(ReplicatedStorage:WaitForChild("FourD").Common.getExternalCFrame)

local EXIT_BIND_NAME = "Turret5Exit"
local EXIT_KEY = Enum.KeyCode.E

local model = script.Parent
if not model:IsA("Model") then return end

local player = Players.LocalPlayer
local seat = model:WaitForChild("DriverSeat")

local function getSeatWeld(character: Model): Weld?
	local primaryPart = character.PrimaryPart
	if not primaryPart then return nil end

	for _, joint in primaryPart:GetJoints() do
		if joint.Name == "SeatWeld" then
			return joint
		end
	end

	return nil
end

local function exitHandler(_, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then return end

	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local seatWeld = getSeatWeld(character)
	if seatWeld then
		repeat
			seatWeld.AncestryChanged:Wait()
		until not seatWeld:IsDescendantOf(game)
	end

	task.defer(function()
		character:PivotTo(getExternalCFrame(model, "Left"))
	end)

	humanoid.PlatformStand = true
	task.wait()
	humanoid.PlatformStand = false
end

local function updateExitBind()
	local occupant = seat.Occupant
	local isSeated = occupant ~= nil and occupant.Parent == player.Character
	if isSeated then
		ContextActionService:BindAction(EXIT_BIND_NAME, exitHandler, true, EXIT_KEY)
	else
		ContextActionService:UnbindAction(EXIT_BIND_NAME)
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(updateExitBind)
updateExitBind()

end

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis
local exitLocationAttachment = chassis.ExitLocationAttachment

local function getSeatWeld(character: Model): Weld?
	local primaryPart = character.PrimaryPart
	if not primaryPart then
		return nil
	end
	local joints = primaryPart:GetJoints()
	for _, joint in joints do
		if joint.Name == "SeatWeld" then
			return joint
		end
	end
	return nil
end

local function exitHandlerAsync(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		local character = player.Character
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		-- Force the character to get out of the seat
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

		-- If a SeatWeld currently exists, wait for it to be removed
		local seatWeld = getSeatWeld(character)
		if seatWeld then
			repeat
				seatWeld.AncestryChanged:Wait()
			until not seatWeld:IsDescendantOf(game)
		end

		-- Move the character outside the car
		-- This is deferred to avoid a race condition with the physics system when SignalBehavior is not already deferred
		task.defer(function()
			character:PivotTo(exitLocationAttachment.WorldCFrame)
		end)

		-- fix for falling characters when exiting cars
		humanoid.PlatformStand = true
		task.wait()
		humanoid.PlatformStand = false
	end
end

return exitHandlerAsync

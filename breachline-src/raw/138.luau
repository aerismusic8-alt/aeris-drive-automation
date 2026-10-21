--[[
	File: Touch.luau
	Touch throttle/steering poll for WaterVehicle2. Mirrors PlayerDrivable._pollTouch:
	projects the character's MoveDirection onto the seat's flattened heading.
]]--

-- Root

local Touch = {}

-- Roblox Services

local Players = game:GetService("Players")

-- Constants

local MOVE_DEADZONE = 0.01

-- Public Functions

function Touch.poll(seat: VehicleSeat): (number, number)
	local character = Players.LocalPlayer.Character
	if not character then return 0, 0 end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return 0, 0 end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < MOVE_DEADZONE then return 0, 0 end

	local look = seat.CFrame.LookVector
	local right = seat.CFrame.RightVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local flatRight = Vector3.new(right.X, 0, right.Z).Unit

	local throttle = math.clamp(moveDir:Dot(flatLook), -1, 1)
	local steering = math.clamp(moveDir:Dot(flatRight), -1, 1)

	return throttle, steering
end

-- Return

return Touch
H;
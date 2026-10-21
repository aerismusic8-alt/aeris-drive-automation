if not script.Parent:IsA("Model") then return end

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local model = script.Parent
local player = Players.LocalPlayer

local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
if not seat then return end

local framePart = model.PrimaryPart
if not framePart then return end

local balanceGyro = framePart:FindFirstChild("BalanceGyro")
local thrustForce = framePart:FindFirstChild("ThrustForce")
if not balanceGyro or not thrustForce then return end

local maxSpeed = model:GetAttribute("maxSpeed") or 50
local acceleration = model:GetAttribute("acceleration") or 30
local maxLeanAngle = math.rad(model:GetAttribute("maxLeanAngle") or 30)
local leanSpeed = model:GetAttribute("leanSpeed") or 8
local wheelieAngle = math.rad(model:GetAttribute("wheelieAngle") or 25)
local steerRate = model:GetAttribute("steerRate") or 2.5
local brakeForce = model:GetAttribute("brakeForce") or 50

local currentYaw = 0
local currentLean = 0
local currentWheeliePitch = 0
local pedalAngle = 0
local shiftHeld = false

local pedalParts = {}
local pedalArmParts = {}
for _, desc in ipairs(model:GetDescendants()) do
	if desc:IsA("BasePart") then
		local parent = desc.Parent
		if parent then
			if parent.Name == "left pedal" or parent.Name == "right pedal" then
				table.insert(pedalParts, desc)
			elseif parent.Name == "left pedal arm" or parent.Name == "right pedal arm" then
				table.insert(pedalArmParts, desc)
			end
		end
	end
end

local function isDriver()
	if not seat.Occupant then return false end
	return seat.Occupant.Parent == player.Character
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftHeld = false
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not isDriver() then
		thrustForce.Force = Vector3.new(0, 0, 0)
		return
	end

	local throttle = seat.Throttle
	local steer = seat.Steer

	local currentVelocity = framePart.AssemblyLinearVelocity
	local forwardSpeed = currentVelocity:Dot(framePart.CFrame.LookVector)
	local speedRatio = math.clamp(math.abs(forwardSpeed) / maxSpeed, 0, 1)

	local targetThrust = 0
	if throttle ~= 0 then
		local boostMult = (shiftHeld and throttle > 0) and 1.3 or 1
		targetThrust = -throttle * acceleration * framePart.AssemblyMass * boostMult
	else
		targetThrust = -forwardSpeed * brakeForce * 0.3
	end
	thrustForce.Force = Vector3.new(0, 0, targetThrust)

	local speedFactor = math.max(0.3, 1 - speedRatio * 0.5)
	currentYaw = currentYaw - steer * steerRate * speedFactor * dt

	local targetLean = -steer * maxLeanAngle * speedRatio
	currentLean = currentLean + (targetLean - currentLean) * math.min(1, dt * leanSpeed)

	local targetWheeliePitch = 0
	if shiftHeld and throttle > 0 and speedRatio > 0.3 then
		targetWheeliePitch = -wheelieAngle
	end
	currentWheeliePitch = currentWheeliePitch + (targetWheeliePitch - currentWheeliePitch) * math.min(1, dt * 6)

	balanceGyro.CFrame = CFrame.Angles(0, currentYaw, 0) * CFrame.Angles(currentWheeliePitch, 0, currentLean)

	-- Cosmetic pedal rotation proportional to speed
	if #pedalParts > 0 or #pedalArmParts > 0 then
		local pedalSpeedMult = math.abs(forwardSpeed) * 2
		pedalAngle = pedalAngle + pedalSpeedMult * dt
	end
end)

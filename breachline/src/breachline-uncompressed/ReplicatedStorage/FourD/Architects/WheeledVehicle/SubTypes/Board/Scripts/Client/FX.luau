-- GENERATED WRAPPER around upstream FX.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: FX/init.server.luau
	RunContext: Client (rolling audio volume)
]]--

if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then return end

-- Roblox Services

local RunService = game:GetService("RunService")

-- Object References

local boardRig = script.Parent.Parent.Parent
local chassis = boardRig:WaitForChild("Chassis")
local audioEmitter = chassis:FindFirstChildOfClass("AudioEmitter")

-- Constants

local MAX_AUDIBLE_SPEED = 60

-- Local Functions

local function update(_: number): ()
	if not audioEmitter then return end
	if not chassis.Parent then return end

	local speed = chassis.AssemblyLinearVelocity.Magnitude
	local volume = math.clamp(speed / MAX_AUDIBLE_SPEED, 0, 1)
	for _, child in audioEmitter:GetChildren() do
		if child:IsA("AudioPlayer") then
			child.Volume = volume
		end
	end
end

local function initialize()
	RunService.Heartbeat:Connect(update)
end

initialize()

end

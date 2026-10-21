-- GENERATED WRAPPER around upstream SwivelDrive.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
Turret5 SwivelDrive - yaws the swivel mount in sync with the turret. Runs
client-side (RunContext = Client) and smooths the `turretYaw` attribute (set
by Gunnable's TurretServer) onto a dedicated yaw-only Motor6D at the same
rate Gunnable's TurretClient smooths the gun, so the swivel mount turns with
the gun but never pitches. Cloned into each Turret5 model by the
capability's bind().
]]

local RunService = game:GetService("RunService")

local model = script.Parent
if not model:IsA("Model") then return end

local swivelMotor = model:FindFirstChild("SwivelMotor", true)
local swivelBaseC0Value = model:FindFirstChild("SwivelBaseC0")
if not swivelMotor or not swivelMotor:IsA("Motor6D") then return end
if not swivelBaseC0Value or not swivelBaseC0Value:IsA("CFrameValue") then return end

local baseC0 = swivelBaseC0Value.Value
local turretSpeedRad = math.rad(model:GetAttribute("Gunnable_TurretSpeed") or 540)
local smoothedYaw = model:GetAttribute("turretYaw") or 0

local function approachAngle(current: number, target: number, maxStep: number): number
	local delta = math.atan2(math.sin(target - current), math.cos(target - current))
	return current + math.clamp(delta, -maxStep, maxStep)
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	local yaw = model:GetAttribute("turretYaw")
	if typeof(yaw) ~= "number" or yaw ~= yaw then return end

	smoothedYaw = approachAngle(smoothedYaw, yaw, turretSpeedRad * deltaTime)
	swivelMotor.C0 = baseC0 * CFrame.Angles(0, smoothedYaw, 0)
end)

end

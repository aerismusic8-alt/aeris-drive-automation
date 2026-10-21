if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then return end

local RS = game:GetService("ReplicatedStorage")
local FourD = RS:WaitForChild("FourD")
local WheeledVehicle = require(FourD.Architects.WheeledVehicle)

local model = script.Parent

local function findRole(role: string): Instance?
	for _, desc in model:GetDescendants() do
		if desc:GetAttribute("_FD_Role") == role then
			return desc
		end
	end
	return nil
end

local function findAllByRole(role: string): { PVInstance }
	local results = {}
	for _, desc in model:GetDescendants() do
		if desc:GetAttribute("_FD_Role") == role then
			table.insert(results, desc)
		end
	end
	return results
end

local container = findRole("Body")
local wheelF = findRole("WheelF")
local wheelR = findRole("WheelR")

if not (container and wheelF and wheelR) then
	warn("[FourD Rig] WheeledVehicle2W: missing required schema parts (Body, WheelF, WheelR)")
	script:Destroy()
	return
end

local extraParts = findAllByRole("ExtraPart")

WheeledVehicle.build2Wheel(container, {
	Schema = {
		WheelF = wheelF,
		WheelR = wheelR,
	},
	Performance = {
		MaxSpeedForward = model:GetAttribute("_FD_MaxSpeedForward"),
		MaxSpeedReverse = model:GetAttribute("_FD_MaxSpeedReverse"),
		Acceleration = model:GetAttribute("_FD_Acceleration"),
		Braking = model:GetAttribute("_FD_Braking"),
		Deceleration = model:GetAttribute("_FD_Deceleration"),
		MaxSteerDegrees = model:GetAttribute("_FD_MaxSteerDegrees"),
		MaxLeanDegrees = model:GetAttribute("_FD_MaxLeanDegrees"),
		LeanGain = model:GetAttribute("_FD_LeanGain"),
		BalanceStrength = model:GetAttribute("_FD_BalanceStrength"),
		BalanceDamping = model:GetAttribute("_FD_BalanceDamping"),
		YawStrength = model:GetAttribute("_FD_YawStrength"),
		MaxYawRate = model:GetAttribute("_FD_MaxYawRate"),
		MaxInclineDegrees = model:GetAttribute("_FD_MaxInclineDegrees"),
	},
	ExtraParts = if #extraParts > 0 then extraParts else nil,
})

script:Destroy()

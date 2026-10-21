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
local wheelFL = findRole("WheelFL")
local wheelFR = findRole("WheelFR")
local wheelRL = findRole("WheelRL")
local wheelRR = findRole("WheelRR")

if not (container and wheelFL and wheelFR and wheelRL and wheelRR) then
	warn("[FourD Rig] WheeledVehicle4W: missing required schema parts (Body, WheelFL, WheelFR, WheelRL, WheelRR)")
	script:Destroy()
	return
end

local extraParts = findAllByRole("ExtraPart")

WheeledVehicle.build4Wheel(container, {
	Schema = {
		WheelFL = wheelFL,
		WheelFR = wheelFR,
		WheelRL = wheelRL,
		WheelRR = wheelRR,
	},
	Performance = {
		MaxSpeedForward = model:GetAttribute("_FD_MaxSpeedForward"),
		MaxSpeedReverse = model:GetAttribute("_FD_MaxSpeedReverse"),
		Acceleration = model:GetAttribute("_FD_Acceleration"),
		Braking = model:GetAttribute("_FD_Braking"),
		Deceleration = model:GetAttribute("_FD_Deceleration"),
		EngineSpeedCorrection = model:GetAttribute("_FD_EngineSpeedCorrection"),
		HasNitro = model:GetAttribute("_FD_HasNitro"),
		MinSpeedTorque = model:GetAttribute("_FD_MinSpeedTorque"),
		MaxSpeedTorque = model:GetAttribute("_FD_MaxSpeedTorque"),
		NitroAcceleration = model:GetAttribute("_FD_NitroAcceleration"),
		NitroMaxExtraSpeed = model:GetAttribute("_FD_NitroMaxExtraSpeed"),
		NitroTime = model:GetAttribute("_FD_NitroTime"),
		NitroRechargeTime = model:GetAttribute("_FD_NitroRechargeTime"),
		NitroTorque = model:GetAttribute("_FD_NitroTorque"),
	},
	SeatPosition = model:GetAttribute("_FD_SeatPosition") or "ontop",
	ExtraParts = if #extraParts > 0 then extraParts else nil,
	AsymmetricAxles = model:GetAttribute("_FD_AsymmetricAxles") or false,
})

script:Destroy()

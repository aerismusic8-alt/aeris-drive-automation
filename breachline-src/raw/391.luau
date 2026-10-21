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
	warn("[FourD Rig] WheeledVehicleBoard: missing required schema parts (Body, WheelFL, WheelFR, WheelRL, WheelRR)")
	script:Destroy()
	return
end

local extraParts = findAllByRole("ExtraPart")

WheeledVehicle.buildBoard(container, {
	Schema = {
		WheelFL = wheelFL,
		WheelFR = wheelFR,
		WheelRL = wheelRL,
		WheelRR = wheelRR,
	},
	Performance = {
		AccelerationSpeed = model:GetAttribute("_FD_AccelerationSpeed"),
		MaxSpeed = model:GetAttribute("_FD_MaxSpeed"),
		TurnSpeed = model:GetAttribute("_FD_TurnSpeed"),
		TurnSpeedAirMult = model:GetAttribute("_FD_TurnSpeedAirMult"),
		OllieImpulse = model:GetAttribute("_FD_OllieImpulse"),
		MaxInclineDegrees = model:GetAttribute("_FD_MaxInclineDegrees"),
		OllieCooldown = model:GetAttribute("_FD_OllieCooldown"),
		RedressCooldown = model:GetAttribute("_FD_RedressCooldown"),
	},
	ExtraParts = if #extraParts > 0 then extraParts else nil,
})

script:Destroy()

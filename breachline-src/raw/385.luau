if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then return end

local RS = game:GetService("ReplicatedStorage")
local FourD = RS:WaitForChild("FourD")
local AirVehicle = require(FourD.Architects.AirVehicle)

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

local body = findRole("Body")

if not body then
	warn("[FourD Rig] AirVehiclePlane: missing required schema part (Body)")
	script:Destroy()
	return
end

local propellers = findAllByRole("Propeller")
local thrusters = findAllByRole("Thruster")
local forwardHint = findAllByRole("ForwardHint")
local leftLandingGear = findRole("LeftLandingGear")
local rightLandingGear = findRole("RightLandingGear")
local centerLandingGear = findRole("CenterLandingGear")

AirVehicle.buildPlane(model, {
	Schema = {
		Body = body,
		Propellers = if #propellers > 0 then propellers else nil,
		Thrusters = if #thrusters > 0 then thrusters else nil,
		ForwardHint = if #forwardHint > 0 then forwardHint else nil,
		LeftLandingGear = leftLandingGear,
		RightLandingGear = rightLandingGear,
		CenterLandingGear = centerLandingGear,
	},
	Performance = {
		MaxSpeed = model:GetAttribute("_FD_MaxSpeed"),
		StallSpeed = model:GetAttribute("_FD_StallSpeed"),
		Acceleration = model:GetAttribute("_FD_Acceleration"),
		PitchRate = model:GetAttribute("_FD_PitchRate"),
		TurnRate = model:GetAttribute("_FD_TurnRate"),
		CameraDistance = model:GetAttribute("_FD_CameraDistance"),
	},
	ProximityPromptText = model:GetAttribute("_FD_ProximityPromptText"),
})

script:Destroy()

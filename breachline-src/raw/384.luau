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

local pack = findRole("Pack")
local thruster = findRole("Thruster")

if not (pack and thruster) then
	warn("[FourD Rig] AirVehicleJetpack: missing required schema parts (Pack, Thruster)")
	script:Destroy()
	return
end

local forwardHint = findAllByRole("ForwardHint")

AirVehicle.buildJetpack(model, {
	Schema = {
		Pack = pack,
		Thruster = thruster,
		ForwardHint = if #forwardHint > 0 then forwardHint else nil,
	},
	Performance = {
		MaxSpeed = model:GetAttribute("_FD_MaxSpeed"),
		Acceleration = model:GetAttribute("_FD_Acceleration"),
		AltitudeChangeRate = model:GetAttribute("_FD_AltitudeChangeRate"),
		LookRate = model:GetAttribute("_FD_LookRate"),
		CameraDistance = model:GetAttribute("_FD_CameraDistance"),
	},
	ProximityPromptText = model:GetAttribute("_FD_ProximityPromptText"),
})

script:Destroy()
s
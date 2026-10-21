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
	warn("[FourD Rig] AirVehicleRotor: missing required schema part (Body)")
	script:Destroy()
	return
end

local mainRotors = findAllByRole("MainRotor")
local tailRotors = findAllByRole("TailRotor")
local forwardHint = findAllByRole("ForwardHint")

AirVehicle.buildRotor(model, {
	Schema = {
		Body = body,
		MainRotors = if #mainRotors > 0 then mainRotors else nil,
		TailRotors = if #tailRotors > 0 then tailRotors else nil,
		ForwardHint = if #forwardHint > 0 then forwardHint else nil,
	},
	Performance = {
		MaxSpeedLateral = model:GetAttribute("_FD_MaxSpeedLateral"),
		MaxSpeedStrafe = model:GetAttribute("_FD_MaxSpeedStrafe"),
		Acceleration = model:GetAttribute("_FD_Acceleration"),
		MaxCollective = model:GetAttribute("_FD_MaxCollective"),
		CollectiveRate = model:GetAttribute("_FD_CollectiveRate"),
		CameraDistance = model:GetAttribute("_FD_CameraDistance"),
	},
	ProximityPromptText = model:GetAttribute("_FD_ProximityPromptText"),
	RiderVisible = model:GetAttribute("_FD_RiderVisible"),
})

script:Destroy()

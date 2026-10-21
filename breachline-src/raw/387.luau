if script:FindFirstAncestorWhichIsA("ReplicatedStorage") then return end

local RS = game:GetService("ReplicatedStorage")
local FourD = RS:WaitForChild("FourD")
local WaterSubmersible = require(FourD.Architects.WaterSubmersible)

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
	warn("[FourD Rig] WaterSubmersible: missing required schema part (Body)")
	script:Destroy()
	return
end

local rotors = findAllByRole("Rotor")

WaterSubmersible.build(body, {
	MaxForwardSpeed = model:GetAttribute("_FD_MaxForwardSpeed"),
	MaxReverseSpeed = model:GetAttribute("_FD_MaxReverseSpeed"),
	Acceleration = model:GetAttribute("_FD_Acceleration"),
	MaxTurnSpeed = model:GetAttribute("_FD_MaxTurnSpeed"),
	TurnAcceleration = model:GetAttribute("_FD_TurnAcceleration"),
	DepthChangeSpeed = model:GetAttribute("_FD_DepthChangeSpeed"),
	ProximityPromptText = model:GetAttribute("_FD_ProximityPromptText"),
	UseProximityPrompt = if model:GetAttribute("_FD_UseProximityPrompt") ~= nil
		then model:GetAttribute("_FD_UseProximityPrompt")
		else true,
	Rotors = if #rotors > 0 then rotors else nil,
})

script:Destroy()

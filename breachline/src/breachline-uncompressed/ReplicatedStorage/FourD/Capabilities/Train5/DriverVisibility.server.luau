--[[
Train5 DriverVisibility - hides the driver's character while they occupy the
driver seat, matching the plane-style mounting behavior. Cloned into the engine
car model by bind().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local CharacterUtils = require(FourD:WaitForChild("Architects"):WaitForChild("AirVehicle"):WaitForChild("Common"):WaitForChild("CharacterUtils"))

local model = script.Parent
if not model:IsA("Model") then return end

local seat = model:FindFirstChildWhichIsA("VehicleSeat")
if not seat then return end

local hiddenCharacter: Model? = nil

local function updateVisibility()
	local occupant = seat.Occupant
	local character = if occupant then occupant.Parent else nil

	if hiddenCharacter and hiddenCharacter ~= character then
		CharacterUtils.showCharacter(hiddenCharacter)
		hiddenCharacter = nil
	end

	if character and character:IsA("Model") and hiddenCharacter == nil then
		CharacterUtils.hideCharacter(character)
		hiddenCharacter = character
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(updateVisibility)

script.Destroying:Connect(function()
	if hiddenCharacter then
		CharacterUtils.showCharacter(hiddenCharacter)
		hiddenCharacter = nil
	end
end)

updateVisibility()

--[[
	File: CharacterUtils.luau
]]--

-- Root

local CharacterUtils = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local GeometryUtils = require(FourD.Common.GeometryUtils)

-- Constants

local DEFAULT_HIP_HEIGHT = 2

-- Public Functions

function CharacterUtils.setCharacterMassless(character: Model, massless: boolean)
	for _, part in GeometryUtils.getInstanceParts(character) do
		part.Massless = massless
	end
end

local function setCharacterVisibility(character: Model, transparency: number)
	for _, descendant in character:GetDescendants() do
		if descendant.Name == "HumanoidRootPart" then continue end
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.Transparency = transparency
		end
	end
end

function CharacterUtils.hideCharacter(character: Model)
	setCharacterVisibility(character, 1)
end

function CharacterUtils.showCharacter(character: Model)
	setCharacterVisibility(character, 0)
end

function CharacterUtils.getHipHeight(humanoid: Humanoid): number
	local height = humanoid.HipHeight
	if height > 0 then return height end
	return DEFAULT_HIP_HEIGHT
end

-- Return

return CharacterUtils

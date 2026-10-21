-- Template guard: only run when cloned into Workspace as part of a thrown grenade assembly
if not script:FindFirstAncestorWhichIsA("Workspace") then return end

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Common = FourD.Common
local getCharacterFromPart = require(Common.getCharacterFromPart)

local DAMAGE = 100
local RADIUS = 15

-- script 
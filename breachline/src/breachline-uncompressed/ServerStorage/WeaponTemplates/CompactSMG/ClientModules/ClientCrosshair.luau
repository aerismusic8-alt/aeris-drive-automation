--[[
	File: ClientCrosshair.luau
]]--

-- Root

local ClientCrosshair = {}
ClientCrosshair.__index = ClientCrosshair

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local ConeMath = require(Firearm2.Common.ConeMath)
local Constants = require(Firearm2.Common.Constants)

-- Constants

local TEMPLATE_PATH = Constants.CROSSHAIR_TEMPLATE_PATH

-- Local Functions

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function resolveTemplate(): ScreenGui?
	local current = ReplicatedStorage
	for _, segment in TEMPLATE_PATH do
		current = current:FindFirstChild(segment)
		if not current then return nil end
	end

	if not current:IsA("ScreenGui") then
		vwarn("FirearmCrosshair template is not a ScreenGui")
		return nil
	end

	return current
end

-- Public Methods

function ClientCrosshair:SetSpread(spreadDeg: number, camera: Camera)
	if not self._holder then return end
	local diameter = math.max(0, ConeMath.spreadDegToPixelRadius(spreadDeg, camera) * 2)
	self._holder.Size = UDim2.fromOffset(diameter, diameter)
end

function ClientCrosshair:Enable()
	if self._gui then return end

	local template = resolveTemplate()
	if not template then
		vwarn("FirearmCrosshair template missing; crosshair disabled")
		return
	end

	local clone = template:Clone()
	clone.ResetOnSpawn = false
	clone.Parent = self._player:WaitForChild("PlayerGui")

	self._gui = clone
	self._holder = clone:FindFirstChild("Holder")

	if not self._holder then
		vwarn("FirearmCrosshair clone missing Holder frame")
	end
end

function ClientCrosshair:Disable()
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end

	self._holder = nil
end

function ClientCrosshair:Destroy()
	self:Disable()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function ClientCrosshair.new(): any
	local self = setmetatable({}, ClientCrosshair)
	self._player = Players.LocalPlayer
	self._gui = nil
	self._holder = nil
	return self
end

-- Return

return ClientCrosshair

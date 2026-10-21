--[[
	File: ClientAmmoHud.luau
]]--

-- Root

local ClientAmmoHud = {}
ClientAmmoHud.__index = ClientAmmoHud

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local Constants = require(Firearm2.Common.Constants)

-- Constants

local TEMPLATE_PATH = Constants.AMMO_HUD_TEMPLATE_PATH
local LABEL_NAME = Constants.AMMO_HUD_LABEL_NAME
local LEADING_ZERO_OPEN = `<font color="#960000">`

-- Local Functions

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function resolveTemplate(): ScreenGui?
	local current: Instance = ReplicatedStorage
	for _, segment in TEMPLATE_PATH do
		local nextChild = current:FindFirstChild(segment)
		if not nextChild then return nil end
		current = nextChild
	end

	if not current:IsA("ScreenGui") then
		vwarn("FirearmAmmo template is not a ScreenGui")
		return nil
	end

	return current
end

local function formatAmmoText(currentAmmo: number, maxAmmo: number): string
	local maxStr = tostring(math.max(maxAmmo, 0))
	local currentClamped = math.clamp(currentAmmo, 0, math.max(maxAmmo, 0))
	local currentStr = tostring(currentClamped)
	local padCount = math.max(#maxStr - #currentStr, 0)
	local padded = string.rep("0", padCount) .. currentStr

	local firstNonZero = string.find(padded, "[^0]") or (#padded + 1)
	local leadingZeros = string.sub(padded, 1, firstNonZero - 1)
	local rest = string.sub(padded, firstNonZero)

	local leadingPart = if #leadingZeros > 0
		then `{LEADING_ZERO_OPEN}{leadingZeros}</font>`
		else ""

	return `<font weight="500">{leadingPart}{rest}</font>/{maxStr}`
end

-- Public Methods

function ClientAmmoHud:SetAmmo(currentAmmo: number, maxAmmo: number)
	if not self._label then return end
	self._label.Text = formatAmmoText(currentAmmo, maxAmmo)
end

function ClientAmmoHud:SetReloading()
	if not self._label then return end
	self._label.Text = "RELOADING"
end

function ClientAmmoHud:Enable()
	if self._gui then return end

	local template = resolveTemplate()
	if not template then
		vwarn("FirearmAmmo template missing; ammo hud disabled")
		return
	end

	local clone = template:Clone()
	clone.ResetOnSpawn = false
	clone.Parent = self._player:WaitForChild("PlayerGui")

	self._gui = clone
	local label = clone:FindFirstChild(LABEL_NAME, true)
	if label and label:IsA("TextLabel") then
		self._label = label
	else
		vwarn(`FirearmAmmo clone missing TextLabel '{LABEL_NAME}'`)
	end
end

function ClientAmmoHud:Disable()
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end

	self._label = nil
end

function ClientAmmoHud:Destroy()
	self:Disable()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function ClientAmmoHud.new(): any
	local self = setmetatable({}, ClientAmmoHud)
	self._player = Players.LocalPlayer
	self._gui = nil
	self._label = nil
	return self
end

-- Return

return ClientAmmoHud
8"
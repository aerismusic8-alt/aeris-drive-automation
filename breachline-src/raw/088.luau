--[[
	File: AimReticle.luau

	Client-side screen reticle shared by Gunnable SubTypes. Owns the HUD
	ScreenGui lifecycle and the world-to-screen projection: callers resolve an
	aim point in world space each frame and hand it over, and this decides where
	the dot sits, whether the spread ring is worth drawing, and when the whole
	thing should hide.

	Purely cosmetic and local. Hardpoint feeds it a raycast against the barrel
	centroid; Launcher feeds it the clipped ballistic impact point.
]]--

-- Root

local AimReticle = {}
AimReticle.__index = AimReticle

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Constants

local DEFAULT_TEMPLATE_NAME = "Gunnable_HardpointHud"
local DEFAULT_LERP_RATE = 20

-- Private Methods

function AimReticle:_ensureGui()
	if self._screenGui then return end

	local clone = self._template:Clone()
	clone.Enabled = false
	clone.Parent = self._playerGui

	self._screenGui = clone
	self._holder = clone:WaitForChild("Holder")
	self._spreadOutline = self._holder:WaitForChild("SpreadOutline")
	self._dot = self._holder:WaitForChild("Dot")
end

-- Public Methods

function AimReticle:Hide()
	if not self._screenGui then return end

	self._screenGui.Enabled = false
end

function AimReticle:ReleaseGui()
	if self._screenGui then
		self._screenGui:Destroy()
	end

	self._screenGui = nil
	self._holder = nil
	self._spreadOutline = nil
	self._dot = nil
	self._smoothedPosition = nil
	self._anchorScreenPosition = nil
	self._anchorWorldPosition = nil
end

function AimReticle:Update(aimPoint: Vector3, deltaTime: number): boolean
	self:_ensureGui()

	local camera = Workspace.CurrentCamera
	if not camera then
		self:Hide()
		return false
	end

	local screenPos = camera:WorldToViewportPoint(aimPoint)
	if screenPos.Z <= 0 then
		self:Hide()
		self._smoothedPosition = nil
		return false
	end

	local reticlePos = Vector2.new(screenPos.X, screenPos.Y)
	if self._lerp then
		local alpha = 1 - math.exp(-self._lerpRate * deltaTime)
		local smoothed = self._smoothedPosition
		self._smoothedPosition = if smoothed then smoothed:Lerp(reticlePos, alpha) else reticlePos
		reticlePos = self._smoothedPosition
	end

	self._holder.Position = UDim2.fromOffset(reticlePos.X, reticlePos.Y)
	self._anchorScreenPosition = Vector2.new(screenPos.X, screenPos.Y)
	self._anchorWorldPosition = aimPoint

	self._screenGui.Enabled = true
	return true
end

function AimReticle:SetSpreadRadius(worldRadius: number?)
	if not self._screenGui then return end

	local anchorWorld = self._anchorWorldPosition
	local anchorScreen = self._anchorScreenPosition
	if not worldRadius or worldRadius <= 0 or not anchorWorld or not anchorScreen then
		self._spreadOutline.Visible = false
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		self._spreadOutline.Visible = false
		return
	end

	local edgePoint = anchorWorld + camera.CFrame.RightVector * worldRadius
	local edgeScreen = camera:WorldToViewportPoint(edgePoint)
	local diameterPx = 2 * (Vector2.new(edgeScreen.X, edgeScreen.Y) - anchorScreen).Magnitude
	if diameterPx > self._dot.AbsoluteSize.X then
		self._spreadOutline.Size = UDim2.fromOffset(diameterPx, diameterPx)
		self._spreadOutline.Visible = true
	else
		self._spreadOutline.Visible = false
	end
end

function AimReticle:Destroy()
	self:ReleaseGui()
	table.clear(self)
	setmetatable(self, nil)
end

-- Constructor

function AimReticle.new(params: AimReticleParams): AimReticle
	local localPlayer = Players.LocalPlayer
	assert(localPlayer, "[AimReticle] requires a LocalPlayer")

	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI")
	local template = assets:WaitForChild(params.TemplateName or DEFAULT_TEMPLATE_NAME)

	local self = setmetatable({}, AimReticle)

	self._template = template
	self._playerGui = localPlayer:WaitForChild("PlayerGui")
	self._lerp = params.Lerp == true
	self._lerpRate = params.LerpRate or DEFAULT_LERP_RATE

	self._screenGui = nil
	self._holder = nil
	self._spreadOutline = nil
	self._dot = nil
	self._smoothedPosition = nil
	self._anchorScreenPosition = nil
	self._anchorWorldPosition = nil

	return self
end

-- Types

export type AimReticleParams = {
	Lerp: boolean?,
	LerpRate: number?,
	TemplateName: string?,
}

export type AimReticle = {
	Update: (self: AimReticle, aimPoint: Vector3, deltaTime: number) -> boolean,
	SetSpreadRadius: (self: AimReticle, worldRadius: number?) -> (),
	Hide: (self: AimReticle) -> (),
	ReleaseGui: (self: AimReticle) -> (),
	Destroy: (self: AimReticle) -> (),
}

-- Return

return AimReticle

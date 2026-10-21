--[[
	File: FX.luau
]]--

-- Root

local FX = {}

-- Constants

local VFX_CLONE_PREFIX = "JetFlameRoot_"
local MOVE_INTENSITY_THRESHOLD = 0.05

-- Module State

local active = false
local emitters: { ParticleEmitter } = {}
local beams: { Beam } = {}
local trails: { Trail } = {}
local beamsEnabled = false

-- Local Functions

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

local function gatherEffects(wrapper: Model)
	for _, child in wrapper:GetChildren() do
		if not child:IsA("Model") then continue end
		if not startsWith(child.Name, VFX_CLONE_PREFIX) then continue end

		for _, descendant in child:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				table.insert(emitters, descendant)
			elseif descendant:IsA("Beam") then
				table.insert(beams, descendant)
			elseif descendant:IsA("Trail") then
				table.insert(trails, descendant)
			end
		end
	end
end

local function setEnabled(value: boolean)
	for _, emitter in emitters do
		emitter.Enabled = value
	end
	for _, beam in beams do
		beam.Enabled = value
	end
	for _, trail in trails do
		trail.Enabled = value
	end
	beamsEnabled = value
end

local function setBeamsEnabled(value: boolean)
	if value == beamsEnabled then return end
	beamsEnabled = value
	for _, beam in beams do
		beam.Enabled = value
	end
end

-- Public Functions

function FX.enable(wrapper: Model, _root: BasePart)
	if active then return end
	active = true

	emitters = {}
	beams = {}
	trails = {}
	gatherEffects(wrapper)

	setEnabled(true)
end

function FX.disable()
	if not active then return end
	active = false

	setEnabled(false)

	emitters = {}
	beams = {}
	trails = {}
end

function FX.update(intensityRatio: number, _speedRatio: number, _dt: number)
	if not active then return end
	setBeamsEnabled(intensityRatio > MOVE_INTENSITY_THRESHOLD)
end

-- Return

return FX
n
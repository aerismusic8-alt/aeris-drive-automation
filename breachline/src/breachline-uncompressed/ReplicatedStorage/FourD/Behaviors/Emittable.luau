--[[
	File: Emittable/init.luau

	Emittable behavior. Adds a particle/fire/smoke effect to a BasePart. The
	effect instances (Fire, Smoke, ParticleEmitter) are server-authoritative and
	replicate natively — no per-client renderer needed.

	Supports six styles:
		"fire"     -> Fire instance
		"smoke"    -> Smoke instance
		"sparkles" -> ParticleEmitter (yellow/white sparkle preset)
		"embers"   -> ParticleEmitter (orange rising embers)
		"magic"    -> ParticleEmitter (purple/cyan swirl)
		"steam"    -> ParticleEmitter (white upward puffs)

	Public API:
		Emittable.new(host, params) -> Emittable
		Emittable:SetEnabled / IsEnabled
		Emittable:GetEffect -> Instance
		Emittable:GetHost -> BasePart
		Emittable:Destroy
]]--

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local EmittableRoot = FourD.Behaviors.Emittable
local Constants = require(EmittableRoot.Common.Constants)
local Types = require(EmittableRoot.Common.Types)

-- Root

local Emittable = {}
Emittable.__index = Emittable

-- Local Functions

local function findAnyBasePart(pvInstance: PVInstance): BasePart?
	if pvInstance:IsA("BasePart") then
		return pvInstance
	end
	if pvInstance:IsA("Model") then
		if pvInstance.PrimaryPart then
			return pvInstance.PrimaryPart
		end
		for _, descendant in pvInstance:GetDescendants() do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end
	return nil
end

local function buildFire(host: BasePart, params: Types.EmittableParams): Fire
	local scale = params.Scale or Constants.DEFAULTS.Scale
	local mag = host.Size.Magnitude

	local fire = Instance.new("Fire")
	fire.Name = Constants.EFFECT_NAME
	fire.Size = math.clamp(mag * 2 * scale, 2, 30)
	fire.Heat = math.clamp(mag * scale, 1, 25)
	if params.Color then
		fire.Color = params.Color
		fire.SecondaryColor = params.Color:Lerp(Color3.new(0, 0, 0), 0.5)
	end
	fire.Enabled = if params.Enabled ~= nil then params.Enabled else Constants.DEFAULTS.Enabled
	fire.Parent = host
	return fire
end

local function buildSmoke(host: BasePart, params: Types.EmittableParams): Smoke
	local scale = params.Scale or Constants.DEFAULTS.Scale
	local mag = host.Size.Magnitude

	local smoke = Instance.new("Smoke")
	smoke.Name = Constants.EFFECT_NAME
	smoke.Size = math.clamp(mag * 1.5 * scale, 1, 20)
	smoke.Opacity = math.clamp(0.3 * scale, 0.1, 0.8)
	smoke.RiseVelocity = math.clamp(mag * 0.5 * scale, 1, 15)
	if params.Color then
		smoke.Color = params.Color
	end
	smoke.Enabled = if params.Enabled ~= nil then params.Enabled else Constants.DEFAULTS.Enabled
	smoke.Parent = host
	return smoke
end

local function buildParticleEmitter(host: BasePart, params: Types.EmittableParams, preset: string): ParticleEmitter
	local scale = params.Scale or Constants.DEFAULTS.Scale
	local mag = host.Size.Magnitude

	local pe = Instance.new("ParticleEmitter")
	pe.Name = Constants.EFFECT_NAME

	if preset == "sparkles" then
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Rate = math.clamp(20 * scale, 5, 100)
		pe.Lifetime = NumberRange.new(0.5, 1.5)
		pe.Speed = NumberRange.new(1 * scale, 3 * scale)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(math.clamp(mag * 0.1 * scale, 0.1, 2))
		local color = params.Color or Color3.fromRGB(255, 255, 180)
		pe.Color = ColorSequence.new(color)
		pe.LightEmission = 1

	elseif preset == "embers" then
		pe.Texture = "rbxasset://textures/particles/fire_main.dds"
		pe.Rate = math.clamp(15 * scale, 3, 80)
		pe.Lifetime = NumberRange.new(1, 3)
		pe.Speed = NumberRange.new(2 * scale, 5 * scale)
		pe.SpreadAngle = Vector2.new(30, 30)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(mag * 0.05 * scale, 0.05, 0.5)),
			NumberSequenceKeypoint.new(1, 0),
		})
		local color = params.Color or Color3.fromRGB(255, 120, 20)
		pe.Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.7))
		pe.LightEmission = 0.6
		pe.EmissionDirection = Enum.NormalId.Top

	elseif preset == "magic" then
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Rate = math.clamp(25 * scale, 5, 120)
		pe.Lifetime = NumberRange.new(0.8, 2)
		pe.Speed = NumberRange.new(2 * scale, 6 * scale)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, math.clamp(mag * 0.08 * scale, 0.1, 1)),
			NumberSequenceKeypoint.new(1, 0),
		})
		local color = params.Color or Color3.fromRGB(150, 50, 255)
		pe.Color = ColorSequence.new(color, Color3.fromRGB(50, 200, 255))
		pe.LightEmission = 0.8
		pe.RotSpeed = NumberRange.new(-180, 180)

	elseif preset == "steam" then
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Rate = math.clamp(10 * scale, 2, 50)
		pe.Lifetime = NumberRange.new(1, 3)
		pe.Speed = NumberRange.new(2 * scale, 4 * scale)
		pe.SpreadAngle = Vector2.new(15, 15)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(mag * 0.1 * scale, 0.1, 1)),
			NumberSequenceKeypoint.new(1, math.clamp(mag * 0.3 * scale, 0.3, 3)),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		local color = params.Color or Color3.fromRGB(240, 240, 240)
		pe.Color = ColorSequence.new(color)
		pe.LightEmission = 0
		pe.EmissionDirection = Enum.NormalId.Top
	end

	pe.Enabled = if params.Enabled ~= nil then params.Enabled else Constants.DEFAULTS.Enabled
	pe.Parent = host
	return pe
end

-- Internal Methods

function Emittable:_assertAlive()
	assert(table.isfrozen(self) == false, "cannot operate on a destroyed Emittable")
end

-- Public Methods

---Returns the underlying effect instance (Fire, Smoke, or ParticleEmitter).
function Emittable:GetEffect(): Instance
	self:_assertAlive()
	return self._effect
end

---Returns the host BasePart.
function Emittable:GetHost(): BasePart
	self:_assertAlive()
	return self._host
end

---Returns whether the effect is currently enabled.
function Emittable:IsEnabled(): boolean
	self:_assertAlive()
	return self._effect.Enabled
end

---Enables or disables the effect.
function Emittable:SetEnabled(enabled: boolean)
	self:_assertAlive()
	self._effect.Enabled = enabled
end

---Drains the Dumpster, nils every field, and freezes self.
function Emittable:Destroy()
	self:_assertAlive()
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
end

-- Constructor

---Creates an Emittable on `host`. The host can be any PVInstance with at least
---one BasePart. The effect is sized relative to the host and replicates
---natively.
function Emittable.new(host: PVInstance, params: Types.EmittableParams): Emittable
	assert(params, "params is required")
	assert(params.Style, "params.Style is required")

	local hostPart = findAnyBasePart(host)
	assert(hostPart, `host "{host:GetFullName()}" must contain at least one BasePart`)

	local mainDump = Dumpster.new()
	mainDump:AttachTo(hostPart)

	local style = params.Style
	local effect: Instance

	if style == "fire" then
		effect = buildFire(hostPart, params)
	elseif style == "smoke" then
		effect = buildSmoke(hostPart, params)
	elseif style == "sparkles" or style == "embers" or style == "magic" or style == "steam" then
		effect = buildParticleEmitter(hostPart, params, style)
	else
		error(`unknown EffectStyle "{style}"`)
	end

	mainDump:Add(effect)

	local self = setmetatable({
		_dumpster = mainDump,
		_host = hostPart,
		_effect = effect,
	}, Emittable)

	return self
end

-- Types

export type EffectStyle = Types.EffectStyle
export type EmittableParams = Types.EmittableParams
export type Emittable = typeof(Emittable)

return Emittable

--[[
	File: FX.luau
]]--

-- Root

local FX = {}

-- Roblox Services

local CollectionService = game:GetService("CollectionService")

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Constants

local ROTOR_MOTOR_PREFIX = "RotorMotor"
local BLUR_DISK_NAME = "BlurDisk"
local DEFAULT_VISIBLE_TRANSPARENCY = 0
local FLAME_MOTOR_NAME = "JetFlameMotor"

-- Types

type JetFlame = {
	Mesh: BasePart,
	Motor: Motor6D,
	FullLength: number,
	RadiusX: number,
	RadiusZ: number,
	VisibleTransparency: number,
}

-- Module State

local active = false
local rotorMotors: { Motor6D } = {}
local blurDisks: { BasePart } = {}
local jetFlames: { JetFlame } = {}
local rotorAngle = 0

-- Local Functions

local function getRotorMotors(root: BasePart): { Motor6D }
	local motors: { Motor6D } = {}
	for _, child in root:GetChildren() do
		if child:IsA("Motor6D") and string.sub(child.Name, 1, #ROTOR_MOTOR_PREFIX) == ROTOR_MOTOR_PREFIX then
			table.insert(motors, child)
		end
	end
	return motors
end

local function getMotorSpinAxis(motor: Motor6D): Vector3
	local x = motor:GetAttribute("SpinAxisX") or 0
	local y = motor:GetAttribute("SpinAxisY") or 0
	local z = motor:GetAttribute("SpinAxisZ") or 1
	return Vector3.new(x, y, z)
end

local function getBlurDisks(planeModel: Model): { BasePart }
	local disks: { BasePart } = {}
	for _, child in planeModel:GetChildren() do
		if child:IsA("BasePart") and child.Name == BLUR_DISK_NAME then
			table.insert(disks, child)
		end
	end
	return disks
end

local function getJetFlames(planeModel: Model): { JetFlame }
	local flames: { JetFlame } = {}
	for _, descendant in planeModel:GetDescendants() do
		if not (descendant:IsA("BasePart") and CollectionService:HasTag(descendant, Constants.JET_FLAME_TAG)) then
			continue
		end

		local motor = descendant:FindFirstChild(FLAME_MOTOR_NAME)
		if not (motor and motor:IsA("Motor6D")) then
			continue
		end

		table.insert(flames, {
			Mesh = descendant,
			Motor = motor,
			FullLength = descendant:GetAttribute("FlameFullLength") or descendant.Size.Y,
			RadiusX = descendant:GetAttribute("FlameRadiusX") or descendant.Size.X,
			RadiusZ = descendant:GetAttribute("FlameRadiusZ") or descendant.Size.Z,
			VisibleTransparency = descendant:GetAttribute("FlameVisibleTransparency") or 0,
		})
	end

	return flames
end

-- Public Functions

function FX.enable(planeModel: Model, root: BasePart)
	if active then return end
	active = true

	rotorMotors = getRotorMotors(root)
	blurDisks = getBlurDisks(planeModel)
	jetFlames = getJetFlames(planeModel)
	rotorAngle = 0
end

function FX.disable()
	if not active then return end
	active = false

	for _, disk in blurDisks do
		disk.Transparency = 1
	end

	for _, flame in jetFlames do
		flame.Mesh.Transparency = 1
		flame.Mesh.Size = Vector3.new(flame.RadiusX, Constants.MIN_FLAME_LENGTH, flame.RadiusZ)
		flame.Motor.C0 = CFrame.new(0, Constants.MIN_FLAME_LENGTH * 0.5, 0)
	end

	rotorMotors = {}
	blurDisks = {}
	jetFlames = {}
end

function FX.update(speedRatio: number, throttleRatio: number, dt: number)
	if not active then return end

	local rotorRatio = Constants.ROTOR_MIN_RATIO
		+ (1 - Constants.ROTOR_MIN_RATIO) * math.clamp(throttleRatio, 0, 1)
	rotorAngle += rotorRatio * Constants.ROTOR_MAX_RADS_PER_SEC * dt

	for _, motor in rotorMotors do
		local axis = getMotorSpinAxis(motor)
		motor.Transform = CFrame.fromAxisAngle(axis, rotorAngle)
	end

	local fadeRange = math.max(Constants.BLUR_DISK_FADE_END_RATIO - Constants.BLUR_DISK_FADE_START_RATIO, 1e-3)
	local visibility = math.clamp((speedRatio - Constants.BLUR_DISK_FADE_START_RATIO) / fadeRange, 0, 1)
	for _, disk in blurDisks do
		local visibleTransparency = disk:GetAttribute("VisibleTransparency") or DEFAULT_VISIBLE_TRANSPARENCY
		disk.Transparency = 1 - visibility * (1 - visibleTransparency)
	end

	local flameAlpha = math.clamp(throttleRatio, 0, 1)
	for _, flame in jetFlames do
		local length = math.max(Constants.MIN_FLAME_LENGTH, flame.FullLength * flameAlpha)
		flame.Mesh.Size = Vector3.new(flame.RadiusX, length, flame.RadiusZ)
		flame.Motor.C0 = CFrame.new(0, length * 0.5, 0)
		flame.Mesh.Transparency = 1 - flameAlpha * (1 - flame.VisibleTransparency)
	end
end

-- Return

return FX

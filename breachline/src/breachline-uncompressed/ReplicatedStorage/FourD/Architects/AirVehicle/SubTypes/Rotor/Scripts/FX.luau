--[[
	File: FX.luau
]]--

-- Root

local FX = {}

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Constants

local MAIN_MOTOR_PREFIX = "MainRotorMotor"
local TAIL_MOTOR_PREFIX = "TailRotorMotor"
local BLUR_DISK_NAME = "BlurDisk"
local DEFAULT_VISIBLE_TRANSPARENCY = 0

-- Module State

local active = false
local mainMotors: { Motor6D } = {}
local tailMotors: { Motor6D } = {}
local blurDisks: { BasePart } = {}
local mainAngle = 0
local tailAngle = 0

-- Local Functions

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

local function getMotors(root: BasePart): ({ Motor6D }, { Motor6D })
	local main: { Motor6D } = {}
	local tail: { Motor6D } = {}
	for _, child in root:GetChildren() do
		if not child:IsA("Motor6D") then continue end
		local kind = child:GetAttribute(Constants.ROTOR_KIND_ATTRIBUTE)
		if kind == Constants.ROTOR_KIND_MAIN or startsWith(child.Name, MAIN_MOTOR_PREFIX) then
			table.insert(main, child)
		elseif kind == Constants.ROTOR_KIND_TAIL or startsWith(child.Name, TAIL_MOTOR_PREFIX) then
			table.insert(tail, child)
		end
	end
	return main, tail
end

local function getBlurDisks(rotorModel: Model): { BasePart }
	local disks: { BasePart } = {}
	for _, child in rotorModel:GetChildren() do
		if child:IsA("BasePart") and child.Name == BLUR_DISK_NAME then
			table.insert(disks, child)
		end
	end
	return disks
end

-- Public Functions

function FX.enable(rotorModel: Model, root: BasePart)
	if active then return end
	active = true

	mainMotors, tailMotors = getMotors(root)
	blurDisks = getBlurDisks(rotorModel)
	mainAngle = 0
	tailAngle = 0
end

function FX.disable()
	if not active then return end
	active = false

	for _, disk in blurDisks do
		disk.Transparency = 1
	end

	mainMotors = {}
	tailMotors = {}
	blurDisks = {}
end

function FX.update(intensityRatio: number, speedRatio: number, dt: number)
	if not active then return end

	local clampedIntensity = math.clamp(intensityRatio, 0, 1)
	local rotorRatio = Constants.ROTOR_MIN_RATIO
		+ (1 - Constants.ROTOR_MIN_RATIO) * clampedIntensity

	mainAngle += rotorRatio * Constants.MAIN_ROTOR_RADS_PER_SEC * dt
	tailAngle += rotorRatio * Constants.TAIL_ROTOR_RADS_PER_SEC * dt

	for _, motor in mainMotors do
		motor.Transform = CFrame.fromAxisAngle(Vector3.xAxis, mainAngle)
	end

	for _, motor in tailMotors do
		motor.Transform = CFrame.fromAxisAngle(Vector3.xAxis, tailAngle)
	end

	for _, disk in blurDisks do
		local visibleTransparency = disk:GetAttribute("VisibleTransparency") or DEFAULT_VISIBLE_TRANSPARENCY
		disk.Transparency = visibleTransparency
	end
end

-- Return

return FX

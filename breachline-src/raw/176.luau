--[[
	File: BuildPropellers.luau
]]--

-- Root

local BuildPropellers = {}

-- Dependencies

local AirVehicleRoot = script.Parent.Parent.Parent.Parent
local CommonBuildPropellers = require(AirVehicleRoot.Common.BuildPropellers)

-- Constants

local ROTOR_MOTOR_PREFIX = "RotorMotor"
local BLUR_DISK_INITIAL_TRANSPARENCY = 1

-- Local Functions

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function buildRotorMotor(root: BasePart, rotorRoot: BasePart, spinAxis: Vector3, motorName: string)
	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Part0 = root
	motor.Part1 = rotorRoot
	motor.C0 = root.CFrame:Inverse() * rotorRoot.CFrame
	motor.C1 = CFrame.identity
	local localSpin = root.CFrame:VectorToObjectSpace(spinAxis).Unit
	motor:SetAttribute("SpinAxisX", localSpin.X)
	motor:SetAttribute("SpinAxisY", localSpin.Y)
	motor:SetAttribute("SpinAxisZ", localSpin.Z)
	motor.Parent = root
end

-- Public Functions

function BuildPropellers.rig(
	planeModel: Model,
	root: BasePart,
	propellers: { PVInstance }?,
	blurDiskOpacity: number
)
	CommonBuildPropellers.rig({
		WrapperModel = planeModel,
		Root = root,
		Propellers = propellers,
		MotorPrefix = ROTOR_MOTOR_PREFIX,
		BlurDiskOpacity = blurDiskOpacity,
		BlurDiskInitialTransparency = BLUR_DISK_INITIAL_TRANSPARENCY,
		MotorBuilder = buildRotorMotor,
		WarnLabel = "propeller",
	})
end

function BuildPropellers.rigThrustersStub(thrusters: { PVInstance }?)
	if not thrusters or #thrusters == 0 then return end
	vwarn(`Plane jet thrust not yet implemented; {#thrusters} thruster(s) tracked only`)
end

-- Return

return BuildPropellers

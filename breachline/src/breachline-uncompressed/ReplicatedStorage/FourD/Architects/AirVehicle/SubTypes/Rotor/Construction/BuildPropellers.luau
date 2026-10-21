--[[
	File: BuildPropellers.luau
]]--

-- Root

local BuildPropellers = {}

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local AirVehicleRoot = script.Parent.Parent.Parent.Parent
local CommonBuildPropellers = require(AirVehicleRoot.Common.BuildPropellers)

local _ = FourD

-- Constants

local ROTOR_KIND_ATTRIBUTE = "RotorKind"

-- Local Functions

local function makeMotorBuilder(rotorKind: string)
	return function(root: BasePart, rotorRoot: BasePart, spinAxis: Vector3, motorName: string)
		local spinAxisLocal = root.CFrame:VectorToObjectSpace(spinAxis).Unit
		local rotorPosLocal = root.CFrame:PointToObjectSpace(rotorRoot.Position)

		local upHint = if math.abs(spinAxisLocal.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
		local upLocal = upHint - spinAxisLocal * upHint:Dot(spinAxisLocal)
		if upLocal.Magnitude < 1e-3 then
			upLocal = Vector3.xAxis
		end
		upLocal = upLocal.Unit

		local jointC0 = CFrame.fromMatrix(rotorPosLocal, spinAxisLocal, upLocal)
		local jointWorld = root.CFrame * jointC0

		local motor = Instance.new("Motor6D")
		motor.Name = motorName
		motor.Part0 = root
		motor.Part1 = rotorRoot
		motor.C0 = jointC0
		motor.C1 = rotorRoot.CFrame:ToObjectSpace(jointWorld)
		motor:SetAttribute(ROTOR_KIND_ATTRIBUTE, rotorKind)
		motor.Parent = root
	end
end

-- Public Functions

function BuildPropellers.rig(
	rotorModel: Model,
	root: BasePart,
	propellers: { PVInstance }?,
	motorPrefix: string,
	rotorKind: string,
	blurDiskOpacity: number
)
	CommonBuildPropellers.rig({
		WrapperModel = rotorModel,
		Root = root,
		Propellers = propellers,
		MotorPrefix = motorPrefix,
		BlurDiskOpacity = blurDiskOpacity,
		BlurDiskInitialTransparency = blurDiskOpacity,
		MotorBuilder = makeMotorBuilder(rotorKind),
		WarnLabel = `{rotorKind} rotor`,
	})
end

-- Return

return BuildPropellers

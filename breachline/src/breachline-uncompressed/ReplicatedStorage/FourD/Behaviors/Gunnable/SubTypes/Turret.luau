--[[
	File: SubTypes/Turret/init.luau

	Rigs a managed turret mount: TurretMount + Motor6D for aim, optional
	caller-supplied DriverSeat fallback, optional caller-supplied GunnerSeat
	(with auto-generated ProximityPrompt + SwapRole event when present).
	Handles mounting and aiming only — firing is provided by sibling
	Hardpoint/Launcher SubTypes bound via the TurretHandle.
]]--

local FourD = script:FindFirstAncestor("FourD")
local Common = script.Parent.Parent.Common
local DiscoverMounts = require(Common.DiscoverMounts)
local Types = require(Common.Types)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local Keybinds = require(FourD.Common.Keybinds)

local DEFAULT_TURRET_SPEED = 540

local Turret = {}

local function createSeatRef(parent: Model, name: string, value: Instance?)
	local ov = Instance.new("ObjectValue")
	ov.Name = name
	ov.Value = value
	ov.Parent = parent
end

local function createMountPart(name: string, cframe: CFrame, parent: Model): BasePart
	local mount = Instance.new("Part")
	mount.Name = name
	mount.Size = Vector3.new(0.5, 0.5, 0.5)
	mount.Transparency = 1
	mount.CanCollide = false
	mount.Massless = true
	mount.Anchored = false
	mount.CFrame = cframe
	mount.Parent = parent
	return mount
end

local function weldPartsToMount(mount: BasePart, sourceModel: Instance)
	for _, part in ipairs(GeometryUtils.getInstanceParts(sourceModel)) do
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		local weld = Instance.new("Weld")
		weld.Part0 = mount
		weld.Part1 = part
		weld.C0 = mount.CFrame:Inverse() * part.CFrame
		weld.C1 = CFrame.new()
		weld.Parent = mount
	end
end

function Turret.rig(assembledModel: Model, gunModel: Model, mounts: DiscoverMounts.Mounts, config: Types.TurretConfig)
	local pitchUpDeg = config.GunnerPitchUp or 60
	local pitchDownDeg = config.GunnerPitchDown or 25

	local chassis = mounts.Chassis
	local pivotCFrame = mounts.PivotCFrame

	local chassisUp = chassis.CFrame.UpVector
	local flatForward = pivotCFrame.LookVector - pivotCFrame.LookVector:Dot(chassisUp) * chassisUp
	if flatForward.Magnitude < 1e-4 then
		flatForward = chassis.CFrame.LookVector
	end

	pivotCFrame = CFrame.lookAlong(pivotCFrame.Position, flatForward.Unit, chassisUp)

	-- Split-axis rig: yaw model turns on its own axis, gun model pitches on top of it,
	-- so a barrel offset from the yaw centre still orbits that centre instead of its own
	local yawModel = config.YawModel
	local pitchPart = chassis
	local baseC0 = chassis.CFrame:Inverse() * pivotCFrame

	if yawModel then
		local yawCFrame = CFrame.lookAlong(GeometryUtils.getInstanceCFrame(yawModel).Position, flatForward.Unit, chassisUp)
		local yawMount = createMountPart("TurretYawMount", yawCFrame, assembledModel)
		local yawBaseC0 = chassis.CFrame:Inverse() * yawCFrame

		local yawMotor = Instance.new("Motor6D")
		yawMotor.Name = "TurretYawMotor"
		yawMotor.Part0 = chassis
		yawMotor.Part1 = yawMount
		yawMotor.C0 = yawBaseC0
		yawMotor.C1 = CFrame.new()
		yawMotor.Parent = chassis

		local yawBaseC0Value = Instance.new("CFrameValue")
		yawBaseC0Value.Name = "TurretYawBaseC0"
		yawBaseC0Value.Value = yawBaseC0
		yawBaseC0Value.Parent = assembledModel

		weldPartsToMount(yawMount, yawModel)
		yawModel.Parent = assembledModel

		pitchPart = yawMount
		baseC0 = yawCFrame:Inverse() * pivotCFrame
	end

	local turretMount = createMountPart("TurretMount", pivotCFrame, assembledModel)

	local motor = Instance.new("Motor6D")
	motor.Name = "TurretMotor"
	motor.Part0 = pitchPart
	motor.Part1 = turretMount
	motor.C0 = baseC0
	motor.C1 = CFrame.new()
	motor.Parent = pitchPart

	local baseC0Value = Instance.new("CFrameValue")
	baseC0Value.Name = "TurretBaseC0"
	baseC0Value.Value = baseC0
	baseC0Value.Parent = assembledModel

	weldPartsToMount(turretMount, gunModel)

	gunModel.Parent = assembledModel

	if config.DriverSeat then
		createSeatRef(assembledModel, "Gunnable_DriverSeatRef", config.DriverSeat)
		if config.DriverSeat:IsA("VehicleSeat") then
			config.DriverSeat.HeadsUpDisplay = false
		end
	end

	local hasGunnerSeat = config.GunnerSeat ~= nil
	if hasGunnerSeat then
		createSeatRef(assembledModel, "Gunnable_GunnerSeatRef", config.GunnerSeat)

		local body = assembledModel:FindFirstChild("body")
		local bodySize = if body then GeometryUtils.getInstanceSize(body) else chassis.Size
		local promptDist = bodySize.X * 0.5 + 10

		local gunnerPromptAtt = Instance.new("Attachment")
		gunnerPromptAtt.Name = "GunnerPromptAttachment"
		gunnerPromptAtt.Parent = chassis

		local gunnerPrompt = Instance.new("ProximityPrompt")
		gunnerPrompt.Name = "GunnerPrompt"
		gunnerPrompt.ActionText = "Enter as Gunner"
		gunnerPrompt.ObjectText = ""
		gunnerPrompt.MaxActivationDistance = promptDist
		gunnerPrompt.HoldDuration = 0
		gunnerPrompt.KeyboardKeyCode = Keybinds.getKeyboardKey("Gunnable.Turret", "EnterGunner") :: Enum.KeyCode
		gunnerPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		gunnerPrompt.RequiresLineOfSight = false
		gunnerPrompt.Enabled = false
		gunnerPrompt.Parent = gunnerPromptAtt

		local swapRoleEvent = Instance.new("RemoteEvent")
		swapRoleEvent.Name = "SwapRole"
		swapRoleEvent.Parent = assembledModel
	end

	local updateTurretEvent = Instance.new("RemoteEvent")
	updateTurretEvent.Name = "UpdateTurret"
	updateTurretEvent.Parent = assembledModel

	local turretFireEvent = Instance.new("RemoteEvent")
	turretFireEvent.Name = "TurretFire"
	turretFireEvent.Parent = assembledModel

	assembledModel:SetAttribute("gunnerActive", false)
	assembledModel:SetAttribute("turretYaw", 0)
	assembledModel:SetAttribute("turretPitch", 0)
	assembledModel:SetAttribute("gunnerPitchUp", pitchUpDeg)
	assembledModel:SetAttribute("gunnerPitchDown", pitchDownDeg)
	assembledModel:SetAttribute("Gunnable_HasDriverSeat", config.DriverSeat ~= nil)
	assembledModel:SetAttribute("Gunnable_HasGunnerSeat", hasGunnerSeat)
	assembledModel:SetAttribute("Gunnable_HasYawMotor", yawModel ~= nil)
	assembledModel:SetAttribute("Gunnable_FirstPerson", config.FirstPerson == true)
	assembledModel:SetAttribute("Gunnable_DisablePitch", config.DisablePitch == true)
	assembledModel:SetAttribute("Gunnable_DisableYaw", config.DisableYaw == true)
	assembledModel:SetAttribute("Gunnable_DisableCrosshair", config.DisableCrosshair == true)
	assembledModel:SetAttribute("Gunnable_TurretSpeed", config.TurretSpeed or DEFAULT_TURRET_SPEED)
end

function Turret.attachScripts(assembledModel: Model)
	local serverScript = script:FindFirstChild("TurretServer")
	if serverScript then
		local clone = serverScript:Clone()
		clone.Enabled = true
		clone.Parent = assembledModel
	end

	local clientScript = script:FindFirstChild("TurretClient")
	if clientScript then
		local clone = clientScript:Clone()
		if clone:IsA("BaseScript") then
			clone.Enabled = true
		end
		clone.Parent = assembledModel
	end
end

return Turret

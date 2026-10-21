--[[
	File: Board.luau
]]--

-- Root

local Board = {}
Board.__index = Board

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local BoardConstants = require(script.Scripts.Constants)
local CreateConfiguration = require(FourD.Common.createConfiguration)
local DamageController = require(FourD.Common.DamageController)
local Dumpster = require(FourD.Libs.Dumpster)
local Heuristics = require(script.Heuristics)

-- Object References

local Assets = ReplicatedStorage:WaitForChild("Assets", 5)
local Rigs = Assets and Assets:WaitForChild("Rigs", 5)
local BoardRigTemplate = Rigs and Rigs:WaitForChild("WheeledVehicle_board", 5)
if not BoardRigTemplate then
	error("WheeledVehicle/Board: missing ReplicatedStorage.Assets.Rigs.WheeledVehicle_board template. "
		.. "Bring the rig over from place.rbxl or any scene that ships it.")
end

-- Constants

local VERBOSE_LOGGING = true
local RIG_DEBUG_MODE = false
local CHASSIS_DENSITY = 0.2
local WHEEL_DENSITY = 4
local WHEEL_FRICTION = 1
local WHEEL_FRICTION_WEIGHT = 1
local WHEEL_ELASTICITY = 0.1
local WHEEL_ELASTICITY_WEIGHT = 1
local MOTOR_TORQUE_SAFETY_FACTOR = 10
local STEER_AUTHORITY_INERTIA_FACTOR = 4
local STEER_AUTHORITY_FRICTION_FACTOR = 4
local STEER_AUTHORITY_SAFETY_FACTOR = 5
local STEER_AUTHORITY_AIR_FACTOR = 0.25
local STEER_FRICTION_COEFFICIENT = 1.5
local STEER_SPIN_UP_TIME = 0.15
local STEER_INPUT_DEADZONE = 0.05
local STABILIZE_GYRO_P = 200
local STABILIZE_GYRO_D = 200
local STABILIZE_TORQUE_FACTOR = 0.5
local STABILIZE_LANDING_GRACE = 0.2
local RIG_WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }
local DEFAULT_PERFORMANCE = {
	AccelerationSpeed = 15,
	MaxSpeed = 30,
	TurnSpeed = 90,
	TurnSpeedAirMult = 1.5,
	OllieImpulse = 90,
	MaxInclineDegrees = 60,
	OllieCooldown = 0.4,
	RedressCooldown = 2.0,
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function enableScripts(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = false
		end
	end
end

local function cloneRigScripts(boardRig: Model)
	local scripts = script.Scripts:Clone()
	scripts.Parent = boardRig
end

local function enableRigScripts(boardRig: Model)
	local scripts = boardRig:FindFirstChild("Scripts")
	if scripts then
		enableScripts(scripts)
	end
end

local function mergePerformanceDefaults(performance: Performance?): Performance
	local merged = {}
	for key, value in DEFAULT_PERFORMANCE do
		merged[key] = value
	end

	if performance then
		for key, value in performance do
			if value == nil then continue end
			merged[key] = value
		end
	end

	return merged
end

local function applyWheelPhysicalProperties(wheelPart: BasePart)
	wheelPart.CustomPhysicalProperties = PhysicalProperties.new(
		WHEEL_DENSITY,
		WHEEL_FRICTION,
		WHEEL_ELASTICITY,
		WHEEL_FRICTION_WEIGHT,
		WHEEL_ELASTICITY_WEIGHT
	)
	wheelPart.Massless = false
end

local function applyChassisPhysicalProperties(chassis: BasePart)
	local existing = chassis.CustomPhysicalProperties
	chassis.CustomPhysicalProperties = PhysicalProperties.new(
		CHASSIS_DENSITY,
		if existing then existing.Friction else 0.7,
		if existing then existing.Elasticity else 0.3,
		if existing then existing.FrictionWeight else 1,
		if existing then existing.ElasticityWeight else 1
	)
	chassis.Massless = false
end

-- Private Methods

function Board:_buildTool()
	local container: Model = self._container
	local schema = self._params.Schema

	local function anchorAll(source: Instance)
		for _, descendant in source:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
	end

	anchorAll(container)
	anchorAll(schema.WheelFL)
	anchorAll(schema.WheelFR)
	anchorAll(schema.WheelRL)
	anchorAll(schema.WheelRR)
	for _, extraPart in self._params.ExtraParts do
		anchorAll(extraPart)
	end

	local originalParent = container.Parent
	local rootName = if originalParent then originalParent.Name else container.Name
	local tool = Instance.new("Tool")
	tool.Name = `WheeledVehicleBoard_{rootName}`
	tool.RequiresHandle = true
	tool.CanBeDropped = true
	tool.Grip = CFrame.new()
	tool.Parent = originalParent
	self.mainDump:Add(tool)

	container.Parent = tool
	schema.WheelFL.Parent = tool
	schema.WheelFR.Parent = tool
	schema.WheelRL.Parent = tool
	schema.WheelRR.Parent = tool
	for _, extraPart in self._params.ExtraParts do
		extraPart.Parent = tool
	end

	self.vehicleModel = tool
end

function Board:_rigFunctional()
	local root: Model = self.vehicleModel
	local container = self._container
	local schema = self._params.Schema
	local flWheel = schema.WheelFL
	local frWheel = schema.WheelFR
	local rlWheel = schema.WheelRL
	local rrWheel = schema.WheelRR

	local originalPivot = root:GetPivot()

	Heuristics.prepareGeometry(root, flWheel, frWheel, rlWheel, rrWheel, container)

	local boardRig = BoardRigTemplate:Clone()

	local rigInfo = Heuristics.updateBoardRig(boardRig, flWheel, frWheel, rlWheel, rrWheel, container)
	Heuristics.attachGeometryToBoardRig(boardRig, flWheel, frWheel, rlWheel, rrWheel, container, self._params.ExtraParts)

	local chassis = boardRig:WaitForChild("Chassis")
	applyChassisPhysicalProperties(chassis)

	local wheelsFolder = boardRig:WaitForChild("Wheels")
	local wheelParts: { BasePart } = {}
	local refreshedTotalMass = chassis.Mass
	for _, wheelName in RIG_WHEEL_NAMES do
		local wheelPart = (wheelsFolder:WaitForChild(wheelName)):WaitForChild("Wheel")
		applyWheelPhysicalProperties(wheelPart)
		refreshedTotalMass += wheelPart.Mass
		table.insert(wheelParts, wheelPart)
	end

	cloneRigScripts(boardRig)

	local steerAttachment = chassis:FindFirstChild("SteerAttachment")
	if not steerAttachment then
		steerAttachment = Instance.new("Attachment")
		steerAttachment.Name = "SteerAttachment"
		steerAttachment.Parent = chassis
	end

	local steerAngularVelocity = Instance.new("BodyAngularVelocity")
	steerAngularVelocity.Name = "SteerAngularVelocity"
	steerAngularVelocity.AngularVelocity = Vector3.zero
	steerAngularVelocity.MaxTorque = Vector3.zero
	steerAngularVelocity.P = 1250
	steerAngularVelocity.Parent = chassis

	local redressAttachment = chassis:FindFirstChild("RedressAttachment")
	if not redressAttachment then
		redressAttachment = Instance.new("Attachment")
		redressAttachment.Name = "RedressAttachment"
		redressAttachment.Parent = chassis
	end

	local redressOrientation = Instance.new("AlignOrientation")
	redressOrientation.Name = "RedressOrientation"
	redressOrientation.Attachment0 = redressAttachment
	redressOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	redressOrientation.MaxTorque = 1e6
	redressOrientation.Responsiveness = 25
	redressOrientation.RigidityEnabled = false
	redressOrientation.Enabled = false
	redressOrientation.Parent = chassis

	local stabilityGyro = Instance.new("BodyGyro")
	stabilityGyro.Name = "StabilityGyro"
	stabilityGyro.CFrame = CFrame.new()
	stabilityGyro.MaxTorque = Vector3.zero
	stabilityGyro.P = STABILIZE_GYRO_P
	stabilityGyro.D = STABILIZE_GYRO_D
	stabilityGyro.Parent = chassis

	local remotes = boardRig:WaitForChild("Remotes")
	for _, remoteName in { BoardConstants.OLLIE_REMOTE_NAME, BoardConstants.REDRESS_REMOTE_NAME } do
		if remotes:FindFirstChild(remoteName) then continue end
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotes
	end

	-- Owner/OwnerLock are runtime ownership slots the server populates during
	-- Play; they are intentionally empty in the serialized rig. Mark them so the
	-- edit-time inspect gate does not read the empty value as a broken reference.
	local ownerValue = Instance.new("ObjectValue")
	ownerValue.Name = BoardConstants.OWNER_VALUE_NAME
	ownerValue.Value = nil
	ownerValue:SetAttribute("FourDRuntimeSlot", true)
	ownerValue.Parent = boardRig

	local ownerLockValue = Instance.new("ObjectValue")
	ownerLockValue.Name = BoardConstants.OWNER_LOCK_VALUE_NAME
	ownerLockValue.Value = self._params.Owner
	ownerLockValue:SetAttribute("FourDRuntimeSlot", true)
	ownerLockValue.Parent = boardRig

	local performance = self._params.Performance
	local gravity = workspace.Gravity
	local incline = math.rad(performance.MaxInclineDegrees)
	local motorMaxTorque = (refreshedTotalMass * gravity * math.sin(incline) * rigInfo.wheelRadius)
		* MOTOR_TORQUE_SAFETY_FACTOR

	local hingeMaxTorque = motorMaxTorque / 4
	for _, wheelPart in wheelParts do
		local hinge = wheelPart:FindFirstChildOfClass("HingeConstraint")
		assert(hinge, `Board: {wheelPart.Parent.Name} missing HingeConstraint`)
		hinge.MotorMaxTorque = hingeMaxTorque
		hinge.MotorMaxAcceleration = math.huge
		hinge.AngularVelocity = 0
		hinge.ActuatorType = Enum.ActuatorType.None
	end

	local config = {
		AccelerationSpeed = performance.AccelerationSpeed,
		MaxSpeed = performance.MaxSpeed,
		TurnSpeed = performance.TurnSpeed,
		TurnSpeedAirMult = performance.TurnSpeedAirMult,
		OllieImpulse = performance.OllieImpulse,
		MaxInclineDegrees = performance.MaxInclineDegrees,
		WheelRadius = rigInfo.wheelRadius,
		MotorMaxTorque = motorMaxTorque,
		SteerAuthorityInertiaFactor = STEER_AUTHORITY_INERTIA_FACTOR,
		SteerAuthorityFrictionFactor = STEER_AUTHORITY_FRICTION_FACTOR,
		SteerAuthoritySafetyFactor = STEER_AUTHORITY_SAFETY_FACTOR,
		SteerAuthorityAirFactor = STEER_AUTHORITY_AIR_FACTOR,
		SteerFrictionCoefficient = STEER_FRICTION_COEFFICIENT,
		SteerSpinUpTime = STEER_SPIN_UP_TIME,
		SteerInputDeadzone = STEER_INPUT_DEADZONE,
		OllieCooldown = performance.OllieCooldown,
		RedressCooldown = performance.RedressCooldown,
		StabilizeTorqueFactor = STABILIZE_TORQUE_FACTOR,
		StabilizeLandingGrace = STABILIZE_LANDING_GRACE,
	}
	CreateConfiguration(root, config, "BoardConfig")

	DamageController.new(root, 1)

	boardRig.Parent = root
	root:PivotTo(originalPivot)

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
			descendant.Anchored = false
		end
	end

	if RIG_DEBUG_MODE then
		for _, descendant in boardRig:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = 0.5
			end
		end
		chassis.Anchored = true
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = chassis.Size
	handle.CFrame = chassis.CFrame
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = true
	handle.Massless = true
	handle.Anchored = false
	handle.Parent = root

	self.boardRig = boardRig
end

function Board:_rigVehicle()
	self:_buildTool()
	self:_rigFunctional()
	enableRigScripts(self.boardRig)
end

-- Public Methods

function Board:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self.mainDump:Destroy()
	for k in self do rawset(self, k, nil) end

	table.freeze(self)
end

-- Constructor

function Board.new(container: Model | BasePart, params: SetupParams): BoardInstance
	assert(container ~= nil, "must supply container")
	if container:IsA("BasePart") then
		local bodyPart = container
		local bodyModel = Instance.new("Model")
		bodyModel.Name = bodyPart.Name
		bodyModel.Parent = bodyPart.Parent
		bodyPart.Parent = bodyModel
		container = bodyModel
	end
	assert(container:IsA("Model"), "container must be a Model or BasePart")
	assert(params ~= nil, "must supply params")
	assert(params.Schema ~= nil, "params.Schema is required")
	assert(
		params.Schema.WheelFL and (params.Schema.WheelFL:IsA("BasePart") or params.Schema.WheelFL:IsA("Model")),
		"Schema.WheelFL must be a BasePart or Model"
	)
	assert(
		params.Schema.WheelFR and (params.Schema.WheelFR:IsA("BasePart") or params.Schema.WheelFR:IsA("Model")),
		"Schema.WheelFR must be a BasePart or Model"
	)
	assert(
		params.Schema.WheelRL and (params.Schema.WheelRL:IsA("BasePart") or params.Schema.WheelRL:IsA("Model")),
		"Schema.WheelRL must be a BasePart or Model"
	)
	assert(
		params.Schema.WheelRR and (params.Schema.WheelRR:IsA("BasePart") or params.Schema.WheelRR:IsA("Model")),
		"Schema.WheelRR must be a BasePart or Model"
	)

	if params.ExtraParts then
		for index, extraPart in params.ExtraParts do
			assert(
				typeof(extraPart) == "Instance" and (extraPart:IsA("BasePart") or extraPart:IsA("Model")),
				`ExtraParts[{index}] must be a BasePart or Model`
			)
		end
	end

	local self = setmetatable({}, Board)

	self.mainDump = Dumpster.new()
	self.vehicleModel = nil
	self.boardRig = nil

	self._container = container
	self._params = {
		Schema = params.Schema,
		Performance = mergePerformanceDefaults(params.Performance),
		Owner = params.Owner,
		ExtraParts = params.ExtraParts or {},
	}

	self:_rigVehicle()
	vprint(`Completed setup on {container} with params:`, self._params)
	return self
end

-- Types

export type Schema = {
	WheelFL: PVInstance,
	WheelFR: PVInstance,
	WheelRL: PVInstance,
	WheelRR: PVInstance,
}
export type Performance = {
	AccelerationSpeed: number?,
	MaxSpeed: number?,
	TurnSpeed: number?,
	TurnSpeedAirMult: number?,
	OllieImpulse: number?,
	MaxInclineDegrees: number?,
	OllieCooldown: number?,
	RedressCooldown: number?,
}
export type SetupParams = {
	Schema: Schema,
	Performance: Performance?,
	Owner: Player?,
	ExtraParts: { PVInstance }?,
}
export type BoardInstance = {
	vehicleModel: Tool,
	boardRig: Model,
	mainDump: any,
	Destroy: (self: BoardInstance) -> (),
}

-- Return

return Board

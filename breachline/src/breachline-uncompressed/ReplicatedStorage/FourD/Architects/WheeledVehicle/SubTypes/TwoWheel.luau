--[[
	File: TwoWheel.luau
]]--

-- Root

local TwoWheel = {}
TwoWheel.__index = TwoWheel

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local BikeConstants = require(script.Scripts.Constants)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local CreateConfiguration = require(FourD.Common.createConfiguration)
local DamageController = require(FourD.Common.DamageController)
local Dumpster = require(FourD.Libs.Dumpster)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local Heuristics = require(script.Heuristics)
local RecenterModelPivot = require(FourD.Common.recenterModelPivot)

-- Object References

local BikeBuilderStarter = ReplicatedStorage.Assets.Rigs.WheeledVehicle_2w

-- Constants

local VERBOSE_LOGGING = true
local RIG_DEBUG_MODE = false
local TEMPLATE_SCRIPTS = {
	VehicleCameraHandler = true,
	DestructionHandler = true,
}
local DEFAULT_PERFORMANCE = {
	Acceleration = 40,
	Braking = 105,
	Deceleration = 35,
	EngineSpeedCorrection = 5,
	HasNitro = false,
	MaxSpeedForward = 70,
	MaxSpeedReverse = 30,
	MaxSpeedTorque = 50000,
	MinSpeedTorque = 250000,
	NitroAcceleration = 100,
	NitroMaxExtraSpeed = 35,
	NitroRechargeTime = 6,
	NitroTime = 3,
	NitroTorque = 15000,
	MaxSteerDegrees = 30,
	MaxLeanDegrees = 25,
	LeanGain = 1.0,
	BalanceStrength = 1200,
	BalanceDamping = 140,
	YawStrength = 18,
	MaxYawRate = 2.0,
	MaxInclineDegrees = 42,
	MuteEngineSound = false,
	JumpImpulse = 80,
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function enableScripts(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BaseScript") and not TEMPLATE_SCRIPTS[descendant.Name] then
			descendant.Disabled = false
		end
	end
end

local function cloneRigScripts(bikeRig: Model)
	local driverSeat = bikeRig:FindFirstChild("DriverSeat")
	assert(driverSeat, "WheeledVehicle: bikeRig.DriverSeat not found")

	local seatHandler = script.SeatEventHandler:Clone()
	seatHandler.Parent = driverSeat

	local scripts = script.Scripts:Clone()
	scripts.Parent = bikeRig
end

local function enableRigScripts(bikeRig: Model)
	local driverSeat = bikeRig:FindFirstChild("DriverSeat")
	if driverSeat then
		local seatHandler = driverSeat:FindFirstChild("SeatEventHandler")
		if seatHandler then
			seatHandler.Enabled = true
			enableScripts(seatHandler)
		end
	end

	local scripts = bikeRig:FindFirstChild("Scripts")
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

-- Private Methods

function TwoWheel:_buildWrapper()
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
	anchorAll(schema.WheelF)
	anchorAll(schema.WheelR)
	for _, extraPart in self._params.ExtraParts do
		anchorAll(extraPart)
	end

	local rootName = container.Name
	local wrapper = Instance.new("Model")
	wrapper.Name = `WheeledVehicle_{rootName}`
	wrapper.Parent = container.Parent
	self.mainDump:Add(wrapper)

	container.Parent = wrapper
	schema.WheelF.Parent = wrapper
	schema.WheelR.Parent = wrapper
	for _, extraPart in self._params.ExtraParts do
		extraPart.Parent = wrapper
	end

	self.vehicleModel = wrapper
end

function TwoWheel:_rigFunctional()
	local root = self.vehicleModel
	local container = self._container
	local schema = self._params.Schema
	local frontWheel = schema.WheelF
	local rearWheel = schema.WheelR

	local config = {}

	container.PrimaryPart = nil
	RecenterModelPivot(root)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Model") then
			RecenterModelPivot(descendant)
		end
	end

	local bikeCFrame = Heuristics.computeBikeCFrame(frontWheel, rearWheel, container)

	local _, bodySize = GeometryUtils.measureExtentsInFrame(GeometryUtils.getInstanceParts(container), bikeCFrame)
	bodySize = Vector3.new(
		math.max(bodySize.X, 0.05),
		math.max(bodySize.Y, 0.05),
		math.max(bodySize.Z, 0.05)
	)
	local bodyGeom = Instance.new("Part")
	bodyGeom.Name = "body_geom"
	bodyGeom.Size = bodySize
	bodyGeom.CFrame = bikeCFrame
	bodyGeom.Transparency = 1
	bodyGeom.CanCollide = false
	bodyGeom.Massless = true
	bodyGeom.Anchored = true
	bodyGeom.Parent = root
	root.PrimaryPart = bodyGeom

	Heuristics.prepareGeometry(root, frontWheel, rearWheel, container)

	local bikeRig = BikeBuilderStarter:Clone()
	for _, descendant in bikeRig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	Heuristics.updateBikeRig(bikeRig, frontWheel, rearWheel, container, bikeCFrame, self._params.Performance)
	Heuristics.attachGeometryToBikeRig(bikeRig, frontWheel, rearWheel, container, self._params.ExtraParts)

	cloneRigScripts(bikeRig)

	ConstructionHelpers.makeWeld(bikeRig:FindFirstChild("Chassis"), bodyGeom)

	local vehicleSeat = bikeRig:FindFirstChild("DriverSeat")
	assert(vehicleSeat, "WheeledVehicle: bikeRig.DriverSeat not found")
	vehicleSeat.WeldConstraint.Enabled = false
	Heuristics.placeDriverSeatOnSchemaSeat(root, vehicleSeat, container, bikeCFrame)
	vehicleSeat.CanCollide = false
	vehicleSeat.BrickColor = BrickColor.new("Black")
	vehicleSeat.Transparency = 1
	vehicleSeat.Massless = true
	vehicleSeat.WeldConstraint.Enabled = true

	local vehicleModelRef = vehicleSeat:FindFirstChild("VehicleModelRef")
	vehicleModelRef.Value = root

	CreateConfiguration(root, config, "BikeConfig")
	DamageController.new(root, 1)

	bikeRig.Parent = root

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	if RIG_DEBUG_MODE then
		for _, descendant in bikeRig:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = 0.5
			end
		end
		local chassis = bikeRig:FindFirstChild("Chassis")
		if chassis then
			chassis.Anchored = true
		end
	end

	self.bikeRig = bikeRig
	self.vehicleSeat = vehicleSeat
end

function TwoWheel:_applyPerformance()
	local engine = self.bikeRig:FindFirstChild("Engine")
	assert(engine, "WheeledVehicle: bikeRig.Engine not found")
	local performance = self._params.Performance

	local nitroMaxSpeed = performance.MaxSpeedForward + performance.NitroMaxExtraSpeed
	local nitroAcceleration = performance.Acceleration + performance.NitroAcceleration

	engine:SetAttribute("forwardMaxSpeed", performance.MaxSpeedForward)
	engine:SetAttribute("reverseMaxSpeed", performance.MaxSpeedReverse)
	engine:SetAttribute("acceleration", performance.Acceleration)
	engine:SetAttribute("deceleration", performance.Deceleration)
	engine:SetAttribute("braking", performance.Braking)
	engine:SetAttribute("engineSpeedCorrection", performance.EngineSpeedCorrection)
	engine:SetAttribute("minSpeedTorque", performance.MinSpeedTorque)
	engine:SetAttribute("maxSpeedTorque", performance.MaxSpeedTorque)
	engine:SetAttribute("nitroTorque", performance.NitroTorque)
	engine:SetAttribute("nitroTime", performance.NitroTime)
	engine:SetAttribute("nitroRechargeTime", performance.NitroRechargeTime)
	engine:SetAttribute("nitroMaxSpeed", nitroMaxSpeed)
	engine:SetAttribute("nitroAcceleration", nitroAcceleration)

	self.bikeRig:SetAttribute(BikeConstants.NITRO_USABLE_ATTRIBUTE, performance.HasNitro)
	self.bikeRig:SetAttribute(BikeConstants.MUTE_ENGINE_SOUND_ATTRIBUTE, performance.MuteEngineSound)

	local steering = self.bikeRig:FindFirstChild("Steering")
	if steering then
		local clampedSteer = Heuristics.clampMaxSteerDegrees(performance.MaxSteerDegrees)
		steering:SetAttribute("maxSteerDegrees", clampedSteer)
	end

	local chassis = self.bikeRig:FindFirstChild("Chassis")
	if chassis then
		chassis:SetAttribute("maxLeanDegrees", performance.MaxLeanDegrees)
		chassis:SetAttribute("leanGain", performance.LeanGain)
		chassis:SetAttribute("balanceStrength", performance.BalanceStrength)
		chassis:SetAttribute("balanceDamping", performance.BalanceDamping)
		chassis:SetAttribute("yawStrength", performance.YawStrength)
		chassis:SetAttribute("maxYawRate", performance.MaxYawRate)
		chassis:SetAttribute("maxInclineDegrees", performance.MaxInclineDegrees)
		chassis:SetAttribute("jumpImpulse", performance.JumpImpulse)
	end
end

function TwoWheel:_rigVehicle()
	self:_buildWrapper()
	self:_rigFunctional()
	self:_applyPerformance()
	enableRigScripts(self.bikeRig)
end

-- Public Methods

function TwoWheel:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self.mainDump:Destroy()
	for k in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function TwoWheel.new(container: Model, params: SetupParams): TwoWheelInstance
	assert(container ~= nil, "must supply container")
	assert(container:IsA("Model"), "container must be a Model")
	assert(params ~= nil, "must supply params")
	assert(params.Schema ~= nil, "params.Schema is required")
	assert(
		params.Schema.WheelF and (params.Schema.WheelF:IsA("BasePart") or params.Schema.WheelF:IsA("Model")),
		"Schema.WheelF must be a BasePart or Model"
	)
	assert(
		params.Schema.WheelR and (params.Schema.WheelR:IsA("BasePart") or params.Schema.WheelR:IsA("Model")),
		"Schema.WheelR must be a BasePart or Model"
	)
	assert(container:FindFirstChild("handlebars"), "container must contain a child named 'handlebars'")
	assert(container:FindFirstChild("front fork"), "container must contain a child named 'front fork'")

	if params.ExtraParts then
		for index, extraPart in params.ExtraParts do
			assert(
				typeof(extraPart) == "Instance" and (extraPart:IsA("BasePart") or extraPart:IsA("Model")),
				`ExtraParts[{index}] must be a BasePart or Model`
			)
		end
	end

	local self = setmetatable({}, TwoWheel)

	self.mainDump = Dumpster.new()
	self.vehicleModel = nil
	self.bikeRig = nil
	self.vehicleSeat = nil

	self._container = container
	self._params = {
		Schema = params.Schema,
		Performance = mergePerformanceDefaults(params.Performance),
		ExtraParts = params.ExtraParts or {},
	}

	self:_rigVehicle()
	vprint(`Completed setup on {container} with params:`, self._params)
	return self
end

-- Types

export type Schema = {
	WheelF: PVInstance,
	WheelR: PVInstance,
}

export type Performance = {
	Acceleration: number?,
	Braking: number?,
	Deceleration: number?,
	EngineSpeedCorrection: number?,
	HasNitro: boolean?,
	MaxSpeedForward: number?,
	MaxSpeedReverse: number?,
	MaxSpeedTorque: number?,
	MinSpeedTorque: number?,
	NitroAcceleration: number?,
	NitroMaxExtraSpeed: number?,
	NitroRechargeTime: number?,
	NitroTime: number?,
	NitroTorque: number?,
	MaxSteerDegrees: number?,
	MaxLeanDegrees: number?,
	LeanGain: number?,
	BalanceStrength: number?,
	BalanceDamping: number?,
	YawStrength: number?,
	MaxYawRate: number?,
	MaxInclineDegrees: number?,
	MuteEngineSound: boolean?,
	JumpImpulse: number?,
}

export type SetupParams = {
	Schema: Schema,
	Performance: Performance?,
	ExtraParts: { PVInstance }?,
}

export type TwoWheelInstance = {
	vehicleModel: Model,
	bikeRig: Model,
	vehicleSeat: Instance?,
	mainDump: any,
	Destroy: (self: TwoWheelInstance) -> (),
}

-- Return

return TwoWheel

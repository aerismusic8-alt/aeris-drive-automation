--[[
	File: FourWheel.luau
]]--

-- Root

local FourWheel = {}
FourWheel.__index = FourWheel

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local CarConstants = require(script.Scripts.Constants)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local CreateConfiguration = require(FourD.Common.createConfiguration)
local DamageController = require(FourD.Common.DamageController)
local Dumpster = require(FourD.Libs.Dumpster)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local Heuristics = require(script.Heuristics)
local recenterModelPivot = require(FourD.Common.recenterModelPivot)
local SeatHelpers = require(FourD.Common.SeatHelpers)

-- Object References

local CarBuilderStarter = ReplicatedStorage.Assets.Rigs.WheeledVehicle_4w

-- Constants

local VERBOSE_LOGGING = true
local RIG_DEBUG_MODE = false
local DEFAULT_SEAT_POSITION: "inside" | "ontop" = "ontop"
local TEMPLATE_SCRIPTS = {
	VehicleCameraHandler = true,
	DestructionHandler = true,
}
local TOWED_MASS_ATTRIBUTE = "HitchTowedMass"
local TOW_ASSIST_ROLLING_RESISTANCE = 0.05
local TOW_ASSIST_HEADROOM = 1.25
local TOW_ASSIST_REFRESH_INTERVAL = 0.25
local TOW_ASSIST_WRITE_THRESHOLD = 0.02
local DEFAULT_TRACTION_SLIP_TOLERANCE = 8
local DEFAULT_PERFORMANCE = {
	Acceleration = 40,
	Braking = 105,
	Deceleration = 35,
	EngineSpeedCorrection = 5,
	HasNitro = false,
	MaxSpeedForward = 70,
	MaxSpeedReverse = 30,
	MaxSpeedTorque = 5000,
	MinSpeedTorque = 25000,
	NitroAcceleration = 100,
	NitroMaxExtraSpeed = 35,
	NitroRechargeTime = 6,
	NitroTime = 3,
	NitroTorque = 15000,
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function enableScripts(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BaseScript") and not TEMPLATE_SCRIPTS[descendant.Name] then
			descendant.Disabled = false
		end
	end
end

local function cloneRigScripts(carRig: Model)
	local driverSeat = carRig:FindFirstChild("DriverSeat")
	assert(driverSeat, "WheeledVehicle: carRig.DriverSeat not found")

	local seatHandler = script.SeatEventHandler:Clone()
	seatHandler.Parent = driverSeat

	local scripts = script.Scripts:Clone()
	scripts.Parent = carRig
end

local function enableRigScripts(carRig: Model)
	local driverSeat = carRig:FindFirstChild("DriverSeat")
	if driverSeat then
		local seatHandler = driverSeat:FindFirstChild("SeatEventHandler")
		if seatHandler then
			seatHandler.Enabled = true
			enableScripts(seatHandler)
		end
	end

	local scripts = carRig:FindFirstChild("Scripts")
	if scripts then
		enableScripts(scripts)
	end
end

local function fillInConfigDefaults(config: { seatPosition: ("inside" | "ontop")?, [string]: any })
	if config.seatPosition ~= "inside" and config.seatPosition ~= "ontop" then
		vwarn(`seatPosition not set in config, defaulting to {DEFAULT_SEAT_POSITION}`)
		config.seatPosition = DEFAULT_SEAT_POSITION
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

local function sumEffectiveMass(model: Instance): number
	local total = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Massless then
			total += descendant:GetMass()
		end
	end
	return total
end

-- Private Methods

function FourWheel:_buildWrapper()
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
	local wrapper
	if originalParent and originalParent:IsA("Model") then
		-- Re-use the source model as the wrapper so it isn't left empty/orphaned post-rig.
		-- CAS patch: keep its name. Callers address the vehicle by the name they
		-- bound, and nothing in the framework reads this one.
		wrapper = originalParent
	else
		wrapper = Instance.new("Model")
		wrapper.Name = if originalParent then originalParent.Name else container.Name
		wrapper.Parent = originalParent
	end
	self.mainDump:Add(wrapper)

	container.Parent = wrapper
	schema.WheelFL.Parent = wrapper
	schema.WheelFR.Parent = wrapper
	schema.WheelRL.Parent = wrapper
	schema.WheelRR.Parent = wrapper
	for _, extraPart in self._params.ExtraParts do
		extraPart.Parent = wrapper
	end

	self.vehicleModel = wrapper
end

function FourWheel:_rigFunctional()
	local root = self.vehicleModel
	local container = self._container
	local schema = self._params.Schema
	local flWheel = schema.WheelFL
	local frWheel = schema.WheelFR
	local rlWheel = schema.WheelRL
	local rrWheel = schema.WheelRR

	local config = {
		seatPosition = self._params.SeatPosition,
		cameraHeightScale = self._params.Camera.HeightScale,
		cameraDistanceScale = self._params.Camera.DistanceScale,
		cameraAimHeightOffset = self._params.Camera.AimHeightOffset,
	}
	fillInConfigDefaults(config)

	assert(#GeometryUtils.getInstanceParts(container) > 0, "FourWheel: container has no BaseParts")

	container.PrimaryPart = nil

	recenterModelPivot(root)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Model") then
			recenterModelPivot(descendant)
		end
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local carCFrame = Heuristics.computeCarCFrame(flWheel, frWheel, rlWheel, rrWheel, container, self._params.AsymmetricAxles)

	local _, bodySize = GeometryUtils.measureExtentsInFrame(GeometryUtils.getInstanceParts(container), carCFrame)
	bodySize = Vector3.new(
		math.max(bodySize.X, 0.05),
		math.max(bodySize.Y, 0.05),
		math.max(bodySize.Z, 0.05)
	)
	local rootPart = Instance.new("Part")
	rootPart.Name = "RootPart"
	rootPart.Size = bodySize
	rootPart.CFrame = carCFrame
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Massless = true
	rootPart.Anchored = true
	rootPart.Parent = root
	root.PrimaryPart = rootPart

	Heuristics.prepareGeometry(root, flWheel, frWheel, rlWheel, rrWheel, container, carCFrame)

	local carRig = CarBuilderStarter:Clone()
	for _, descendant in carRig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	Heuristics.updateCarRig(carRig, flWheel, frWheel, rlWheel, rrWheel, container, carCFrame)
	Heuristics.attachGeometryToCarRig(carRig, flWheel, frWheel, rlWheel, rrWheel, container, self._params.ExtraParts)

	ConstructionHelpers.makeWeld(carRig:FindFirstChild("Chassis"), rootPart)

	cloneRigScripts(carRig)

	local vehicleSeat = carRig:FindFirstChild("DriverSeat")
	assert(vehicleSeat, "WheeledVehicle: carRig.DriverSeat not found")
	vehicleSeat.WeldConstraint.Enabled = false
	SeatHelpers.placeSeatOnModel(root, vehicleSeat, config.seatPosition)
	vehicleSeat.CanCollide = false
	vehicleSeat.BrickColor = BrickColor.new("Black")
	vehicleSeat.Transparency = 1
	vehicleSeat.Massless = true
	vehicleSeat.WeldConstraint.Enabled = true

	local vehicleModelRef = vehicleSeat:FindFirstChild("VehicleModelRef")
	vehicleModelRef.Value = root

	CreateConfiguration(root, config, "CarConfig")
	DamageController.new(root, 1)

	carRig.Parent = root

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	if RIG_DEBUG_MODE then
		for _, descendant in carRig:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = 0.5
			end
		end

		carRig.Chassis.Anchored = true
	end

	self.carRig = carRig
	self.vehicleSeat = vehicleSeat
end

function FourWheel:_applyPerformance()
	local engine = self.carRig:FindFirstChild("Engine")
	assert(engine, "WheeledVehicle: carRig.Engine not found")
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

	local tractionControl = performance.TractionControl
	local tractionEnabled = tractionControl ~= nil and tractionControl ~= false
	local tractionTolerance = if type(tractionControl) == "table" and tractionControl.SlipTolerance
		then tractionControl.SlipTolerance
		else DEFAULT_TRACTION_SLIP_TOLERANCE
	engine:SetAttribute("tractionControl", if tractionEnabled then 1 else 0)
	engine:SetAttribute("tractionSlipTolerance", tractionTolerance)

	self.carRig:SetAttribute(CarConstants.NITRO_USABLE_ATTRIBUTE, performance.HasNitro)

	if performance.TowAssist then
		self:_installTowAssist(engine, performance)
	end
end

function FourWheel:_installTowAssist(engine: Instance, performance: Performance)
	local baseMinTorque = performance.MinSpeedTorque
	local baseMaxTorque = performance.MaxSpeedTorque
	local towerMass = sumEffectiveMass(self.vehicleModel)
	local towAssist = performance.TowAssist
	local maxMultiplier = if type(towAssist) == "table" then towAssist.MaxMultiplier else nil
	local chassis = self.carRig:FindFirstChild("Chassis")
	local currentMinTorque = baseMinTorque
	local currentMaxTorque = baseMaxTorque

	local wheelRadius = 0
	local wheelsFolder = self.carRig:FindFirstChild("Wheels")
	if wheelsFolder then
		for _, mountName in { "WheelFL", "WheelFR", "WheelRL", "WheelRR" } do
			local mount = wheelsFolder:FindFirstChild(mountName)
			local wheelPart = if mount then mount:FindFirstChild("Wheel") else nil
			if wheelPart and wheelPart:IsA("BasePart") then
				wheelRadius = math.max(wheelRadius, wheelPart.Size.Y / 2)
			end
		end
	end

	local function computeDemandTorque(towedMass: number): number
		if not chassis or not chassis:IsA("BasePart") or wheelRadius <= 0 then
			return 0
		end

		local sinPitch = math.abs(chassis.CFrame.LookVector.Y)
		local cosPitch = math.sqrt(math.max(0, 1 - sinPitch * sinPitch))
		local requiredForce = (towerMass + towedMass)
			* workspace.Gravity
			* (sinPitch + TOW_ASSIST_ROLLING_RESISTANCE * cosPitch)
		return requiredForce * wheelRadius / 4 * TOW_ASSIST_HEADROOM
	end

	local function refresh()
		local towedMass = self.vehicleModel:GetAttribute(TOWED_MASS_ATTRIBUTE) or 0
		local factor = 1
		if towerMass > 0 then
			factor = 1 + towedMass / towerMass
		end

		local minTorque = baseMinTorque * factor
		local maxTorque = baseMaxTorque * factor
		if towedMass > 0 then
			local demandTorque = computeDemandTorque(towedMass)
			minTorque = math.max(minTorque, demandTorque)
			maxTorque = math.max(maxTorque, demandTorque)
		end

		if maxMultiplier then
			minTorque = math.min(minTorque, baseMinTorque * maxMultiplier)
			maxTorque = math.min(maxTorque, baseMaxTorque * maxMultiplier)
		end

		local minDelta = math.abs(minTorque - currentMinTorque)
		local maxDelta = math.abs(maxTorque - currentMaxTorque)
		if
			minDelta <= currentMinTorque * TOW_ASSIST_WRITE_THRESHOLD
			and maxDelta <= currentMaxTorque * TOW_ASSIST_WRITE_THRESHOLD
		then
			return
		end

		currentMinTorque = minTorque
		currentMaxTorque = maxTorque
		engine:SetAttribute("minSpeedTorque", minTorque)
		engine:SetAttribute("maxSpeedTorque", maxTorque)
	end

	local elapsed = 0
	self.mainDump:Connect(RunService.Heartbeat, function(deltaTime: number)
		local towedMass = self.vehicleModel:GetAttribute(TOWED_MASS_ATTRIBUTE) or 0
		if towedMass <= 0 then
			return
		end

		elapsed += deltaTime
		if elapsed < TOW_ASSIST_REFRESH_INTERVAL then
			return
		end

		elapsed = 0
		refresh()
	end)
	self.mainDump:Connect(self.vehicleModel:GetAttributeChangedSignal(TOWED_MASS_ATTRIBUTE), refresh)
	refresh()
end

function FourWheel:_rigVehicle()
	self:_buildWrapper()
	self:_rigFunctional()
	self:_applyPerformance()
	enableRigScripts(self.carRig)
end

-- Public Methods

function FourWheel:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self.mainDump:Destroy()
	for k in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function FourWheel.new(container: Model | BasePart, params: SetupParams): FourWheelInstance
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

	local self = setmetatable({}, FourWheel)

	self.mainDump = Dumpster.new()
	self.vehicleModel = nil
	self.carRig = nil
	self.vehicleSeat = nil

	self._container = container
	self._params = {
		Schema = params.Schema,
		Performance = mergePerformanceDefaults(params.Performance),
		SeatPosition = params.SeatPosition or DEFAULT_SEAT_POSITION,
		ExtraParts = params.ExtraParts or {},
		AsymmetricAxles = params.AsymmetricAxles or false,
		Camera = {
			HeightScale = if params.Camera and params.Camera.HeightScale then params.Camera.HeightScale else 1,
			DistanceScale = if params.Camera and params.Camera.DistanceScale then params.Camera.DistanceScale else 1,
			AimHeightOffset = if params.Camera and params.Camera.AimHeightOffset then params.Camera.AimHeightOffset else 0,
		},
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
	TowAssist: (boolean | { MaxMultiplier: number? })?,
	TractionControl: (boolean | { SlipTolerance: number? })?,
}
export type CameraOverride = {
	HeightScale: number?,
	DistanceScale: number?,
	AimHeightOffset: number?,
}
export type SetupParams = {
	Schema: Schema,
	Performance: Performance?,
	SeatPosition: ("inside" | "ontop")?,
	ExtraParts: { PVInstance }?,
	AsymmetricAxles: boolean?,
	Camera: CameraOverride?,
}
export type FourWheelInstance = {
	vehicleModel: Model,
	carRig: Model,
	vehicleSeat: Instance?,
	mainDump: any,
	Destroy: (self: FourWheelInstance) -> (),
}

-- Return

return FourWheel

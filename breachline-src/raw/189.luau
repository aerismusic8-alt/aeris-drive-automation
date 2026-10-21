--[[
	File: Rotor.luau
]]--

-- Root

local Rotor = {}
Rotor.__index = Rotor

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local StripCapabilityTag = require(FourD.Common.stripCapabilityTag)
local recenterModelPivot = require(FourD.Common.recenterModelPivot)

local AirVehicleRoot = script.Parent.Parent
local NetworkOwnership = require(AirVehicleRoot.Common.NetworkOwnership)
local PruneFiltered = require(AirVehicleRoot.Common.PruneFiltered)
local Heuristics = require(AirVehicleRoot.Common.Heuristics)

local BuildHull = require(AirVehicleRoot.Common.BuildHull)
local BuildPropellers = require(script.Construction.BuildPropellers)
local BuildPhysics = require(script.Construction.BuildPhysics)
local BuildPrompt = require(AirVehicleRoot.Common.BuildPrompt)
local BuildController = require(AirVehicleRoot.Common.BuildController)

-- Constants

local VERBOSE_LOGGING = false
local GUNNER_SEAT_REF_NAME = "AirVehicle_GunnerSeatRef"
local MAIN_ROTOR_MOTOR_PREFIX = "MainRotorMotor"
local TAIL_ROTOR_MOTOR_PREFIX = "TailRotorMotor"
local MAIN_ROTOR_KIND = "Main"
local TAIL_ROTOR_KIND = "Tail"
local RIDER_VISIBLE_ATTRIBUTE = "RiderVisible"
local RIDER_PLATFORM_STAND_ATTRIBUTE = "RiderPlatformStand"
local DEFAULT_PERFORMANCE: Performance = {
	MaxSpeedLateral = 150,
	MaxSpeedStrafe = 80,
	Acceleration = 20,
	MaxCollective = 20,
	CollectiveRate = 15,
	YawRate = 40,
	CameraDistance = 25,
	CameraHeight = 6,
	BlurDiskOpacity = 0.7,
	PitchFollow = false,
	PitchRate = 55,
	MaxPitchFollowDegrees = 65,
	MaxVisualPitchDegrees = 25,
	MaxVisualRollDegrees = 25,
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

-- Private Methods

function Rotor:_setupRotor()
	PruneFiltered(self._bodyModel, self._params.Schema.Preserve)

	for _, child in self._bodyModel:GetChildren() do
		if child:IsA("Model") then
			recenterModelPivot(child, true)
		end
	end

	local rigModel = Instance.new("Model")
	rigModel.Name = `AirVehicleRotor_{self._bodyModel.Name}`
	rigModel.Parent = self._bodyModel.Parent

	self.rotorModel = rigModel
	self._mainDump:Add(rigModel)

	local schema = self._params.Schema
	-- MainRotors sit on top of and centered over the fuselage, so they carry no
	-- reliable fore/aft signal: their tiny residual horizontal offset (whatever
	-- survives flattenY) tends to point at the tail and rigs the craft backward.
	-- Pass only genuine fore/aft cues; TailRotors, when present, are a true aft
	-- feature. Absent any cue, detectForwardAxis falls back to the mass-bulk
	-- disambiguated long axis (cabin forward, tail boom aft).
	local forwardAxis = schema.ForwardAxis or Heuristics.detectForwardAxis(
		schema.Body,
		schema.ForwardHint,
		nil,
		schema.TailRotors,
		"[RotorHeuristics]"
	)

	local hull = BuildHull.rig(rigModel, self._bodyModel, schema.Body, forwardAxis)

	local blurDiskOpacity = self._params.Performance.BlurDiskOpacity
	BuildPropellers.rig(rigModel, hull.Root, schema.MainRotors, MAIN_ROTOR_MOTOR_PREFIX, MAIN_ROTOR_KIND, blurDiskOpacity)
	BuildPropellers.rig(rigModel, hull.Root, schema.TailRotors, TAIL_ROTOR_MOTOR_PREFIX, TAIL_ROTOR_KIND, blurDiskOpacity)

	BuildPhysics.rig(hull.Root)

	BuildPrompt.rig(hull.Root, hull.BodySize, self._params.ProximityPromptText, self._params.ProximityPromptTitle or "Helicopter")

	local performance = self._params.Performance
	BuildController.rig({
		WrapperModel = rigModel,
		Root = hull.Root,
		Attributes = {
			MaxSpeedLateral = performance.MaxSpeedLateral,
			MaxSpeedStrafe = performance.MaxSpeedStrafe,
			Acceleration = performance.Acceleration,
			MaxCollective = performance.MaxCollective,
			CollectiveRate = performance.CollectiveRate,
			YawRate = performance.YawRate,
			CameraDistance = performance.CameraDistance,
			CameraHeight = performance.CameraHeight,
			PitchFollow = performance.PitchFollow,
			PitchRate = performance.PitchRate,
			MaxPitchFollowDegrees = performance.MaxPitchFollowDegrees,
			MaxVisualPitchDegrees = performance.MaxVisualPitchDegrees,
			MaxVisualRollDegrees = performance.MaxVisualRollDegrees,
		},
		ScriptsFolder = script:WaitForChild("Scripts"),
	})

	if self._params.RiderVisible ~= nil then
		hull.Root:SetAttribute(RIDER_VISIBLE_ATTRIBUTE, self._params.RiderVisible)
	end

	if self._params.RiderPlatformStand ~= nil then
		hull.Root:SetAttribute(RIDER_PLATFORM_STAND_ATTRIBUTE, self._params.RiderPlatformStand)
	end

	BuildController.createSwapRemote(rigModel)

	for _, child in self._bodyModel:GetChildren() do
		child.Parent = rigModel
	end

	StripCapabilityTag(rigModel)
	NetworkOwnership.setOwner(rigModel, nil)
end

function Rotor:SetGunnerSeat(seat: Seat?)
	if not self._gunnerSeatRef then
		local ref = Instance.new("ObjectValue")
		ref.Name = GUNNER_SEAT_REF_NAME
		ref.Parent = self.rotorModel
		self._mainDump:Add(ref)
		self._gunnerSeatRef = ref
	end

	self._gunnerSeatRef.Value = seat
end

-- Public Methods

function Rotor:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self._mainDump:Destroy()
	for k in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function Rotor.new(bodyModel: Model, params: SetupParams): RotorInstance
	assert(bodyModel ~= nil, "must supply bodyModel")
	assert(bodyModel:IsA("Model"), "bodyModel must be a Model")
	assert(params ~= nil, "must supply params")
	assert(params.Schema ~= nil, "must supply params.Schema")
	assert(params.Schema.Body ~= nil, "must supply params.Schema.Body")
	assert(params.Schema.Body:IsA("BasePart") or params.Schema.Body:IsA("Model"),
		"params.Schema.Body must be a BasePart or Model")

	local self = setmetatable({}, Rotor)

	self._mainDump = Dumpster.new()

	self._bodyModel = bodyModel
	self.rotorModel = nil
	self._gunnerSeatRef = nil

	local mergedPerformance: Performance = table.clone(DEFAULT_PERFORMANCE)

	if params.Performance then
		for k, v in params.Performance do
			if v ~= nil then
				mergedPerformance[k] = v
			end
		end
	end

	self._params = {
		Schema = params.Schema,
		Performance = mergedPerformance,
		ProximityPromptText = params.ProximityPromptText,
		ProximityPromptTitle = params.ProximityPromptTitle,
		RiderVisible = params.RiderVisible,
		RiderPlatformStand = params.RiderPlatformStand,
		RiderPlacementOffset = params.RiderPlacementOffset,
	}

	self:_setupRotor()
	vprint(`Completed setup on {bodyModel.Name} with params:`, self._params)
	return self
end

-- Types

export type Schema = {
	Body: PVInstance,
	MainRotors: { PVInstance }?,
	TailRotors: { PVInstance }?,
	ForwardHint: { PVInstance }?,
	ForwardAxis: Vector3?,
	Preserve: { Instance }?,
}

export type Performance = {
	MaxSpeedLateral: number?,
	MaxSpeedStrafe: number?,
	Acceleration: number?,
	MaxCollective: number?,
	CollectiveRate: number?,
	YawRate: number?,
	CameraDistance: number?,
	CameraHeight: number?,
	BlurDiskOpacity: number?,
	PitchFollow: boolean?,
	PitchRate: number?,
	MaxPitchFollowDegrees: number?,
	MaxVisualPitchDegrees: number?,
	MaxVisualRollDegrees: number?,
}

export type SetupParams = {
	Schema: Schema,
	Performance: Performance?,
	ProximityPromptText: string?,
	ProximityPromptTitle: string?,
	RiderVisible: boolean?,
	RiderPlatformStand: boolean?,
	RiderPlacementOffset: ((root: BasePart, hipHeight: number) -> CFrame)?,
}

export type RotorInstance = {
	rotorModel: Model,
	SetGunnerSeat: (self: RotorInstance, seat: Seat?) -> (),
	Destroy: (self: RotorInstance) -> (),
}

-- Return

return Rotor

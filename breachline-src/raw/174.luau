--[[
	File: Plane.luau
]]--

-- Root

local Plane = {}
Plane.__index = Plane

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local StripCapabilityTag = require(FourD.Common.stripCapabilityTag)

local AirVehicleRoot = script.Parent.Parent
local NetworkOwnership = require(AirVehicleRoot.Common.NetworkOwnership)
local PruneFiltered = require(AirVehicleRoot.Common.PruneFiltered)
local Heuristics = require(AirVehicleRoot.Common.Heuristics)

local BuildHull = require(AirVehicleRoot.Common.BuildHull)
local BuildPropellers = require(script.Construction.BuildPropellers)
local BuildThrusters = require(script.Construction.BuildThrusters)
local BuildPhysics = require(script.Construction.BuildPhysics)
local BuildPrompt = require(AirVehicleRoot.Common.BuildPrompt)
local BuildController = require(AirVehicleRoot.Common.BuildController)

local PlaneConstants = require(script.Scripts.Constants)

-- Constants

local VERBOSE_LOGGING = false
local PITCH_CLAMP_DEGREES = 85
local GUNNER_SEAT_REF_NAME = "AirVehicle_GunnerSeatRef"
local VFX_ASSET_PATH = { "Assets", "VFX", "AirVehicle_Plane_JetThruster" }
local DEFAULT_PERFORMANCE: Performance = {
	MaxSpeed = 100,
	StallSpeed = 30,
	Acceleration = 25,
	PitchRate = 20,
	TurnRate = 40,
	MaxBankDegrees = PlaneConstants.MAX_BANK_DEGREES,
	CameraDistance = 25,
	CameraHeight = 6,
	BlurDiskOpacity = 0.7,
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function resolveVfxTemplate(): Model?
	local current: Instance = ReplicatedStorage
	for _, name in VFX_ASSET_PATH do
		local nextChild = current:FindFirstChild(name)
		if not nextChild then return nil end
		current = nextChild
	end

	if current:IsA("Model") then
		return current
	end

	return nil
end

-- Private Methods

local function applyThrusterColor(template: Model, color: Color3): Model
	local clone = template:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			if string.lower(descendant.Name) == "inner" then
				descendant.Color = color:Lerp(Color3.new(1, 1, 1), 0.5)
			else
				descendant.Color = color
			end
		end
	end

	return clone
end

function Plane:_setupPlane()
	PruneFiltered(self._bodyModel)

	local rigModel = Instance.new("Model")
	rigModel.Name = `AirVehiclePlane_{self._bodyModel.Name}`
	rigModel.Parent = self._bodyModel.Parent

	self.planeModel = rigModel
	self._mainDump:Add(rigModel)

	local schema = self._params.Schema
	local forwardAxis = Heuristics.detectForwardAxis(
		schema.Body,
		schema.ForwardHint,
		schema.Propellers,
		schema.Thrusters,
		"[PlaneHeuristics]"
	)

	local hull = BuildHull.rig(rigModel, self._bodyModel, schema.Body, forwardAxis)

	BuildPropellers.rig(rigModel, hull.Root, schema.Propellers, self._params.Performance.BlurDiskOpacity)

	if schema.Thrusters then
		local vfxTemplate = resolveVfxTemplate()
		if not vfxTemplate then
			warn(`[{script.Name}] missing VFX template at ReplicatedStorage.Assets.VFX.AirVehicle_Plane_JetThruster; skipping jet thruster VFX`)
		else
			local thrusterColor = self._params.ThrusterColor
			local coloredTemplate = if thrusterColor then applyThrusterColor(vfxTemplate, thrusterColor) else vfxTemplate
			for _, thrusterEntry in schema.Thrusters do
				BuildThrusters.rig(rigModel, thrusterEntry, forwardAxis, coloredTemplate)
			end

			if coloredTemplate ~= vfxTemplate then coloredTemplate:Destroy() end
		end
	end

	BuildPhysics.rig(hull.Root)

	BuildPrompt.rig(hull.Root, hull.BodySize, self._params.ProximityPromptText, "Plane")

	local performance = self._params.Performance
	BuildController.rig({
		WrapperModel = rigModel,
		Root = hull.Root,
		Attributes = {
			MaxSpeed = performance.MaxSpeed,
			StallSpeed = performance.StallSpeed,
			Acceleration = performance.Acceleration,
			PitchRate = performance.PitchRate,
			TurnRate = performance.TurnRate,
			MaxBankDegrees = performance.MaxBankDegrees,
			CameraDistance = performance.CameraDistance,
			CameraHeight = performance.CameraHeight,
			PitchClampDegrees = PITCH_CLAMP_DEGREES,
		},
		ScriptsFolder = script:WaitForChild("Scripts"),
	})

	BuildController.createSwapRemote(rigModel)

	for _, child in self._bodyModel:GetChildren() do
		child.Parent = rigModel
	end

	StripCapabilityTag(rigModel)
	NetworkOwnership.setOwner(rigModel, nil)
end

function Plane:SetGunnerSeat(seat: Seat?)
	if not self._gunnerSeatRef then
		local ref = Instance.new("ObjectValue")
		ref.Name = GUNNER_SEAT_REF_NAME
		ref.Parent = self.planeModel
		self._mainDump:Add(ref)
		self._gunnerSeatRef = ref
	end

	self._gunnerSeatRef.Value = seat
end

-- Public Methods

function Plane:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self._mainDump:Destroy()
	for k in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function Plane.new(bodyModel: Model, params: SetupParams): PlaneInstance
	assert(bodyModel ~= nil, "must supply bodyModel")
	assert(bodyModel:IsA("Model"), "bodyModel must be a Model")
	assert(params ~= nil, "must supply params")
	assert(params.Schema ~= nil, "must supply params.Schema")
	assert(params.Schema.Body ~= nil, "must supply params.Schema.Body")
	assert(params.Schema.Body:IsA("BasePart") or params.Schema.Body:IsA("Model"),
		"params.Schema.Body must be a BasePart or Model")

	local self = setmetatable({}, Plane)

	self._mainDump = Dumpster.new()

	self._bodyModel = bodyModel
	self.planeModel = nil
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
		ThrusterColor = params.ThrusterColor,
	}

	self:_setupPlane()
	vprint(`Completed setup on {bodyModel.Name} with params:`, self._params)
	return self
end

-- Types

export type Schema = {
	Body: PVInstance,
	LeftLandingGear: PVInstance?,
	RightLandingGear: PVInstance?,
	CenterLandingGear: PVInstance?,
	Propellers: { PVInstance }?,
	Thrusters: { PVInstance }?,
	ForwardHint: { PVInstance }?,
}

export type Performance = {
	MaxSpeed: number?,
	StallSpeed: number?,
	Acceleration: number?,
	PitchRate: number?,
	TurnRate: number?,
	MaxBankDegrees: number?,
	CameraDistance: number?,
	CameraHeight: number?,
	BlurDiskOpacity: number?,
}

export type SetupParams = {
	Schema: Schema,
	Performance: Performance?,
	ProximityPromptText: string?,
	ThrusterColor: Color3?,
}

export type PlaneInstance = {
	planeModel: Model,
	SetGunnerSeat: (self: PlaneInstance, seat: Seat?) -> (),
	Destroy: (self: PlaneInstance) -> (),
}

-- Return

return Plane

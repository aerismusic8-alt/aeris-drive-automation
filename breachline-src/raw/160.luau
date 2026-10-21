--[[
	File: Jetpack.luau
]]--

-- Root

local Jetpack = {}
Jetpack.__index = Jetpack

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local StripCapabilityTag = require(FourD.Common.stripCapabilityTag)
local GeometryUtils = require(FourD.Common.GeometryUtils)

local AirVehicleRoot = script.Parent.Parent
local NetworkOwnership = require(AirVehicleRoot.Common.NetworkOwnership)
local PruneFiltered = require(AirVehicleRoot.Common.PruneFiltered)
local Heuristics = require(AirVehicleRoot.Common.Heuristics)

local BuildHull = require(AirVehicleRoot.Common.BuildHull)
local BuildPhysics = require(script.Construction.BuildPhysics)
local BuildThrusters = require(script.Construction.BuildThrusters)
local BuildPrompt = require(AirVehicleRoot.Common.BuildPrompt)
local BuildController = require(AirVehicleRoot.Common.BuildController)

-- Constants

local VERBOSE_LOGGING = false
local VFX_ASSET_PATH = { "Assets", "VFX", "JetFlame_Purple" }
local BACK_OFFSET_PADDING = 0.1
local BACK_OFFSET_ATTRIBUTE = "BackOffset"
local PROMPT_DISTANCE_MULT = 3
local DEFAULT_PERFORMANCE: Performance = {
	MaxSpeed = 50,
	Acceleration = 15,
	AltitudeChangeRate = 10,
	LookRate = 40,
	CameraDistance = 18,
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

function Jetpack:_setupJetpack()
	PruneFiltered(self._bodyModel)

	local rigModel = Instance.new("Model")
	rigModel.Name = `AirVehicleJetpack_{self._bodyModel.Name}`
	rigModel.Parent = self._bodyModel.Parent

	self.jetpackModel = rigModel
	self._mainDump:Add(rigModel)

	local schema = self._params.Schema
	local hullForward = schema.ForwardAxis or -Heuristics.detectForwardAxis(
		schema.Pack,
		schema.ForwardHint,
		nil,
		nil,
		"[JetpackHeuristics]"
	)

	local hull = BuildHull.rig(rigModel, self._bodyModel, schema.Pack, hullForward)

	local vfxTemplate = resolveVfxTemplate()
	if vfxTemplate then
		BuildThrusters.rig(rigModel, hull.Root, schema.Pack, schema.Thruster, vfxTemplate)
	else
		warn(`[{script.Name}] missing VFX template at ReplicatedStorage.Assets.VFX.JetFlame_Purple; skipping thruster decoration`)
	end

	BuildPhysics.rig(hull.Root)

	local packParts = GeometryUtils.getInstanceParts(schema.Pack)
	local _, packExtents = GeometryUtils.measureExtentsInFrame(packParts, hull.Root.CFrame)
	hull.Root:SetAttribute(BACK_OFFSET_ATTRIBUTE, packExtents.Z * 0.5 + BACK_OFFSET_PADDING)

	BuildPrompt.rig(hull.Root, hull.BodySize, self._params.ProximityPromptText, "Jetpack", PROMPT_DISTANCE_MULT)

	local performance = self._params.Performance
	BuildController.rig({
		WrapperModel = rigModel,
		Root = hull.Root,
		Attributes = {
			MaxSpeed = performance.MaxSpeed,
			Acceleration = performance.Acceleration,
			AltitudeChangeRate = performance.AltitudeChangeRate,
			LookRate = performance.LookRate,
			CameraDistance = performance.CameraDistance,
		},
		ScriptsFolder = script:WaitForChild("Scripts"),
	})

	for _, child in self._bodyModel:GetChildren() do
		child.Parent = rigModel
	end

	StripCapabilityTag(rigModel)
	NetworkOwnership.setOwner(rigModel, nil)
end

-- Public Methods

function Jetpack:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self._mainDump:Destroy()
	for k in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function Jetpack.new(bodyModel: Model, params: SetupParams): JetpackInstance
	assert(bodyModel ~= nil, "must supply bodyModel")
	assert(bodyModel:IsA("Model"), "bodyModel must be a Model")
	assert(params ~= nil, "must supply params")
	assert(params.Schema ~= nil, "must supply params.Schema")
	assert(params.Schema.Pack ~= nil, "must supply params.Schema.Pack")
	assert(params.Schema.Pack:IsA("BasePart") or params.Schema.Pack:IsA("Model"),
		"params.Schema.Pack must be a BasePart or Model")
	assert(params.Schema.Thruster ~= nil, "must supply params.Schema.Thruster")
	assert(params.Schema.Thruster:IsA("BasePart") or params.Schema.Thruster:IsA("Model"),
		"params.Schema.Thruster must be a BasePart or Model")

	local self = setmetatable({}, Jetpack)

	self._mainDump = Dumpster.new()

	self._bodyModel = bodyModel
	self.jetpackModel = nil

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
	}

	self:_setupJetpack()
	vprint(`Completed setup on {bodyModel.Name} with params:`, self._params)
	return self
end

-- Types

export type Schema = {
	Pack: PVInstance,
	Thruster: PVInstance,
	ForwardHint: { PVInstance }?,
	ForwardAxis: Vector3?,
}

export type Performance = {
	MaxSpeed: number?,
	Acceleration: number?,
	AltitudeChangeRate: number?,
	LookRate: number?,
	CameraDistance: number?,
}

export type SetupParams = {
	Schema: Schema,
	Performance: Performance?,
	ProximityPromptText: string?,
}

export type JetpackInstance = {
	jetpackModel: Model,
	Destroy: (self: JetpackInstance) -> (),
}

-- Return

return Jetpack

--[[
	File: Pistol.luau
]]--

-- Root

local Pistol = {}
Pistol.__index = Pistol

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local BuildHandle = require(Firearm2.Common.BuildHandle)
local Constants = require(Firearm2.Common.Constants)
local Dumpster = require(FourD.Libs.Dumpster)
local Heuristics = require(script.Heuristics)

-- Constants

local VERBOSE_LOGGING = Constants.VERBOSE_LOGGING
local REQUIRED_SCHEMA_KEYS = { "Grip", "Barrel" }
local OPTIONAL_SCHEMA_KEYS = { "Frame", "Slide", "Magazine", "Trigger" }
local DEFAULT_HOLD_CFRAME = CFrame.new(0.5, 0, -2)

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function validateSchema(schema: { [string]: any })
	for _, key in REQUIRED_SCHEMA_KEYS do
		local value = schema[key]
		assert(value ~= nil, `Pistol Schema: required key "{key}" missing`)
		assert(typeof(value) == "Instance", `Pistol Schema: "{key}" must be an Instance`)
		assert(
			value:IsA("BasePart") or value:IsA("Model"),
			`Pistol Schema: "{key}" must be a BasePart or Model`
		)
	end

	for _, key in OPTIONAL_SCHEMA_KEYS do
		local value = schema[key]
		if value == nil then continue end

		if typeof(value) ~= "Instance" then
			vwarn(`Pistol Schema: optional key "{key}" is not an Instance; ignoring`)
			schema[key] = nil
		end
	end
end

local function mergeParams(input: { [string]: any }): { [string]: any }
	local merged: { [string]: any } = {}
	for key, value in Constants.DEFAULT_PARAMS do
		merged[key] = value
	end

	merged.HoldCFrame = DEFAULT_HOLD_CFRAME

	for key, value in input do
		if key == "Schema" then continue end
		if value == nil then continue end
		merged[key] = value
	end

	return merged
end

-- Public Methods

function Pistol:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self._mainDump:Destroy()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function Pistol.new(bodyModel: Model, params: { Schema: { [string]: any }, [string]: any }): any
	assert(bodyModel ~= nil, "Pistol.new: must supply bodyModel")
	assert(bodyModel:IsA("Model"), "Pistol.new: bodyModel must be a Model")
	assert(params ~= nil, "Pistol.new: must supply params")
	assert(params.Schema ~= nil, "Pistol.new: params.Schema is required")

	validateSchema(params.Schema)

	local self = setmetatable({}, Pistol)
	self._mainDump = Dumpster.new()
	self._params = mergeParams(params)

	local heuristic = Heuristics.compute(bodyModel, params.Schema)
	local tool = BuildHandle(
		heuristic.OrientedModel,
		heuristic.ForwardDirection,
		self._params
	)

	self._mainDump:Add(tool)
	self.Tool = tool

	vprint(`Built Pistol "{bodyModel.Name}" with params:`, self._params)
	return self
end

-- Return

return Pistol
M
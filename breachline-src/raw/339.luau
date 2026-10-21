--[[
Sailboat4 Capability - Drivable sailboat with buoyancy, thrust, and auxiliary propeller spin

Composes: WaterVehicle Architect
Schema: Sailboat4 (body, sail, propeller, rudder)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WaterVehicle2Architect = require(FourD.Architects.WaterVehicle2)

local function MakeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}

	local body = root:FindFirstChild("body")
	local sail = root:FindFirstChild("sail")
	local propeller = root:FindFirstChild("propeller")
	local rudder = root:FindFirstChild("rudder")

	if not body then error("Missing 'body' child in sailboat model") end
	if not sail then error("Missing 'sail' child in sailboat model") end
	if not propeller then error("Missing 'propeller' child in sailboat model") end
	if not rudder then error("Missing 'rudder' child in sailboat model") end

	WaterVehicle2Architect.build(root, {
		Acceleration = config.acceleration,
		Draft = 0.5,
		MaxForwardSpeed = config.maxForwardSpeed,
		MaxReverseSpeed = config.maxReverseSpeed,
		MaxTurnSpeed = config.maxTurnSpeed,
		Rotors = { propeller },
		Rudder = rudder,
		TurnAcceleration = config.turnAcceleration,
	})

	return root.Parent
end

local Sailboat4 = CapabilityBase.createChild()

function Sailboat4:getCapabilityDocumentation()
	return [[
The Sailboat4Capability creates a functional sailboat that floats on water. The player sits in a driver seat and controls the boat with WASD: W/S for throttle forward and reverse, A/D for steering. The auxiliary propeller spins visually when throttle is applied. Buoyancy is simulated with a spring-damper system that keeps the hull at the water surface. The boat features a mainsail and jib sail as decorative rigging.
]]
end

function Sailboat4:getModelSpecs()
	return {
		{
			name = "sailboat",
			modelSchema = "Sailboat4",
			description = "a sailboat with a hull body, mainsail and jib sail rigging, auxiliary propeller, and rudder",
		},
	}
end

function Sailboat4:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxForwardSpeed", {
			type = "number",
			default = 40,
			description = "Maximum forward speed in studs/sec",
		})
		:addOptionalArgument("maxReverseSpeed", {
			type = "number",
			default = 8,
			description = "Maximum reverse speed in studs/sec",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 4,
			description = "Surge acceleration rate in studs/sec^2",
		})
		:addOptionalArgument("maxTurnSpeed", {
			type = "number",
			default = 35,
			description = "Maximum yaw rate in degrees/sec",
		})
		:addOptionalArgument("turnAcceleration", {
			type = "number",
			default = 20,
			description = "Yaw acceleration rate in degrees/sec^2",
		})
		:build()
end

function Sailboat4:getCapabilitySelectionExamples()
	return {
		{
			user = "a sailboat",
			assistant = {
				capability_reasoning = "The user wants a sailboat, which is a wind-powered water vessel with mast, sails, and a rudder. Sailboat4Capability creates a functional sailboat with buoyancy, thrust, and steering.",
				capability_selection = "Sailboat4Capability",
				overall_size_reasoning = "A typical sailboat has a narrow hull and tall mast. A small sailboat is around 2m wide, 4m tall (including mast), and 6m long.",
				overall_size_selection = { x = 2.0, y = 4.0, z = 6.0 },
			},
		},
		{
			user = "a yacht",
			assistant = {
				capability_reasoning = "A yacht is a sail-powered watercraft 
--[[
SimpleMotorcycle7 Capability - Drivable two-wheeled motorcycle

Composes: WheeledVehicle TwoWheel architect
Schema: SimpleMotorcycle7 (frame, seat, handlebars, front fork, rear swingarm, front wheel, rear wheel)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)

local SimpleMotorcycle7 = CapabilityBase.createChild()

function SimpleMotorcycle7:getCapabilityDocumentation()
	return [[
The SimpleMotorcycle7Capability creates a functional two-wheeled motorcycle from existing parts. The bike has a steerable front wheel (rake-angled fork hinge), motorized rear wheel, and an upright-balancing chassis. Anything that is not a two-wheeled vehicle should NOT use this capability.
]]
end

function SimpleMotorcycle7:getModelSpecs()
	return {
		{
			name = "motorcycle",
			modelSchema = "SimpleMotorcycle7",
			description = "a driveable two-wheeled motorcycle with frame, seat, handlebars, front fork, rear swingarm, front wheel, and rear wheel",
		},
	}
end

function SimpleMotorcycle7:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function SimpleMotorcycle7:getCapabilitySelectionExamples()
	return {
		{
			user = "a motorcycle",
			assistant = {
				capability_reasoning = "The user has requested a 'motorcycle', a two-wheeled drivable vehicle. SimpleMotorcycle7Capability handles two-wheeled vehicles via the WheeledVehicle TwoWheel architect.",
				capability_selection = "SimpleMotorcycle7Capability",
				overall_size_reasoning = "A typical motorcycle is roughly 2.0m long, 0.8m wide, and 1.1m tall. Sized for a single Roblox avatar to straddle.",
				overall_size_selection = { x = 0.8, y = 1.1, z = 2.0 },
			},
		},
	}
end

function SimpleMotorcycle7:getConfigureCapabilityExamples()
	return {
		{
			user = "a motorcycle",
			assistant = {
				capability_parameters_reasoning = "No configurable parameters; the motorcycle uses default behavior.",
				capability_parameters_selection = {},
			},
		},
	}
end

function SimpleMotorcycle7:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("SimpleMotorcycle7Capability configuration error: " .. errorMsg)
	end

	local motorcycle = generatedModels["motorcycle"]
	if not motorcycle then
		error("Could not find 'motorcycle' model in generatedModels")
	end

	local frontWheel = motorcycle:FindFirstChild("front wheel")
	local rearWheel = motorcycle:FindFirstChild("rear wheel")

	if not frontWheel then error("Could not find 'front wheel'") end
	if not rearWheel then error("Could not find 'rear wheel'") end

	local vehicle = WheeledVehicleArchitect.build2Wheel(motorcycle, {
		Schema = {
			WheelF = frontWheel,
			WheelR = rearWheel,
		},
		Performance = {
			HasNitro = true,
		},
	})

	return vehicle.vehicleModel
end

return SimpleMotorcycle7

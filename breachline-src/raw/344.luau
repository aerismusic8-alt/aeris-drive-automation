--[[
Bike10 Capability - Drivable two-wheeled bicycle

Composes: WheeledVehicle TwoWheel architect
Schema: Bike10 (frame, seat, handlebars, front fork, front wheel, rear wheel, left pedal, left pedal arm, right pedal, right pedal arm)

Pedals and pedal arms are not animated yet; they are welded to the rig as cosmetic body parts.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)

local Bike10 = CapabilityBase.createChild()

function Bike10:getCapabilityDocumentation()
	return [[
The Bike10Capability creates a functional two-wheeled bicycle from existing parts. The bike has a steerable front wheel (rake-angled fork hinge), motorized rear wheel, and an upright-balancing chassis. Pedals and pedal arms are cosmetic and welded to the frame (not animated). Anything that is not a two-wheeled vehicle should NOT use this capability.
]]
end

function Bike10:getModelSpecs()
	return {
		{
			name = "bike",
			modelSchema = "Bike10",
			description = "a driveable two-wheeled bicycle with frame, seat, handlebars, front fork, front wheel, rear wheel, and cosmetic pedals with pedal arms",
		},
	}
end

function Bike10:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Bike10:getCapabilitySelectionExamples()
	return {
		{
			user = "a bicycle",
			assistant = {
				capability_reasoning = "The user has requested a 'bicycle', a two-wheeled drivable vehicle. Bike10Capability handles two-wheeled vehicles via the WheeledVehicle TwoWheel architect.",
				capability_selection = "Bike10Capability",
				overall_size_reasoning = "A typical bicycle is roughly 1.7m long, 0.5m wide, and 1.0m tall. Sized for a single Roblox avatar to straddle.",
				overall_size_selection = { x = 0.5, y = 1.0, z = 1.7 },
			},
		},
	}
end

function Bike10:getConfigureCapabilityExamples()
	return {
		{
			user = "a bicycle",
			assistant = {
				capability_parameters_reasoning = "No configurable parameters; the bicycle uses default behavior.",
				capability_parameters_selection = {},
			},
		},
	}
end

function Bike10:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Bike10Capability configuration error: " .. errorMsg)
	end

	local bike = generatedModels["bike"]
	if not bike then
		error("Could not find 'bike' model in generatedModels")
	end

	local frontWheel = bike:FindFirstChild("front wheel")
	local rearWheel = bike:FindFirstChild("rear wheel")

	if not frontWheel then error("Could not find 'front wheel'") end
	if not rearWheel then error("Could not find 'rear wheel'") end

	local vehicle = WheeledVehicleArchitect.build2Wheel(bike, {
		Schema = {
			WheelF = frontWheel,
			WheelR = rearWheel,
		},
		Performance = {
			MuteEngineSound = true,
		},
	})

	return vehicle.vehicleModel
end

return Bike10

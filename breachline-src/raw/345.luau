--[[
Bus5 Capability - Drivable bus vehicle

Composes: Drivable behavior
Schema: Bus5 (body + 4 wheels)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)

local Bus5 = CapabilityBase.createChild()

function Bus5:getCapabilityDocumentation()
	return [[
The Bus5Capability creates a functional bus from parts with four wheels and a body.
Use for any large passenger vehicle like a city bus or charter bus.
]]
end

function Bus5:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "Bus5",
			description = "a large passenger bus with four wheels and a body",
		},
	}
end

function Bus5:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "inside",
			description = "Position of the driver seat relative to the bus body",
		})
		:build()
end

function Bus5:getCapabilitySelectionExamples()
	return {
		{
			user = "a city bus",
			assistant = {
				capability_reasoning = 'A city bus is a large passenger vehicle. Bus5Capability handles buses.',
				capability_selection = "Bus5Capability",
				overall_size_reasoning = "A city bus is about 12m long, 2.5m wide, 3m tall.",
				overall_size_selection = { x = 2.5, y = 3, z = 12 },
			},
		},
	}
end

function Bus5:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("Bus5Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	local fl = carModel:FindFirstChild("left front wheel")
	local fr = carModel:FindFirstChild("right front wheel")
	local rl = carModel:FindFirstChild("left rear wheel")
	local rr = carModel:FindFirstChild("right rear wheel")
	local body = carModel:FindFirstChild("body")

	if not fl then error("Missing 'left front wheel'") end
	if not fr then error("Missing 'right front wheel'") end
	if not rl then error("Missing 'left rear wheel'") end
	if not rr then error("Missing 'right rear wheel'") end
	if not body then error("Missing 'body'") end

	local vehicle = WheeledVehicleArchitect.build4Wheel(body, {
		Schema = {
			WheelFL = fl,
			WheelFR = fr,
			WheelRL = rl,
			WheelRR = rr,
		},
		SeatPosition = parameters.seatPosition,
		Performance = {
			Acceleration = 10,
			Braking = 75,
			Deceleration = 10,
			HasNitro = true,
			MaxSpeedForward = 85,
		},
		Camera = {
			HeightScale = 1.25,
			DistanceScale = 1.5,
		},
	})
	return vehicle.vehicleModel
end

return Bus5

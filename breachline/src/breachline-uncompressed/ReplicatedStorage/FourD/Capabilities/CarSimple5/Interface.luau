--[[
CarSimple5 Capability - Drivable four-wheeled vehicle

Composes: Drivable behavior
Schema: CarSimple5 (body + 4 wheels)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)

local CarSimple5 = CapabilityBase.createChild()

function CarSimple5:getCapabilityDocumentation()
	return [[
The CarSimple5Capability creates a functional car from existing parts with four wheels and a body. Anything with less than four wheels should NOT use the CarSimple5Capability.
]]
end

function CarSimple5:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "CarSimple5",
			description = "a driveable vehicle with four wheels and a body",
		},
	}
end

function CarSimple5:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "ontop",
			description = "Position of the seat relative to the car body",
		})
		:build()
end

function CarSimple5:getCapabilitySelectionExamples()
	return {
		{
			user = "a car",
			assistant = {
				capability_reasoning = 'The user has requested a "car" which is a ground vehicle with wheels that players can drive. This clearly maps to the CarSimple5Capability which is designed to create functional cars with four wheels and a body that can be operated by players.',
				capability_selection = "CarSimple5Capability",
				overall_size_reasoning = "A typical car should be sized to accommodate Roblox avatars (1.5m tall) comfortably. A standard car is usually around 4-5 meters long, 1.8-2 meters wide, and 1.5-1.7 meters high. I'll suggest dimensions of 1.8m width (x), 1.6m height (y), and 4.5m length (z) to create a reasonably sized vehicle that players can enter and drive.",
				overall_size_selection = { x = 1.8, y = 1.6, z = 4.5 },
			},
		},
	}
end

function CarSimple5:getConfigureCapabilityExamples()
	return {
		{
			user = "a car",
			assistant = {
				capability_parameters_reasoning = 'The user wants to create "a car" which is a simple, straightforward request. Looking at the CarSimple5Capability schema, I need to configure the seatPosition parameter. The schema provides two options: "inside" (seat is inside the car body) or "ontop" (seat is on top of the car body). For a typical car, the seat should logically be positioned inside the car body rather than on top of it, as this represents normal car functionality where passengers sit within the vehicle\'s cabin.',
				capability_parameters_selection = {
					seatPosition = "ontop",
				},
			},
		},
	}
end

function CarSimple5:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("CarSimple5Capability configuration error: " .. errorMsg)
	end

	local carModel = generatedModels["car"]
	if not carModel then
		error("Could not find 'car' model in generatedModels")
	end

	local frontLeftWheel = carModel:FindFirstChild("left front wheel")
	local frontRightWheel = carModel:FindFirstChild("right front wheel")
	local rearLeftWheel = carModel:FindFirstChild("left rear wheel")
	local rearRightWheel = carModel:FindFirstChild("right rear wheel")
	local body = carModel:FindFirstChild("body")

	if not frontLeftWheel then error("Could not find 'left front wheel'") end
	if not frontRightWheel then error("Could not find 'right front wheel'") end
	if not rearLeftWheel then error("Could not find 'left rear wheel'") end
	if not rearRightWheel then error("Could not find 'right rear wheel'") end
	if not body then error("Could not find 'body'") end

	local vehicle = WheeledVehicleArchitect.build4Wheel(body, {
		SeatPosition = parameters.seatPosition,
		Schema = {
			WheelFL = frontLeftWheel,
			WheelFR = frontRightWheel,
			WheelRL = rearLeftWheel,
			WheelRR = rearRightWheel,
		},
		Performance = {
			HasNitro = true,
		}
	})
	return vehicle.vehicleModel
end

return CarSimple5

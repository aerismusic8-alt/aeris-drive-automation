--[[
SkateboardSimple5 Capability - Rideable skateboard via WheeledVehicle Board rig

Composes: WheeledVehicle.Board SubType (WheeledVehicle.buildBoard)
Schema: SkateboardSimple5 (body + 4 wheels)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)

local SkateboardSimple5 = CapabilityBase.createChild()

function SkateboardSimple5:getCapabilityDocumentation()
	return [[
The SkateboardSimple5Capability creates a rideable skateboard from a body and four wheels using the WheeledVehicle Board rig. Players activate a ProximityPrompt to mount; once mounted they can steer, ollie, and redress.
]]
end

function SkateboardSimple5:getModelSpecs()
	return {
		{
			name = "skateboard",
			modelSchema = "SkateboardSimple5",
			description = "a rideable skateboard with a body and four wheels",
		},
	}
end

function SkateboardSimple5:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function SkateboardSimple5:getCapabilitySelectionExamples()
	return {
		{
			user = "a skateboard",
			assistant = {
				capability_reasoning = "The user has requested a skateboard, which is a small board with four wheels that a player rides while standing. The SkateboardSimple5Capability uses the WheeledVehicle Board rig to deliver a rideable skateboard with steering, ollie, and redress.",
				capability_selection = "SkateboardSimple5Capability",
				overall_size_reasoning = "A standard skateboard is roughly 0.8m long, 0.2m wide, and 0.12m tall to look correct relative to a Roblox avatar.",
				overall_size_selection = { x = 0.2, y = 0.12, z = 0.8 },
			},
		},
	}
end

function SkateboardSimple5:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("SkateboardSimple5Capability configuration error: " .. errorMsg)
	end

	local skateboard = generatedModels["skateboard"]
	if not skateboard then error("Could not find 'skateboard' model in generatedModels") end

	local body = skateboard:FindFirstChild("body")
	local frontLeftWheel = skateboard:FindFirstChild("left front wheel")
	local frontRightWheel = skateboard:FindFirstChild("right front wheel")
	local rearLeftWheel = skateboard:FindFirstChild("left rear wheel")
	local rearRightWheel = skateboard:FindFirstChild("right rear wheel")

	if not body then error("Could not find 'body'") end
	if not frontLeftWheel then error("Could not find 'left front wheel'") end
	if not frontRightWheel then error("Could not find 'right front wheel'") end
	if not rearLeftWheel then error("Could not find 'left rear wheel'") end
	if not rearRightWheel then error("Could not find 'right rear wheel'") end

	local vehicle = WheeledVehicleArchitect.buildBoard(body, {
		Schema = {
			WheelFL = frontLeftWheel,
			WheelFR = frontRightWheel,
			WheelRL = rearLeftWheel,
			WheelRR = rearRightWheel,
		},
	})

	return vehicle.vehicleModel
end

return SkateboardSimple5

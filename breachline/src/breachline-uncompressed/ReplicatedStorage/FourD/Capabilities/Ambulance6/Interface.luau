--[[
Ambulance6 Capability - Drivable ambulance with a flashing siren light bar.

Architect: WheeledVehicle.build4Wheel (DriverSeat, engine, suspension, steering,
redress, four-wheel rig) parented under a wrapper Model.
Behavior: Sirennable - welds the "siren light bar" (BasePart or multi-part Model)
to the rig Chassis and parents red/blue PointLights to the leftmost / rightmost
parts. Driver presses V (default) to toggle the alternating flash.

Schema: Ambulance6 (body + 4 wheels + siren light bar)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local Sirennable = require(Behaviors.Sirennable.makeFunctional)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local HelpUI = require(FourD.Common.HelpUI)

local function makeFunctional(root: Model, config: { seatPosition: string? }): Model
	local fl = root:FindFirstChild("left front wheel")
	local fr = root:FindFirstChild("right front wheel")
	local rl = root:FindFirstChild("left rear wheel")
	local rr = root:FindFirstChild("right rear wheel")
	local body = root:FindFirstChild("body")
	local lightBar = root:FindFirstChild("siren light bar")

	if not fl then error("Missing 'left front wheel'") end
	if not fr then error("Missing 'right front wheel'") end
	if not rl then error("Missing 'left rear wheel'") end
	if not rr then error("Missing 'right rear wheel'") end
	if not body then error("Missing 'body'") end

	local lightBarRelCFs = {}
	if lightBar then
		local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
		for _, part in ipairs(GeometryUtils.getInstanceParts(lightBar)) do
			lightBarRelCFs[part] = bodyAnchor.CFrame:ToObjectSpace(part.CFrame)
		end
		lightBar.Parent = nil
	end

	local vehicle = WheeledVehicleArchitect.build4Wheel(body, {
		Schema = {
			WheelFL = fl,
			WheelFR = fr,
			WheelRL = rl,
			WheelRR = rr,
		},
		SeatPosition = config.seatPosition,
		Performance = { HasNitro = true },
	})
	local assembledCar = vehicle.vehicleModel

	local sirenEnabled = false
	if lightBar and next(lightBarRelCFs) then
		lightBar.Parent = assembledCar
		local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
		for part, relCF in pairs(lightBarRelCFs) do
			part.CFrame = bodyAnchor.CFrame:ToWorldSpace(relCF)
		end
		Sirennable.setup(assembledCar, lightBar, {})
		sirenEnabled = true
	end

	local helpSources = {
		{ Type = "Set", SetId = "WheeledVehicle.FourWheel" },
	}
	if sirenEnabled then
		table.insert(helpSources, { Type = "Set", SetId = "Sirennable" })
	end

	HelpUI.registerState(assembledCar, "Ambulance6_Driver", { Sources = helpSources })
	assembledCar:SetAttribute("HelpUI_DriverState", "Ambulance6_Driver")

	return assembledCar
end

local Ambulance6 = CapabilityBase.createChild()

function Ambulance6:getCapabilityDocumentation()
	return [[
The Ambulance6Capability creates a drivable ambulance with flashing red/blue siren lights.
Press V to toggle the siren while driving.
]]
end

function Ambulance6:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "Ambulance6",
			description = "an ambulance with four wheels, body, and siren light bar",
		},
	}
end

function Ambulance6:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "inside",
			description = "Position of the driver seat",
		})
		:build()
end

function Ambulance6:getCapabilitySelectionExamples()
	return {
		{
			user = "an ambulance",
			assistant = {
				capability_reasoning = "An ambulance is a boxy four-wheeled emergency vehicle with a roof-mounted siren light bar. Ambulance6Capability handles a drivable ambulance with flashing red/blue siren lights.",
				capability_selection = "Ambulance6Capability",
				overall_size_reasoning = "A real ambulance is roughly 6m long, 2.2m wide, and 2.8m tall (taller than a car because of the patient compartment).",
				overall_size_selection = { x = 2.2, y = 2.8, z = 6 },
			},
		},
		{
			user = "a paramedic van with flashing lights",
			assistant = {
				capability_reasoning = "A paramedic van is functionally an ambulance: four-wheeled emergency vehicle with siren light bar. Ambulance6Capability covers it.",
				capability_selection = "Ambulance6Capability",
				overall_size_reasoning = "A paramedic van is slightly shorter than a full ambulance, about 5.5m long, 2m wide, 2.5m tall.",
				overall_size_selection = { x = 2, y = 2.5, z = 5.5 },
			},
		},
	}
end

function Ambulance6:getModelPlanningExamples()
	return {
		{
			user = "an ambulance",
			assistant = {
				size_reasoning = "The body is a tall boxy ambulance cabin big enough for a Roblox avatar (1.5m) to sit inside, around 6m long, 2.2m wide, 2.5m tall. Wheels are heavy-duty van tires roughly 0.8m tall. The siren light bar is a long thin strip mounted on the roof, around 1.2m wide and 0.2m tall.",
				car = {
					description = "a white boxy ambulance cabin with red emergency cross markings on the sides, large windshield, sliding side door, and squared-off rear patient compartment",
					size = { x = 2.2, y = 2.5, z = 6 },
				},
				["left front wheel"] = {
					description = "a black heavy-duty van tire with a chrome hubcap",
					size = { x = 0.4, y = 0.8, z = 0.8 },
				},
				["right front wheel"] = {
					description = "a black heavy-duty van tire with a chrome hubcap",
					size = { x = 0.4, y = 0.8, z = 0.8 },
				},
				["left rear wheel"] = {
					description = "a black heavy-duty van tire with a chrome hubcap",
					size = { x = 0.4, y = 0.8, z = 0.8 },
				},
				["right rear wheel"] = {
					description = "a black heavy-duty van tire with a chrome hubcap",
					size = { x = 0.4, y = 0.8, z = 0.8 },
				},
				["siren light bar"] = {
					description = "a long horizontal emergency light bar with red and blue lens housings, mounted to the front of the ambulance roof",
					size = { x = 1.2, y = 0.2, z = 0.4 },
				},
			},
		},
	}
end

function Ambulance6:getConfigureCapabilityExamples()
	return {
		{
			user = "an ambulance the driver sits inside of",
			assistant = {
				capability_parameters_reasoning = "User explicitly says the driver sits inside the cabin, so seatPosition = 'inside'.",
				capability_parameters_selection = {
					seatPosition = "inside",
				},
			},
		},
		{
			user = "an ambulance you ride on top of",
			assistant = {
				capability_parameters_reasoning = "User wants the driver mounted on top of the body rather than inside the cabin, so seatPosition = 'ontop'.",
				capability_parameters_selection = {
					seatPosition = "ontop",
				},
			},
		},
	}
end

function Ambulance6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("Ambulance6Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return makeFunctional(carModel, parameters)
end

return Ambulance6

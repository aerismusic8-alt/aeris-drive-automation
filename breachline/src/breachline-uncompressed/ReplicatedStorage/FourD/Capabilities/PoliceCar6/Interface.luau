--[[
PoliceCar6 Capability - Drivable police car with a flashing siren light bar.

Architect: WheeledVehicle.build4Wheel (DriverSeat, engine, suspension, steering,
redress, four-wheel rig) parented under a wrapper Model.
Behavior: Sirennable - welds the "siren light bar" (BasePart or multi-part Model)
to the rig Chassis and parents red/blue PointLights to the leftmost / rightmost
parts. Driver presses V (default) to toggle the alternating flash.

Schema: PoliceCar6 (body + 4 wheels + siren light bar)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Beh = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local Sirennable = require(Beh.Sirennable.makeFunctional)
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

	HelpUI.registerState(assembledCar, "PoliceCar6_Driver", { Sources = helpSources })
	assembledCar:SetAttribute("HelpUI_DriverState", "PoliceCar6_Driver")

	return assembledCar
end

local PoliceCar6 = CapabilityBase.createChild()

function PoliceCar6:getCapabilityDocumentation()
	return [[
The PoliceCar6Capability creates a drivable police car with flashing red/blue siren lights.
Press V to toggle the siren while driving.
]]
end

function PoliceCar6:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "PoliceCar6",
			description = "a police car with four wheels, body, and siren light bar",
		},
	}
end

function PoliceCar6:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "inside",
			description = "Position of the driver seat",
		})
		:build()
end

function PoliceCar6:getCapabilitySelectionExamples()
	return {
		{
			user = "a police car",
			assistant = {
				capability_reasoning = "A police car is a four-wheeled sedan with a roof-mounted siren light bar. PoliceCar6Capability handles a drivable cop car with flashing red/blue siren lights.",
				capability_selection = "PoliceCar6Capability",
				overall_size_reasoning = "A real police cruiser is roughly 5m long, 1.9m wide, and 1.5m tall.",
				overall_size_selection = { x = 1.9, y = 1.5, z = 5 },
			},
		},
		{
			user = "a cop cruiser with flashing lights",
			assistant = {
				capability_reasoning = "A cop cruiser is a police car: four-wheeled sedan with siren light bar. PoliceCar6Capability covers it.",
				capability_selection = "PoliceCar6Capability",
				overall_size_reasoning = "A cruiser-style sedan is about 5m long, 1.9m wide, 1.5m tall.",
				overall_size_selection = { x = 1.9, y = 1.5, z = 5 },
			},
		},
		{
			user = "a sheriff SUV",
			assistant = {
				capability_reasoning = "A sheriff SUV is a four-wheeled police vehicle with a roof siren light bar - PoliceCar6Capability fits, just taller and boxier than a cruiser.",
				capability_selection = "PoliceCar6Capability",
				overall_size_reasoning = "A police SUV is around 5m long, 2m wide, 1.9m tall (taller than a cruiser).",
				overall_size_selection = { x = 2, y = 1.9, z = 5 },
			},
		},
	}
end

function PoliceCar6:getModelPlanningExamples()
	return {
		{
			user = "a police car",
			assistant = {
				size_reasoning = "The body is a sedan-shaped police cruiser big enough for a Roblox avatar (1.5m) to sit inside, about 5m long, 1.9m wide, 1.4m tall. Wheels are sporty performance tires roughly 0.7m tall. The siren light bar is a thin roof-mounted strip about 1m wide and 0.15m tall.",
				car = {
					description = "a black and white police sedan with a sloped windshield, side decals reading POLICE, a push bar on the front bumper, and a low aerodynamic profile",
					size = { x = 1.9, y = 1.4, z = 5 },
				},
				["left front wheel"] = {
					description = "a black sport performance tire with a chrome five-spoke rim",
					size = { x = 0.35, y = 0.7, z = 0.7 },
				},
				["right front wheel"] = {
					description = "a black sport performance tire with a chrome five-spoke rim",
					size = { x = 0.35, y = 0.7, z = 0.7 },
				},
				["left rear wheel"] = {
					description = "a black sport performance tire with a chrome five-spoke rim",
					size = { x = 0.35, y = 0.7, z = 0.7 },
				},
				["right rear wheel"] = {
					description = "a black sport performance tire with a chrome five-spoke rim",
					size = { x = 0.35, y = 0.7, z = 0.7 },
				},
				["siren light bar"] = {
					description = "a low-profile police roof light bar with separate red and blue lens housings on each side and a central control module",
					size = { x = 1, y = 0.15, z = 0.35 },
				},
			},
		},
	}
end

function PoliceCar6:getConfigureCapabilityExamples()
	return {
		{
			user = "a police car",
			assistant = {
				capability_parameters_reasoning = "Default cruiser - driver sits inside the cabin, so seatPosition = 'inside'.",
				capability_parameters_selection = {
					seatPosition = "inside",
				},
			},
		},
		{
			user = "a police car the cop rides on top of",
			assistant = {
				capability_parameters_reasoning = "User wants the driver mounted on top of the body rather than inside the cabin, so seatPosition = 'ontop'.",
				capability_parameters_selection = {
					seatPosition = "ontop",
				},
			},
		},
	}
end

function PoliceCar6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("PoliceCar6Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return makeFunctional(carModel, parameters)
end

return PoliceCar6

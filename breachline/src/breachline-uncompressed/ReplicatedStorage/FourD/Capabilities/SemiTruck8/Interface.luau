--[[
SemiTruck8 Capability - Drivable semi truck with hitch plate for towing

Composes: Drivable + Towable behaviors
Schema: SemiTruck8 (body + 6 wheels: front, mid, rear + hitch plate)
Uses front and rear wheels for drive; mid wheels and hitch plate are cosmetic/welded.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Beh = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local Towable = require(Beh.Towable)
local HelpUI = require(FourD.Common.HelpUI)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

local EXTRA_PART_NAMES = { "left mid wheel", "right mid wheel", "hitch plate" }

local function makeFunctional(root, config)
	local fl = root:FindFirstChild("left front wheel")
	local fr = root:FindFirstChild("right front wheel")
	local rl = root:FindFirstChild("left rear wheel")
	local rr = root:FindFirstChild("right rear wheel")
	local body = root:FindFirstChild("body")

	if not fl then error("Missing 'left front wheel'") end
	if not fr then error("Missing 'right front wheel'") end
	if not rl then error("Missing 'left rear wheel'") end
	if not rr then error("Missing 'right rear wheel'") end
	if not body then error("Missing 'body'") end

	local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
	local extraRelCFs = {}
	local extraParts = {}

	for _, partName in ipairs(EXTRA_PART_NAMES) do
		local extraPart = root:FindFirstChild(partName)
		if extraPart then
			extraParts[partName] = extraPart
			for _, part in ipairs(GeometryUtils.getInstanceParts(extraPart)) do
				extraRelCFs[part] = bodyAnchor.CFrame:ToObjectSpace(part.CFrame)
			end
			extraPart.Parent = nil
		end
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

	local chassis = GeometryUtils.findRigChassis(assembledCar)
	if chassis and next(extraRelCFs) then
		for _, partName in ipairs(EXTRA_PART_NAMES) do
			local extraPart = extraParts[partName]
			if extraPart then
				extraPart.Parent = assembledCar
			end
		end
		for part, relCF in pairs(extraRelCFs) do
			part.CFrame = bodyAnchor.CFrame:ToWorldSpace(relCF)
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			ConstructionHelpers.makeWeld(chassis, part)
		end

		local hitchPlate = extraParts["hitch plate"]
		if hitchPlate then
			local driverSeat = assembledCar:FindFirstChildWhichIsA("VehicleSeat", true)
			Towable.setupTower(assembledCar, hitchPlate, {
				DriverSeat = driverSeat,
				MaxAttachDistance = 15,
			})

			HelpUI.registerState(assembledCar, "SemiTruck8_Driver", {
				Sources = {
					{ Type = "Set", SetId = "WheeledVehicle.FourWheel" },
					{ Type = "Set", SetId = "Towable" },
				},
			})
			assembledCar:SetAttribute("HelpUI_DriverState", "SemiTruck8_Driver")
		end
	end

	return assembledCar
end

local SemiTruck8 = CapabilityBase.createChild()

function SemiTruck8:getCapabilityDocumentation()
	return [[
The SemiTruck8Capability creates a drivable semi truck with a hitch plate for connecting trailers.
Uses front and rear wheel pairs for drive; mid wheels are cosmetic. Press to connect trailers at the hitch plate.
]]
end

function SemiTruck8:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "SemiTruck8",
			description = "a semi truck with six wheels, body, and hitch plate",
		},
	}
end

function SemiTruck8:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "ontop",
			description = "Position of the driver seat",
		})
		:build()
end

function SemiTruck8:getCapabilitySelectionExamples()
	return {
		{
			user = "a semi truck",
			assistant = {
				capability_reasoning = 'A semi truck has a hitch plate for towing trailers. SemiTruck8Capability handles this.',
				capability_selection = "SemiTruck8Capability",
				overall_size_reasoning = "A semi truck cab is about 4m long, 2.5m wide, 4m tall.",
				overall_size_selection = { x = 2.5, y = 4, z = 4 },
			},
		},
	}
end

function SemiTruck8:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("SemiTruck8Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return makeFunctional(carModel, parameters)
end

return SemiTruck8

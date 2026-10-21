--[[
Tractor6 Capability - Drivable tractor with towable hitch

Composes: Drivable + Towable behaviors
Schema: Tractor6 (body + 4 wheels + hitch)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Beh = FourD:FindFirstChild("Behaviors")
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local Towable = require(Beh.Towable)
local HelpUI = require(FourD.Common.HelpUI)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

local function makeFunctional(root, config)
	local fl = root:FindFirstChild("left front wheel")
	local fr = root:FindFirstChild("right front wheel")
	local rl = root:FindFirstChild("left rear wheel")
	local rr = root:FindFirstChild("right rear wheel")
	local body = root:FindFirstChild("body")
	local hitch = root:FindFirstChild("hitch")

	if not fl then error("Missing 'left front wheel'") end
	if not fr then error("Missing 'right front wheel'") end
	if not rl then error("Missing 'left rear wheel'") end
	if not rr then error("Missing 'right rear wheel'") end
	if not body then error("Missing 'body'") end

	local hitchParts = {}
	if hitch then
		local bodyAnchor = if body:IsA("BasePart") then body else GeometryUtils.getOrSetPrimaryPart(body)
		assert(bodyAnchor, "Tractor6: body has no BasePart to anchor hitch")
		for _, part in ipairs(GeometryUtils.getInstanceParts(hitch)) do
			hitchParts[part] = bodyAnchor.CFrame:ToObjectSpace(part.CFrame)
		end
		hitch.Parent = nil
	end

	local vehicle = WheeledVehicleArchitect.build4Wheel(body, {
		Schema = {
			WheelFL = fl,
			WheelFR = fr,
			WheelRL = rl,
			WheelRR = rr,
		},
		SeatPosition = config.seatPosition,
		Performance = {
			HasNitro = true,
			MaxSpeedTorque = 8000,
			MinSpeedTorque = 45000,
			NitroTorque = 40000,
			TowAssist = true,
			TractionControl = true,
		},
		AsymmetricAxles = true,
	})
	local assembledCar = vehicle.vehicleModel

	if hitch and next(hitchParts) then
		hitch.Parent = assembledCar
		local bodyAnchor = if body:IsA("BasePart") then body else GeometryUtils.getOrSetPrimaryPart(body)
		assert(bodyAnchor, "Tractor6: body has no BasePart to anchor hitch")
		local chassis = GeometryUtils.findRigChassis(assembledCar)
		for part, relativeCF in pairs(hitchParts) do
			part.CFrame = bodyAnchor.CFrame:ToWorldSpace(relativeCF)
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			if chassis then
				ConstructionHelpers.makeWeld(chassis, part)
			end
		end
		local driverSeat = assembledCar:FindFirstChildWhichIsA("VehicleSeat", true)
		Towable.setupTower(assembledCar, hitch, { SkipWeld = true, DriverSeat = driverSeat })

		HelpUI.registerState(assembledCar, "Tractor6_Driver", {
			Sources = {
				{ Type = "Set", SetId = "WheeledVehicle.FourWheel" },
				{ Type = "Set", SetId = "Towable" },
			},
		})
		assembledCar:SetAttribute("HelpUI_DriverState", "Tractor6_Driver")
	end

	return assembledCar
end

local Tractor6 = CapabilityBase.createChild()

function Tractor6:getCapabilityDocumentation()
	return [[
The Tractor6Capability creates a drivable tractor with a rear hitch for towing trailers.
Use for farm tractors, utility tractors, or any vehicle that needs to tow equipment.
]]
end

function Tractor6:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "Tractor6",
			description = "a tractor with four wheels, a body, and a rear hitch",
		},
	}
end

function Tractor6:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "ontop",
			description = "Position of the driver seat",
		})
		:build()
end

function Tractor6:getCapabilitySelectionExamples()
	return {
		{
			user = "a farm tractor",
			assistant = {
				capability_reasoning = 'A farm tractor is a utility vehicle with towing capability. Tractor6Capability is the right choice.',
				capability_selection = "Tractor6Capability",
				overall_size_reasoning = "A farm tractor is about 4m long, 2m wide, 2.5m tall.",
				overall_size_selection = { x = 2, y = 2.5, z = 4 },
			},
		},
	}
end

function Tractor6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("Tractor6Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return makeFunctional(carModel, parameters)
end

return Tractor6

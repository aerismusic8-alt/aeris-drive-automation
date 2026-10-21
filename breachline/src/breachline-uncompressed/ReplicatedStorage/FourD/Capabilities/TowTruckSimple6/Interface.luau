--[[
TowTruckSimple6 Capability - Drivable tow truck with a fixed hitch

Composes: WheeledVehicle (FourWheel) Architect + Towable behavior
Schema: TowTruckSimple6 (body + 4 wheels + hook)
The hook is welded rigidly to the chassis and acts as the Towable tower hitch.
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

local function makeFunctional(root: Model, config: { [string]: any }): Model
	local fl = root:FindFirstChild("left front wheel")
	local fr = root:FindFirstChild("right front wheel")
	local rl = root:FindFirstChild("left rear wheel")
	local rr = root:FindFirstChild("right rear wheel")
	local body = root:FindFirstChild("body")
	local hook = root:FindFirstChild("hook")

	if not fl then error("Missing 'left front wheel'") end
	if not fr then error("Missing 'right front wheel'") end
	if not rl then error("Missing 'left rear wheel'") end
	if not rr then error("Missing 'right rear wheel'") end
	if not body then error("Missing 'body'") end

	local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
	local hookRelCFs = {}

	if hook then
		for _, part in ipairs(GeometryUtils.getInstanceParts(hook)) do
			hookRelCFs[part] = bodyAnchor.CFrame:ToObjectSpace(part.CFrame)
		end

		hook.Parent = nil
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
			Acceleration = 20,
			HasNitro = true,
			NitroTorque = 40000,
			MaxSpeedTorque = 8000,
			MinSpeedTorque = 45000,
			TowAssist = true,
			TractionControl = true,
		}
	})

	local assembledCar = vehicle.vehicleModel
	local chassis = GeometryUtils.findRigChassis(assembledCar)
	if hook and chassis and next(hookRelCFs) then
		hook.Parent = assembledCar

		for part, relCF in pairs(hookRelCFs) do
			part.CFrame = bodyAnchor.CFrame:ToWorldSpace(relCF)
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			ConstructionHelpers.makeWeld(chassis, part)
		end

		local driverSeat = assembledCar:FindFirstChildWhichIsA("VehicleSeat", true)
		Towable.setupTower(assembledCar, hook, { SkipWeld = true, DriverSeat = driverSeat })

		HelpUI.registerState(assembledCar, "TowTruckSimple6_Driver", {
			Sources = {
				{ Type = "Set", SetId = "WheeledVehicle.FourWheel" },
				{ Type = "Set", SetId = "Towable" },
			},
		})
		assembledCar:SetAttribute("HelpUI_DriverState", "TowTruckSimple6_Driver")
	end

	return assembledCar
end

local TowTruckSimple6 = CapabilityBase.createChild()

function TowTruckSimple6:getCapabilityDocumentation()
	return [[
The TowTruckSimple6Capability creates a drivable tow truck with a fixed hitch.
Press the prompt on the hook to connect or disconnect a towable receiver.
]]
end

function TowTruckSimple6:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "TowTruckSimple6",
			description = "a tow truck with four wheels, body, and a rear hook",
		},
	}
end

function TowTruckSimple6:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "ontop",
			description = "Position of the driver seat",
		})
		:build()
end

function TowTruckSimple6:getCapabilitySelectionExamples()
	return {
		{
			user = "a tow truck",
			assistant = {
				capability_reasoning = "A tow truck is a drivable vehicle with a hook for towing other vehicles. TowTruckSimple6Capability handles this.",
				capability_selection = "TowTruckSimple6Capability",
				overall_size_reasoning = "A tow truck is about 3m wide, 3.5m tall, 6m long.",
				overall_size_selection = { x = 3, y = 3.5, z = 6 },
			},
		},
	}
end

function TowTruckSimple6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("TowTruckSimple6Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return makeFunctional(carModel, parameters)
end

return TowTruckSimple6

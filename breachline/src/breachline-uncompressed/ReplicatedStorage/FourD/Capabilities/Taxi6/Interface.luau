--[[
Taxi6 Capability - Drivable taxi with toggleable taxi sign light

Composes: Drivable behavior + taxi sign toggle
Schema: Taxi6 (body + 4 wheels + taxi light sign)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local Lightable = require(FourD.Behaviors.Lightable)
local HelpUI = require(FourD.Common.HelpUI)

local function MakeFunctional(root: Model, config: { seatPosition: string? }): Model
	local fl = root:FindFirstChild("left front wheel")
	local fr = root:FindFirstChild("right front wheel")
	local rl = root:FindFirstChild("left rear wheel")
	local rr = root:FindFirstChild("right rear wheel")
	local body = root:FindFirstChild("body")
	local taxiSign = root:FindFirstChild("taxi light sign")

	if not fl then error("Missing 'left front wheel'") end
	if not fr then error("Missing 'right front wheel'") end
	if not rl then error("Missing 'left rear wheel'") end
	if not rr then error("Missing 'right rear wheel'") end
	if not body then error("Missing 'body'") end

	local signRelCFs = {}
	if taxiSign then
		local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
		for _, part in ipairs(GeometryUtils.getInstanceParts(taxiSign)) do
			signRelCFs[part] = bodyAnchor.CFrame:ToObjectSpace(part.CFrame)
		end
		taxiSign.Parent = nil
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

	local signLight: Lightable.StaticLight? = nil
	local signAnchor: BasePart? = nil
	if taxiSign and next(signRelCFs) then
		taxiSign.Parent = assembledCar
		local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
		local chassis = GeometryUtils.findRigChassis(assembledCar)
		for part, relCF in pairs(signRelCFs) do
			part.CFrame = bodyAnchor.CFrame:ToWorldSpace(relCF)
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			if chassis then ConstructionHelpers.makeWeld(chassis, part) end
			if not signAnchor then signAnchor = part end
		end

		if signAnchor then
			signLight = Lightable.newStatic(signAnchor, {
				Type = "point",
				Color = Color3.fromRGB(255, 200, 50),
				Brightness = 2,
				Range = 15,
				Enabled = false,
			})
		end
	end

	local helpSources = {
		{ Type = "Set", SetId = "WheeledVehicle.FourWheel" },
	}

	if signLight then
		assembledCar:SetAttribute("taxiSignOn", false)
		assembledCar:SetAttribute("taxiToggleKey", "T")

		local toggleEvent = Instance.new("RemoteEvent")
		toggleEvent.Name = "TaxiSignToggleEvent"
		toggleEvent.Parent = assembledCar

		-- The toggle relay (TaxiSignToggleEvent -> flip the sign light, gated by
		-- the driver) must run at Play, not here in the edit-time bind(): a
		-- connection made now is discarded when the compiler's RigExec session
		-- ends, so a compiled taxi received the event with nothing listening.
		-- Instead persist a pointer to the underlying Light and clone the durable
		-- TaxiSignServer component into the rig. It is stamped FourDServerComponent,
		-- registered in the runtime manifest, and started by
		-- ServerScriptService.FourDServerRuntime at Play, where it reconnects the relay.
		local lightInstance = signAnchor and signAnchor:FindFirstChildWhichIsA("Light")
		if lightInstance then
			local lightRef = Instance.new("ObjectValue")
			lightRef.Name = "Taxi6_SignLightRef"
			lightRef.Value = lightInstance
			lightRef.Parent = assembledCar
		end

		local serverComponent = script.Parent:FindFirstChild("TaxiSignServer")
		if serverComponent then
			serverComponent:Clone().Parent = assembledCar
		end

		local clientScript = script.Parent:FindFirstChild("TaxiClient")
		if clientScript then
			local clone = clientScript:Clone()
			if clone:IsA("BaseScript") then
				clone.Enabled = true
			end
			clone.Parent = assembledCar
		end

		table.insert(helpSources, { Type = "Set", SetId = "Taxi6" })
	end

	HelpUI.registerState(assembledCar, "Taxi6_Driver", { Sources = helpSources })
	assembledCar:SetAttribute("HelpUI_DriverState", "Taxi6_Driver")

	return assembledCar
end

local Taxi6 = CapabilityBase.createChild()

function Taxi6:getCapabilityDocumentation()
	return [[
The Taxi6Capability creates a drivable taxi with a roof-mounted sign that can be toggled on/off.
Press T to toggle the taxi sign light.
]]
end

function Taxi6:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "Taxi6",
			description = "a taxi cab with four wheels, body, and a roof taxi sign",
		},
	}
end

function Taxi6:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "inside",
			description = "Position of the driver seat",
		})
		:build()
end

function Taxi6:getCapabilitySelectionExamples()
	return {
		{
			user = "a taxi",
			assistant = {
				capability_reasoning = 'A taxi cab with a roof sign. Taxi6Capability handles this.',
				capability_selection = "Taxi6Capability",
				overall_size_reasoning = "A taxi is about 4.8m long, 1.8m wide, 1.6m tall.",
				overall_size_selection = { x = 1.8, y = 1.6, z = 4.8 },
			},
		},
	}
end

function Taxi6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("Taxi6Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return MakeFunctional(carModel, parameters)
end

return Taxi6

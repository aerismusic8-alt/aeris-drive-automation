--[[
MultiPlayerCombatPropPlaneSimple3 Capability - Two-occupant propeller aircraft.
Pilot flies; rear gunner takes over fire authority for the forward gun.

Composes: AirVehicle Architect (Plane SubType) + Gunnable (newHardpoint, infinite ammo)
Schema: MultiPlayerCombatPropPlaneSimple3 (body, propeller, center/right/left landing gear, gun)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local AirVehicleArchitect = require(FourD.Architects.AirVehicle)
local Gunnable = require(Behaviors.Gunnable)
local HelpUI = require(FourD.Common.HelpUI)

local HELP_STATE_PILOT_NO_GUNNER = "MultiPlayerCombatPropPlaneSimple3_Pilot_NoGunner"
local HELP_STATE_PILOT_WITH_GUNNER = "MultiPlayerCombatPropPlaneSimple3_Pilot_WithGunner"
local HELP_STATE_GUNNER = "MultiPlayerCombatPropPlaneSimple3_Gunner"

local OPTIONAL_CHILDREN = {
	"left landing gear",
	"right landing gear",
	"center landing gear",
}

local DEFAULT_GUN_DAMAGE = 30
local DEFAULT_GUN_FIRE_RATE = 600

local GUNNER_OFFSET_BEHIND = 6
local GUNNER_SEAT_SIZE = Vector3.new(1.5, 0.5, 1.5)
local GUNNER_PROMPT_DISTANCE_MULT = 1.5

local function fillInConfigDefaults(config: { [string]: any })
	config.gunDamage = config.gunDamage or DEFAULT_GUN_DAMAGE
	config.gunFireRate = config.gunFireRate or DEFAULT_GUN_FIRE_RATE
end

local function collectChildrenByName(root: Model, name: string): { PVInstance }
	local matches: { PVInstance } = {}
	for _, child in root:GetChildren() do
		if child.Name == name and (child:IsA("Model") or child:IsA("BasePart")) then
			table.insert(matches, child)
		end
	end

	return matches
end

local function buildGunnerSeat(planeModel: Model): Seat?
	local hullRoot = planeModel.PrimaryPart
	if not hullRoot then
		warn("[MultiPlayerCombatPropPlaneSimple3] planeModel has no PrimaryPart; cannot place gunner seat")
		return nil
	end

	local seat = Instance.new("Seat")
	seat.Name = "GunnerSeat"
	seat.Size = GUNNER_SEAT_SIZE
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.Anchored = false
	seat.CFrame = hullRoot.CFrame * CFrame.new(0, 0, GUNNER_OFFSET_BEHIND)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hullRoot
	weld.Part1 = seat
	weld.Parent = seat

	seat.Parent = planeModel

	return seat
end

local function buildGunnerPrompt(gunnerSeat: Seat, planeModel: Model): ProximityPrompt
	local extents = planeModel:GetExtentsSize()

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GunnerPrompt"
	prompt.ActionText = "Gunner"
	prompt.ObjectText = "Plane"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.min(extents.X, extents.Z) * GUNNER_PROMPT_DISTANCE_MULT
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Enabled = false
	prompt.Parent = gunnerSeat

	return prompt
end

local function attachGunnerCoopScript(planeModel: Model)
	local template = script.Parent:FindFirstChild("GunnerCoop")
	if not template then
		warn("[MultiPlayerCombatPropPlaneSimple3] GunnerCoop server script template missing")
		return
	end

	local clone = template:Clone()
	clone.Enabled = true
	clone.Parent = planeModel
end

local function makeFunctional(root: Model, config: { [string]: any }): Instance?
	config = config or {}
	fillInConfigDefaults(config)

	local body = root:FindFirstChild("body")
	if not body then error("Missing 'body' child in prop plane model") end

	local propellers = collectChildrenByName(root, "propeller")
	if #propellers == 0 then error("Missing 'propeller' child in prop plane model") end

	local gunModel = root:FindFirstChild("gun")
	if not gunModel or not (gunModel:IsA("Model") or gunModel:IsA("BasePart")) then
		error("Missing 'gun' child in prop plane model")
	end

	gunModel.Parent = nil

	local schema: { [string]: any } = {
		Body = body,
		Propellers = propellers,
	}

	for _, optionalName in OPTIONAL_CHILDREN do
		local match = root:FindFirstChild(optionalName)
		if not match then continue end
		if optionalName == "left landing gear" then
			schema.LeftLandingGear = match
		elseif optionalName == "right landing gear" then
			schema.RightLandingGear = match
		elseif optionalName == "center landing gear" then
			schema.CenterLandingGear = match
		end
	end

	local plane = AirVehicleArchitect.buildPlane(root, {
		Schema = schema,
		Performance = {
			MaxSpeed = config.maxSpeed,
			StallSpeed = config.stallSpeed,
			Acceleration = config.acceleration,
			PitchRate = config.pitchRate,
			TurnRate = config.turnRate,
			BlurDiskOpacity = config.blurDiskOpacity,
			MaxBankDegrees = 55,
		},
	})

	local planeModel = plane.planeModel

	local controllerHandle = Gunnable.newHardpoint(planeModel, gunModel, {
		FireSequence = "Simultaneous",
		GunDamage = config.gunDamage,
		GunFireRate = config.gunFireRate,
		GunAmmo = -1,
		GunRange = config.gunRange,
		ProjectileSpeed = config.projectileSpeed,
		SpreadDegrees = 1,
		ConvergenceRange = (config.gunRange or 800) / 2,
		HudViewerAttribute = "PilotUserId",
	})

	if not controllerHandle then
		warn("[MultiPlayerCombatPropPlaneSimple3] Gunnable.newHardpoint returned nil; gun will not fire")
		return planeModel
	end

	local gunnerSeat = buildGunnerSeat(planeModel)
	if not gunnerSeat then
		return planeModel
	end

	buildGunnerPrompt(gunnerSeat, planeModel)

	HelpUI.registerState(planeModel, HELP_STATE_PILOT_NO_GUNNER, {
		Sources = {
			{ Type = "Set", SetId = "AirVehicle.Plane" },
			{ Type = "Set", SetId = "Gunnable.Hardpoint" },
		},
	})
	HelpUI.registerState(planeModel, HELP_STATE_PILOT_WITH_GUNNER, {
		Sources = {
			{ Type = "Set", SetId = "AirVehicle.Plane" },
		},
	})
	HelpUI.registerState(planeModel, HELP_STATE_GUNNER, {
		Sources = {
			{ Type = "Set", SetId = "Gunnable.Hardpoint" },
			{ Type = "Set", SetId = "AirVehicle.Plane", Filter = { "SwapSeat" } },
		},
	})

	planeModel:SetAttribute("HelpUI_SuppressDefault", true)
	planeModel:SetAttribute("HelpUI_State_PilotNoGunner", HELP_STATE_PILOT_NO_GUNNER)
	planeModel:SetAttribute("HelpUI_State_PilotWithGunner", HELP_STATE_PILOT_WITH_GUNNER)
	planeModel:SetAttribute("HelpUI_State_Gunner", HELP_STATE_GUNNER)

	attachGunnerCoopScript(planeModel)

	plane:SetGunnerSeat(gunnerSeat)

	return planeModel
end

local MultiPlayerCombatPropPlaneSimple3 = CapabilityBase.createChild()

function MultiPlayerCombatPropPlaneSimple3:getCapabilityDocumentation()
	return [[
The MultiPlayerCombatPropPlaneSimple3Capability creates a two-occupant propeller-driven combat aircraft. The pilot mounts at the front with E (PC) or ButtonX (Gamepad); mouse / right thumbstick controls pitch and rotation; W or ButtonA increases throttle while held, S or ButtonB decreases it. Once a pilot is mounted, a Gunner prompt appears at the rear of the plane; a second player presses E (PC) or ButtonY (Gamepad) to occupy the gunner seat, which hides their character and grants them fire authority over the forward-fire gun. While the gunner is seated, only the gunner can fire; when the gunner leaves the seat, fire authority falls back to the pilot. Pitch is clamped to plus or minus 85 degrees; lift fades below StallSpeed. Ammunition never depletes and there is no reload. The propeller spins visually proportional to current speed and is decorated with a semi-transparent blur disk. Landing gear is welded along with the body. All speed and rate parameters are specified in real units (studs per second, degrees per second).
]]
end

function MultiPlayerCombatPropPlaneSimple3:getModelSpecs()
	return {
		{
			name = "plane",
			modelSchema = "MultiPlayerCombatPropPlaneSimple3",
			description = "a propeller-driven combat plane with a body, a propeller, three landing gear pieces, and a forward-fire gun, sized for two occupants (pilot in front, gunner behind)",
		},
	}
end

function MultiPlayerCombatPropPlaneSimple3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxSpeed", {
			type = "number",
			default = 155,
			description = "Maximum target speed in studs per second",
		})
		:addOptionalArgument("stallSpeed", {
			type = "number",
			default = 25,
			description = "Speed below which lift begins to fade, in studs per second",
		})
		:addOptionalArgument("acceleration", {
			type = "number",
			default = 35,
			description = "How quickly current speed ramps toward effective target, in studs per second squared",
		})
		:addOptionalArgument("pitchRate", {
			type = "number",
			default = 30,
			description = "Pitch rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("turnRate", {
			type = "number",
			default = 50,
			description = "Heading rotation rate at maximum input, in degrees per second",
		})
		:addOptionalArgument("gunDamage", {
			type = "number",
			default = DEFAULT_GUN_DAMAGE,
			description = "Damage applied per projectile hit",
		})
		:addOptionalArgument("gunFireRate", {
			type = "number",
			default = DEFAULT_GUN_FIRE_RATE,
			description = "Total rounds per minute across all barrels",
		})
		:addOptionalArgument("gunRange", {
			type = "number",
			description = "Maximum projectile range in studs (defaults handled by Gunnable)",
		})
		:addOptionalArgument("projectileSpeed", {
			type = "number",
			description = "Projectile travel speed in studs per second (defaults handled by Gunnable)",
		})
		:build()
end

function MultiPlayerCombatPropPlaneSimple3:getCapabilitySelectionExamples()
	return {
		{
			user = "a two-seat propeller fighter plane",
			assistant = {
				capability_reasoning = "The user wants a two-occupant armed propeller plane. MultiPlayerCombatPropPlaneSimple3Capability creates a pilot-and-gunner prop plane with a body, propeller, landing gear, and a forward-fire gun.",
				capability_selection = "MultiPlayerCombatPropPlaneSimple3Capability",
				overall_size_reasoning = "A two-seat fighter prop plane is roughly 11m wide (wingspan), 3m tall, and 10m long to accommodate tandem seating.",
				overall_size_selection = { x = 11.0, y = 3.0, z = 10.0 },
			},
		},
		{
			user = "a tandem-seat WW2 fighter plane",
			assistant = {
				capability_reasoning = "A tandem-seat WW2 fighter pairs a pilot with a rear gunner on a propeller-driven aircraft. MultiPlayerCombatPropPlaneSimple3Capability covers this role.",
				capability_selection = "MultiPlayerCombatPropPlaneSimple3Capability",
				overall_size_reasoning = "A WW2 tandem fighter is roughly 12m wide, 3m tall, and 10m long.",
				overall_size_selection = { x = 12.0, y = 3.0, z = 10.0 },
			},
		},
	}
end

function MultiPlayerCombatPropPlaneSimple3:getConfigureCapabilityExamples()
	return {
		{
			user = "a two-seat propeller fighter plane",
			assistant = {
				capability_parameters_reasoning = "A standard two-seat prop fighter uses default prop plane and gun values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a heavy tandem bomber escort with a high-power cannon",
			assistant = {
				capability_parameters_reasoning = "A heavy bomber escort favours damage and range over rate of fire; modest speed boost over baseline.",
				capability_parameters_selection = {
					maxSpeed = 130,
					gunDamage = 60,
					gunFireRate = 480,
					gunRange = 350,
					projectileSpeed = 350,
				},
			},
		},
	}
end

function MultiPlayerCombatPropPlaneSimple3:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("MultiPlayerCombatPropPlaneSimple3Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["plane"]
	if not model then
		error("Could not find 'plane' model in generatedModels")
	end

	return makeFunctional(model, parameters)
end

return MultiPlayerCombatPropPlaneSimple3
a
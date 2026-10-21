--[[
GunSimple3Capability - Generic equippable gun backed by the Firearm2 Architect (Pistol SubType)

Composes: Handheld Tool + Firearm2 Architect (handle rigging, ShotOrigin, OTS aim, spread)
Schema: GunSimple3 (grip, frame, barrel)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Firearm2 = require(FourD.Architects.Firearm2)

local function MakeFunctional(root: Model, config: { [string]: any }): Tool
	config = config or {}

	local grip = root:FindFirstChild("grip")
	local frame = root:FindFirstChild("frame")
	local barrel = root:FindFirstChild("barrel")

	if not grip then error("GunSimple3: Missing 'grip' child in gun model") end
	if not frame then error("GunSimple3: Missing 'frame' child in gun model") end
	if not barrel then error("GunSimple3: Missing 'barrel' child in gun model") end

	local schema = {
		Grip = grip,
		Frame = frame,
		Barrel = barrel,
	}

	Firearm2.buildPistol(root, {
		Schema = schema,
		AimMode = "default",
		DamagePerRound = config.damagePerRound,
		AmmoMagSize = config.ammoMagSize,
		FireRate = config.fireRate,
		AmmoReloadTime = config.ammoReloadTime,
		AmmoReloadEmptyTime = config.ammoReloadEmptyTime,
		BaseSpread = config.baseSpread,
		MaxSpread = config.maxSpread,
		MaxDistance = config.maxDistance,
	})

	return root.Parent :: Tool
end

local GunSimple3 = CapabilityBase.createChild()

function GunSimple3:getCapabilityDocumentation()
	return [[
GunSimple3Capability creates an equippable handheld gun that players can pick up and equip.
It rigs the model as a Roblox Tool using the Firearm2 Architect Pistol SubType: invisible Handle
sized to the body bounding box, all parts welded, ShotOrigin Attachment placed at the barrel tip,
combat stats stamped as Tool attributes, left-hand IK targeting the midpoint between grip and
frame-front, and a cloned client controller that locks the player into a third-person
over-the-shoulder camera with hipfire spread.
The GunSimple3 schema expects only: grip, frame, barrel. Use this for any simple gun shape
that can be described by a grip, a body/frame, and a barrel without additional detailing parts.
]]
end

function GunSimple3:getModelSpecs()
	return {
		{
			name = "gun",
			modelSchema = "GunSimple3",
			description = "a simple gun with a grip, frame, and barrel",
		},
	}
end

function GunSimple3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("damagePerRound", {
			type = "number",
			default = 9,
			minimum = 0,
			description = "Damage dealt per shot",
		})
		:addOptionalArgument("ammoMagSize", {
			type = "number",
			default = 30,
			minimum = 1,
			description = "Number of rounds per magazine",
		})
		:addOptionalArgument("fireRate", {
			type = "number",
			default = 8,
			minimum = 0.1,
			description = "Maximum shots fired per second",
		})
		:addOptionalArgument("ammoReloadTime", {
			type = "number",
			default = 2,
			minimum = 0,
			description = "Time in seconds to reload the magazine",
		})
		:addOptionalArgument("ammoReloadEmptyTime", {
			type = "number",
			default = 0.5,
			minimum = 0,
			description = "Extra reload time in seconds when reloading from an empty magazine",
		})
		:addOptionalArgument("baseSpread", {
			type = "number",
			default = 5,
			minimum = 0,
			description = "Idle hipfire spread floor in degrees",
		})
		:addOptionalArgument("maxSpread", {
			type = "number",
			default = 30,
			minimum = 0,
			description = "Maximum total hipfire spread cap in degrees",
		})
		:addOptionalArgument("maxDistance", {
			type = "number",
			default = 300,
			minimum = 1,
			description = "Maximum effective shot distance in studs",
		})
		:build()
end

function GunSimple3:getCapabilitySelectionExamples()
	return {
		{
			user = "a simple gun",
			assistant = {
				capability_reasoning = 'The user wants a "simple gun" described by a grip, frame, and barrel. GunSimple3Capability wraps any such model as a Tool with combat attributes and firing behavior.',
				capability_selection = "GunSimple3Capability",
				overall_size_reasoning = "A handheld gun for a Roblox avatar should be roughly hand-sized: about 0.5m long (z), 0.15m wide (x), 0.3m tall (y).",
				overall_size_selection = { x = 0.15, y = 0.3, z = 0.5 },
			},
		},
	}
end

function GunSimple3:getConfigureCapabilityExamples()
	return {
		{
			user = "a slow, powerful gun",
			assistant = {
				capability_parameters_reasoning = "A powerful gun fires slowly but deals heavy damage per shot, with a longer reload and tighter accuracy.",
				capability_parameters_selection = {
					damagePerRound = 80,
					ammoMagSize = 6,
					fireRate = 0.5,
					ammoReloadTime = 3,
					ammoReloadEmptyTime = 0.75,
					baseSpread = 3,
					maxSpread = 20,
					maxDistance = 400,
				},
			},
		},
		{
			user = "a fast light gun",
			assistant = {
				capability_parameters_reasoning = "A light gun fires quickly with lower damage and a short reload, but loses accuracy under sustained fire.",
				capability_parameters_selection = {
					damagePerRound = 20,
					ammoMagSize = 12,
					fireRate = 4,
					ammoReloadTime = 1,
					ammoReloadEmptyTime = 0.3,
					baseSpread = 6,
					maxSpread = 40,
					maxDistance = 250,
				},
			},
		},
	}
end

function GunSimple3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("GunSimple3Capability configuration error: " .. errorMsg)
	end

	local gunModel = generatedModels["gun"]
	if not gunModel then
		error("GunSimple3Capability: Could not find 'gun' model")
	end

	return MakeFunctional(gunModel, parameters)
end

return GunSimple3

--[[
Sword4Capability - Equippable melee sword with swing and chain-swing attacks

Composes: Handheld Tool + MeleeTool Architect
Schema: Sword4 (model with handle, hand guard, blade, and pommel sub-models)

Click to swing. A second swing can be chained within 0.8s of the first.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Architects = FourD:FindFirstChild("Architects")
local MeleeTool = require(Architects.MeleeTool)

local DAMAGE_DEALT = 35
local SWING_DEBOUNCE = 0.5
local CHAIN_SWING_ENABLED = true
local CHAIN_SWING_THRESHOLD = 0.8

local function MakeFunctional(model: Model): Tool
	local handleContainer = model:FindFirstChild("handle")
	assert(handleContainer and handleContainer:IsA("PVInstance"), "Sword4: Could not find 'handle' Model/BasePart in model")

	local architect = MeleeTool.build(model, {
		GripPart = handleContainer,
		DamageDealt = DAMAGE_DEALT,
		SwingDebounce = SWING_DEBOUNCE,
		ChainSwingEnabled = CHAIN_SWING_ENABLED,
		ChainSwingThreshold = CHAIN_SWING_THRESHOLD,
		SwingSpeed = 1.2,
		IdleAnimationId = "rbxassetid://84034123842429",
		Swing1AnimationId = "rbxassetid://102174116060593",
		Swing2AnimationId = "rbxassetid://87130514119618",
	})

	return architect.Tool
end

local Sword4 = CapabilityBase.createChild()

function Sword4:getCapabilityDocumentation()
	return [[
Sword4Capability creates an equippable melee sword players can pick up, equip, and swing.
The sword deals 35 damage per hit via the blade. Clicking triggers a swing; a second click
within 0.8 seconds chains into a second swing animation. After the chain (or a single swing),
there is a 0.25-second debounce before the player can swing again.
Use this for any one-handed bladed melee weapon: swords, sabers, longswords, etc.
]]
end

function Sword4:getModelSpecs()
	return {
		{
			name = "sword",
			modelSchema = "Sword4",
			description = "a one-handed sword with a handle, hand guard, blade, and pommel",
		},
	}
end

function Sword4:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Sword4:getCapabilitySelectionExamples()
	return {
		{
			user = "a sword",
			assistant = {
				capability_reasoning = 'The user wants a "sword" — a one-handed bladed melee weapon. Sword4Capability creates an equippable Tool with swing and chain-swing attacks via the MeleeTool Architect.',
				capability_selection = "Sword4Capability",
				overall_size_reasoning = "A one-handed sword for a Roblox avatar should be roughly 0.1m wide, 0.15m deep, and 1.2m long (blade + handle).",
				overall_size_selection = { x = 0.1, y = 1.2, z = 0.15 },
			},
		},
	}
end

function Sword4:getConfigureCapabilityExamples()
	return {}
end

function Sword4:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Sword4Capability configuration error: " .. errorMsg)
	end

	local swordModel = generatedModels["sword"]
	if not swordModel then
		error("Sword4Capability: Could not find 'sword' model")
	end

	return MakeFunctional(swordModel)
end

return Sword4

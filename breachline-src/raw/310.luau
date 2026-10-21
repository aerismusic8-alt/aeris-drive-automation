--[[
Katana3Capability - Equippable melee katana with swing and chain-swing attacks

Composes: Handheld Tool + MeleeTool Architect
Schema: Katana3 (model with handle, hand guard, and blade sub-models)

Click to swing. A second swing can be chained within 1.15s of the first.
Deals 80 damage per hit via the blade. 0.75-second debounce after each swing.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Architects = FourD:FindFirstChild("Architects")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local MeleeTool = require(Architects.MeleeTool)

local DAMAGE_DEALT = 80
local SWING_DEBOUNCE = 0.75
local CHAIN_SWING_ENABLED = true
local CHAIN_SWING_THRESHOLD = 1.15
local SWING_SPEED = 0.75

local function MakeFunctional(model: Model): Tool
	local handleContainer = model:FindFirstChild("handle")
	assert(handleContainer and handleContainer:IsA("PVInstance"), "Katana3: Could not find 'handle' Model/BasePart in model")

	local architect = MeleeTool.build(model, {
		GripPart = handleContainer,
		DamageDealt = DAMAGE_DEALT,
		SwingDebounce = SWING_DEBOUNCE,
		ChainSwingEnabled = CHAIN_SWING_ENABLED,
		ChainSwingThreshold = CHAIN_SWING_THRESHOLD,
		SwingSpeed = SWING_SPEED,
		IdleAnimationId = "rbxassetid://84034123842429",
		Swing1AnimationId = "rbxassetid://102174116060593",
		Swing2AnimationId = "rbxassetid://87130514119618",
	})

	return architect.Tool
end

local Katana3 = CapabilityBase.createChild()

function Katana3:getCapabilityDocumentation()
	return [[
Katana3Capability creates an equippable melee katana players can pick up, equip, and swing.
The katana deals 80 damage per hit via the blade. Clicking triggers a swing; a second click
within 1.15 seconds chains into a second swing animation. After the chain (or a single swing),
there is a 0.75-second debounce before the player can swing again.
Use this for any long curved one-handed bladed melee weapon: katanas, sabers, curved swords, etc.
]]
end

function Katana3:getModelSpecs()
	return {
		{
			name = "katana",
			modelSchema = "Katana3",
			description = "a katana with a handle, hand guard, and blade",
		},
	}
end

function Katana3:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Katana3:getCapabilitySelectionExamples()
	return {
		{
			user = "a katana",
			assistant = {
				capability_reasoning = 'The user wants a "katana" 
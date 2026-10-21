--[[
Knife2Capability - Equippable melee knife with swing and chain-swing attacks

Composes: Handheld Tool + MeleeTool Architect
Schema: Knife2 (model with handle and blade sub-models)

Click to swing. A second swing can be chained within 0.75s of the first.
Deals 10 damage per hit via the blade. 0.2-second debounce after each swing.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Architects = FourD:FindFirstChild("Architects")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local MeleeTool = require(Architects.MeleeTool)

local DAMAGE_DEALT = 10
local SWING_DEBOUNCE = 0.2
local CHAIN_SWING_ENABLED = true
local CHAIN_SWING_THRESHOLD = 0.75
local IDLE_ANIMATION_ID = "rbxassetid://112021396962604"
local SWING1_ANIMATION_ID = "rbxassetid://100209953640718"
local SWING2_ANIMATION_ID = "rbxassetid://98091696568893"

local function MakeFunctional(model: Model): Tool
	local handleContainer = model:FindFirstChild("handle")
	assert(handleContainer and handleContainer:IsA("PVInstance"), "Knife2: Could not find 'handle' Model/BasePart in model")

	local architect = MeleeTool.build(model, {
		GripPart = handleContainer,
		DamageDealt = DAMAGE_DEALT,
		SwingDebounce = SWING_DEBOUNCE,
		ChainSwingEnabled = CHAIN_SWING_ENABLED,
		ChainSwingThreshold = CHAIN_SWING_THRESHOLD,
		IdleAnimationId = IDLE_ANIMATION_ID,
		Swing1AnimationId = SWING1_ANIMATION_ID,
		Swing2AnimationId = SWING2_ANIMATION_ID,
	})

	return architect.Tool
end

local Knife2 = CapabilityBase.createChild()

function Knife2:getCapabilityDocumentation()
	return [[
Knife2Capability creates an equippable melee knife players can pick up, equip, and swing.
The knife deals 10 damage per hit via the blade. Clicking triggers a swing; a second click
within 0.75 seconds chains into a second swing animation. After the chain (or a single swing),
there is a 0.2-second debounce before the player can swing again.
Use this for any short one-handed bladed melee weapon: knives, daggers, hunting knives, etc.
]]
end

function Knife2:getModelSpecs()
	return {
		{
			name = "knife",
			modelSchema = "Knife2",
			description = "a knife with a handle and blade",
		},
	}
end

function Knife2:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Knife2:getCapabilitySelectionExamples()
	return {
		{
			user = "a knife",
			assistant = {
				capability_reasoning = 'The user wants a "knife" 
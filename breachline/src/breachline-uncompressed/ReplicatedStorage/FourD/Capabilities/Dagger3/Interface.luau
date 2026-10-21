--[[
Dagger3Capability - Equippable melee dagger with swing and chain-swing attacks

Composes: Handheld Tool + MeleeTool Architect
Schema: Dagger3 (model with hilt, crossguard, and blade sub-models)

Click to swing. A second swing can be chained within 0.5s of the first.
Deals 40 damage per hit via the blade. 0.25-second debounce after each swing.
Swings at 1.5x speed.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Architects = FourD:FindFirstChild("Architects")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local MeleeTool = require(Architects.MeleeTool)

local DAMAGE_DEALT = 40
local SWING_DEBOUNCE = 0.25
local CHAIN_SWING_ENABLED = true
local CHAIN_SWING_THRESHOLD = 0.5
local SWING_SPEED = 1.5

local function MakeFunctional(model: Model): Tool
	local hiltContainer = model:FindFirstChild("hilt")
	assert(hiltContainer and hiltContainer:IsA("PVInstance"), "Dagger3: Could not find 'hilt' Model/BasePart in model")

	local architect = MeleeTool.build(model, {
		GripPart = hiltContainer,
		DamageDealt = DAMAGE_DEALT,
		SwingDebounce = SWING_DEBOUNCE,
		ChainSwingEnabled = CHAIN_SWING_ENABLED,
		ChainSwingThreshold = CHAIN_SWING_THRESHOLD,
		SwingSpeed = SWING_SPEED,
	})

	return architect.Tool
end

local Dagger3 = CapabilityBase.createChild()

function Dagger3:getCapabilityDocumentation()
	return [[
Dagger3Capability creates an equippable melee dagger players can pick up, equip, and swing.
The dagger deals 40 damage per hit via the blade. Clicking triggers a swing; a second click
within 0.5 seconds chains into a second swing animation. After the chain (or a single swing),
there is a 0.25-second debounce before the player can swing again. Swings at 1.5x speed.
Use this for any short double-edged bladed melee weapon: daggers, stilettos, dirks, etc.
]]
end

function Dagger3:getModelSpecs()
	return {
		{
			name = "dagger",
			modelSchema = "Dagger3",
			description = "a dagger with a hilt, crossguard, and blade",
		},
	}
end

function Dagger3:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Dagger3:getCapabilitySelectionExamples()
	return {
		{
			user = "a dagger",
			assistant = {
				capability_reasoning = 'The user wants a "dagger" — a short double-edged bladed melee weapon. Dagger3Capability creates an equippable Tool with fast swing and chain-swing attacks via the MeleeTool Architect.',
				capability_selection = "Dagger3Capability",
				overall_size_reasoning = "A dagger for a Roblox avatar should be roughly 0.03m wide, 0.35m long, and 0.02m deep (blade + hilt).",
				overall_size_selection = { x = 0.03, y = 0.35, z = 0.02 },
			},
		},
	}
end

function Dagger3:getConfigureCapabilityExamples()
	return {}
end

function Dagger3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Dagger3Capability configuration error: " .. errorMsg)
	end

	local daggerModel = generatedModels["dagger"]
	if not daggerModel then
		error("Dagger3Capability: Could not find 'dagger' model")
	end

	return MakeFunctional(daggerModel)
end

return Dagger3

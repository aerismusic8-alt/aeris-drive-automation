--[[
Pickaxe2Capability - Equippable melee pickaxe with a single heavy swing

Composes: Handheld Tool + MeleeTool Architect
Schema: Pickaxe2 (model with handle and head sub-models)

Click to swing. Deals 40 damage per hit. 1-second debounce between swings.
No chain swing.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Architects = FourD:FindFirstChild("Architects")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local MeleeTool = require(Architects.MeleeTool)

local function MakeFunctional(model: Model): Tool
	local handleContainer = model:FindFirstChild("handle")
	assert(handleContainer and handleContainer:IsA("PVInstance"), "Pickaxe2: Could not find 'handle' Model/BasePart in model")

	local architect = MeleeTool.build(model, {
		GripPart = handleContainer,
		DamageDealt = 40,
		SwingDebounce = 1,
		ChainSwingEnabled = false,
		ChainSwingThreshold = 1.25,
		SwingSpeed = 1,
		IdleAnimationId = "rbxassetid://131400357056664",
		Swing1AnimationId = "rbxassetid://89142755170274",
		Swing2AnimationId = "rbxassetid://89142755170274",
	})

	return architect.Tool
end

local Pickaxe2 = CapabilityBase.createChild()

function Pickaxe2:getCapabilityDocumentation()
	return [[
Pickaxe2Capability creates an equippable melee pickaxe players can pick up, equip, and swing.
The pickaxe deals 40 damage per hit via the head. Clicking triggers a swing with a 1-second debounce
before the player can swing again. There is no chain swing combo.
Use this for any pickaxe-style mining or melee tool: pickaxes, mattocks, picks, etc.
]]
end

function Pickaxe2:getModelSpecs()
	return {
		{
			name = "pickaxe",
			modelSchema = "Pickaxe2",
			description = "a pickaxe with a handle and head",
		},
	}
end

function Pickaxe2:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Pickaxe2:getCapabilitySelectionExamples()
	return {
		{
			user = "a pickaxe",
			assistant = {
				capability_reasoning = 'The user wants a "pickaxe" 
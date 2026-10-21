--[[
Bat2Capability - Equippable melee baseball bat with a single heavy swing

Composes: Handheld Tool + MeleeTool Architect
Schema: Bat2 (model with handle and barrel sub-models)

Click to swing. Deals 50 damage per hit via the barrel. 1-second debounce between swings.
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
	assert(handleContainer and handleContainer:IsA("PVInstance"), "Bat2: Could not find 'handle' Model/BasePart in model")

	local architect = MeleeTool.build(model, {
		GripPart = handleContainer,
		DamageDealt = 50,
		SwingDebounce = 1,
		ChainSwingEnabled = false,
		ChainSwingThreshold = 1.25,
		SwingSpeed = 1,
		IdleAnimationId = "rbxassetid://106739575541281",
		Swing1AnimationId = "rbxassetid://72159930721542",
		Swing2AnimationId = "rbxassetid://129777753997762",
	})

	return architect.Tool
end

local Bat2 = CapabilityBase.createChild()

function Bat2:getCapabilityDocumentation()
	return [[
Bat2Capability creates an equippable melee baseball bat players can pick up, equip, and swing.
The bat deals 50 damage per hit via the barrel. Clicking triggers a swing with a 1-second debounce
before the player can swing again. There is no chain swing combo.
Use this for any blunt one-handed melee weapon: baseball bats, clubs, batons, etc.
]]
end

function Bat2:getModelSpecs()
	return {
		{
			name = "bat",
			modelSchema = "Bat2",
			description = "a baseball bat with a handle and barrel",
		},
	}
end

function Bat2:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Bat2:getCapabilitySelectionExamples()
	return {
		{
			user = "a baseball bat",
			assistant = {
				capability_reasoning = 'The user wants a "baseball bat" 
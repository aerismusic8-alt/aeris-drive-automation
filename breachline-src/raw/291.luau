--[[
NoCapability - Default capability for objects that don't match specialized capabilities

This class extends CapabilityBase to provide a simple default capability for objects
that don't require car, airplane, or blaster functionality. Objects are simply
assembled with physics enabled and no special interactive features.
]]
local FourD = script:FindFirstAncestor("FourD")
local Capabilities = script.Parent.Parent
local Common = FourD.Common
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local createConfiguration = require(Common.createConfiguration)
local GeometryUtils = require(Common.GeometryUtils)
local ConstructionHelpers = require(Common.ConstructionHelpers)
local DamageController = require(Common.DamageController)

local DEFAULT_ANCHORED = false

local function FillInConfigDefaults(config)
	if config.anchored == nil then
		print("WARNING: NoBehavior: anchored not set in config, defaulting to " .. tostring(DEFAULT_ANCHORED))
		config.anchored = DEFAULT_ANCHORED
	end
end

local function MakeFunctional(objectBody, config)
	assert(objectBody:IsA("Model"), "objectBody must be a Model")

	-- make sure all the config fields are there and set defaults
	FillInConfigDefaults(config)

	local parts = GeometryUtils.getInstanceParts(objectBody)
	for _, part in ipairs(parts) do
		part.Anchored = config.anchored
	end

	-- set primary part to first part if no primary part is found
	if not objectBody.PrimaryPart then
		objectBody.PrimaryPart = objectBody:FindFirstChildWhichIsA("BasePart", true)
	end

	-- If not anchored, weld all parts together
	if not config.anchored then
		objectBody.PrimaryPart.Anchored = false
		ConstructionHelpers.weldAllParts(objectBody, objectBody.PrimaryPart)
	end

	-- Create a Configuration object and populate it with values from 'config' (if provided)
	createConfiguration(objectBody, config, "NoBehaviorConfig")
	DamageController.new(objectBody, 1)

	return objectBody
end

local NoBehavior = CapabilityBase.createChild()

function NoBehavior:getCapabilityDocumentation()
	return [[
Only use NoCapability as an absolute last resort. If any other capability matches then use that.
]]
end

--[[
Gets the predefined schema name for GenerateModelAsync.
Returns the schema name to use with the generation API.
For generic objects, we use the Body1 predefined schema.
]]
function NoBehavior:getModelSpecs()
	return {
		{
			name = "model",
			modelSchema = "Body1",
			description = "a static object",
		},
	} -- Use the Body1 predefined schema for generic shapes
end

--[[
NoCapability configuration parameters
]]
function NoBehavior:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addArgument("anchored", {
			type = "boolean",
			default = false,
			description = [[Whether the object should be anchored (static) or unanchored (affected by physics).
                        * true: Object is fixed in place and cannot be moved
                        * false: Object can be pushed, affected by gravity and physics (default)]],
		})
		:build()
end

--[[
Gets capability selection incontext examples for this capability.
]]
function NoBehavior:getCapabilitySelectionExamples()
	return {
		{
			user = "a tree",
			assistant = {
				capability_reasoning = 'The user has requested "a tree" which is a natural decorative object for environment design. Trees are static scenery elements without interactive functionality, making NoCapability the correct choice.',
				capability_selection = "NoCapability",
				overall_size_reasoning = "A tree should be appropriately scaled for a Roblox environment where avatars are 1.5m tall. A medium-sized tree would have a trunk/canopy width of about 3 meters (x), a height of 5 meters (y) to make it clearly recognizable as a tree above player height, and a depth of 3 meters (z) for the canopy spread.",
				overall_size_selection = { x = 3, y = 5, z = 3 },
			},
		},
		{
			user = "a treasure chest",
			assistant = {
				capability_reasoning = 'The user has requested "a treasure chest" which is a prop or container object. While it could potentially have interactive opening mechanics, the basic chest object itself doesn\'t require vehicle or weapon capabilities. NoCapability is appropriate for this type of game prop.',
				capability_selection = "NoCapability",
				overall_size_reasoning = "A treasure chest should be sized appropriately for a Roblox avatar (1.5m tall) to interact with. A typical treasure chest would be about 1 meter wide (x), 0.7 meters tall (y) - roughly knee-to-waist height for an avatar, and 0.6 meters deep (z) to hold items while being reasonably portable.",
				overall_size_selection = { x = 1, y = 0.7, z = 0.6 },
			},
		},
		{
			user = "a bicycle",
			assistant = {
				capability_reasoning = 'The user has requested a "bicycle". This is a two-wheeled vehicle. The Car5Capability is specifically designed for four-wheeled vehicles and would not be appropriate or functional for a two-wheeled bicycle\'s physics. Therefore, "NoCapability" is selected to create a static model or prop of a bicycle.',
				capability_selection = "NoCapability",
				overall_size_reasoning = "A bicycle should be sized appropriately for a Roblox avatar (1.5m tall) to sit on or interact with. The width (x) should be about 0.8 meters to fit the frame, the height (y) around 1.2 meters to include the seat and handlebars, and the length (z) about 1.8 meters to represent a reasonable bicycle size.",
				overall_size_selection = { x = 0.8, y = 1.2, z = 1.8 },
			},
		},
	}
end

function NoBehavior:getConfigureCapabilityExamples()
	return {
		{
			user = "a rock",
			assistant = {
				capability_parameters_reasoning = [[The user requested "a rock", which is a natural environmental object. Rocks in games are typically static decorative elements that don't need to move or be affected by physics. Based on the NoCapability schema, I need to configure the anchored parameter. Setting anchored to true will make the rock fixed in place, which is appropriate for environmental scenery like rocks that should stay where they're placed.]],
				capability_parameters_selection = {
					anchored = true,
				},
			},
		},
		{
			user = "a wooden crate",
			assistant = {
				capability_parameters_reasoning = [[The user requested "a wooden crate", which is typically a movable prop in games. Crates are often used as physics objects that players can push around or stack. Based on the NoCapability schema, I'll set anchored to false so the crate will be affected by physics and can be moved by players or other forces, creating a more interactive and dynamic environment.]],
				capability_parameters_selection = {
					anchored = false,
				},
			},
		},
	}
end

--[[
Binds NoCapability to a model.
]]
function NoBehavior:bind(generateModels, parameters)
	-- Validate configuration
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("NoCapability configuration error: " .. errorMsg)
	end

	local model = generateModels["model"]

	-- Create configuration with defaults
	local noBehaviorConfig = {
		anchored = parameters.anchored,
	}

	-- Default to false if not specified
	if noBehaviorConfig.anchored == nil then
		noBehaviorConfig.anchored = false
	end

	-- Call the makeFunctional functionality
	return MakeFunctional(model, noBehaviorConfig)
end

return NoBehavior
h/
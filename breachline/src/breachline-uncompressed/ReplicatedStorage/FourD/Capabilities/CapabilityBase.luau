--[[
CapabilityBase - Base class for functional object capabilities

This module provides a class inheritance-based approach for creating functional object capabilities

Each capability defines:
- Required schema for geometry
- Required schema for configuration
- Documentation for LLMs
- Configuration examples for knowledge base
- Selection examples for when to use the capability
- Implementation of bind to attach capability to a model
]]

local FourD = script:FindFirstAncestor("FourD")
local Types = require(FourD.Common.Types)

local CapabilityBase = {}
CapabilityBase.__index = CapabilityBase

--[[
Creates a new CapabilityBase instance.
This is the base class that all specific capabilities should inherit from.

@param name string: The name of the capability
@return CapabilityBase: A new capability instance
]]
function CapabilityBase.new(): Types.Capability
	local self = setmetatable({}, CapabilityBase)
	self.configurationExamples = {}
	self.selectionExamples = {}
	return self
end

--[[
Gets the model specifications for GenerateModelAsync.
Returns an array of model specifications, where each specification contains:
- name: string - The name/identifier for this model (e.g., "gunBody", "projectile")
- modelSchema: string - The predefined schema name (e.g., "Body1", "Car5")
- description: string - Description for the model generation prompt
- generationOptions: table? - Optional override options for this specific model's generation
  (e.g., {maxTriangles = 1000, generateTextures = false}). Model-specific options take precedence over global options.

@return table: Array of model specifications
]]
function CapabilityBase:getModelSpecs(): {
	{
		name: string,
		modelSchema: string,
		description: string,
		generationOptions: Types.table?,
	}
}
	error("getModelSpecs must be implemented by subclass")
end

--[[
Gets the functional capability schema for this capability's configuration.
This defines the detailed configuration parameters and their types for this capability.
This should be overridden by subclasses to define their specific schema.

@return table: Schema definition describing required configuration parameters
]]
function CapabilityBase:getBindParametersDefinition(): Types.table
	error("getBindParametersDefinition must be implemented by subclass")
end

--[[
Gets documentation for LLMs to understand how to use this capability.
This should be overridden by subclasses to provide specific documentation.

@return string: Documentation explaining how to configure this capability
]]
function CapabilityBase:getCapabilityDocumentation(): string
	error("getCapabilityDocumentation must be implemented by subclass")
end

--[[
Gets capability selection incontext examples for this capability.
These examples help the capability selection stage learn when to select this capability.
This should be overridden by subclasses to provide specific examples.

Each example should have 'user' and 'assistant' fields where:
- user: The user prompt
- assistant: The expected capability selection output (capability_reasoning, capability)

@return table: Array of capability selection examples
]]
function CapabilityBase:getCapabilitySelectionExamples(): { Types.CapabilitySelectionExampleSchema }
	return {}
end

--[[
Gets model planning incontext examples for this capability.
These examples help the model planning stage learn how to generate descriptions and sizes for components.
This should be overridden by subclasses to provide specific examples.

Each example should have 'user' and 'assistant' fields where:
- user: The user prompt
- assistant: For single model - {size_reasoning, size}; For multiple models - {componentName: {description, size}}

@return table: Array of model planning examples
]]
function CapabilityBase:getModelPlanningExamples(): { Types.ModelPlanningExampleSchema }
	return {}
end

--[[
Gets configure capability incontext examples for this capability.
These examples help the configure capability stage learn how to configure this capability.
This should be overridden by subclasses to provide specific examples.

Each example should have 'user' and 'assistant' fields where:
- user: The user prompt
- assistant: The expected configure capability output (capability_parameters_reasoning, capability_parameters)

@return table: Array of configure capability examples
]]
function CapabilityBase:getConfigureCapabilityExamples(): { Types.ConfigureCapabilityExampleSchema }
	return {}
end

--[[
Binds this capability to a model with the given configuration.
This is equivalent to makeCarFunctional, makeGunFunctional, etc. in the old system.
This should be overridden by subclasses to implement their specific functionality.

@param generatedModels: { string: Instance }: Map from model name to generated model instance
@param config table: Configuration parameters for the capability
@return Instance: The functional model
]]
-- selene: allow(unused_variable)
function CapabilityBase:bind(generatedModels: { string: Instance }, config: Types.table): Instance
	error("bind must be implemented by subclass")
end

--[[
Validates that a configuration matches the required schema.
This is a helper method that subclasses can use to validate configurations.
Uses the capability's getBindParametersDefinition() method for validation.

@param config table: Configuration to validate
@return boolean: True if valid, false otherwise
@return string?: Error message if invalid
]]
function CapabilityBase:validateConfig(config: Types.table): (boolean, string?)
	if not config then
		return false, "Configuration is required"
	end

	local schema = self:getBindParametersDefinition()
	if not schema then
		return true -- No schema means no validation required
	end

	-- Apply defaults for any missing fields that have them
	if schema.properties then
		for field, fieldSchema in pairs(schema.properties) do
			if config[field] == nil and fieldSchema.default ~= nil then
				config[field] = fieldSchema.default
			end
		end
	end

	-- Check required fields exist (after defaults have been applied)
	if schema.required then
		for _, field in ipairs(schema.required) do
			if config[field] == nil then
				return false, "Required field '" .. field .. "' is missing"
			end
		end
	end

	return true
end

--[[
Helper method to create a child class that inherits from CapabilityBase.

@param name string: Name of the child class
@return table: New child class constructor
]]
function CapabilityBase.createChild()
	local ChildClass = {}
	ChildClass.__index = ChildClass
	setmetatable(ChildClass, CapabilityBase)

	function ChildClass.new(_)
		local self = CapabilityBase.new()
		setmetatable(self, ChildClass)
		return self
	end

	return ChildClass
end

return CapabilityBase

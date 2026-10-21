--[[
Schema builder for creating functional behavior schemas with fluent interface.
Modeled after ToolBuilder pattern.

This module provides a reusable schema builder that can be used by all behavior interfaces
to create consistent, maintainable schema definitions.
]]

local SchemaBuilder = {}
SchemaBuilder.__index = SchemaBuilder

function SchemaBuilder.define()
	local self = setmetatable({}, SchemaBuilder)
	self.properties = {}
	self.required = {}
	return self
end

function SchemaBuilder:addOptionalArgument(name, schema)
	self.properties[name] = schema
	return self
end

function SchemaBuilder:addArgument(name, schema)
	self.properties[name] = schema
	table.insert(self.required, name)
	return self
end

function SchemaBuilder:build()
	return {
		type = "object",
		properties = self.properties,
		required = self.required,
	}
end

return SchemaBuilder

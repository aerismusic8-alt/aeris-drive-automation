--[[
CapabilityManager - Manager for functional object capabilities

This module provides a centralized way to manage and use functional object capabilities.
]]

local FourD = script.Parent.Parent
local Types = require(FourD.Common.Types)
local CapabilityManager = {}
CapabilityManager.__index = CapabilityManager

function CapabilityManager.new(): Types.CapabilityManager
	local self = setmetatable({}, CapabilityManager)
	self.capabilityRegistry = {}
	return self
end

--[[
Registers a capability in the manager.
Capabilities must have unique names.
@param name string: The name of the capability
@param capabilityClass Types.Capability: The capability class
]]
function CapabilityManager:registerCapability(name: string, capability: Types.Capability)
	local capabilityInstance = capability.new()

	-- Use instance registry if called on instance, global registry if called statically

	if self.capabilityRegistry[name] then
		warn("Capability already registered: " .. name)
		return
	end
	self.capabilityRegistry[name] = capabilityInstance
end

--[[
Gets a list of all registered capability names.

@return table: Array of capability names
]]
function CapabilityManager:getAvailableCapabilityNames(): { string }
	local names = {}
	for name, _ in pairs(self.capabilityRegistry) do
		table.insert(names, name)
	end
	return names
end

--[[
Gets the singleton instance of a capability.

@param name string: The name of the capability to get
@return Types.Capability: Cached capability instance
]]
function CapabilityManager:getCapabilityInstance(name: string): Types.Capability?
	local capabilityInstance = self.capabilityRegistry[name]
	if not capabilityInstance then
		warn("Unknown capability: " .. name)
		return nil
	end
	return capabilityInstance
end

return CapabilityManager
U.
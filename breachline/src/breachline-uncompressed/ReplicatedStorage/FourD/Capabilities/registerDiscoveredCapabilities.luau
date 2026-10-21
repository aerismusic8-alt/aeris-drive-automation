--[[
registerDiscoveredCapabilities - Auto-discovers capability folders under
ReplicatedStorage/FourD/Capabilities/ and registers each one whose folder
contains an "Interface" ModuleScript into the provided CapabilityManager.

Capability name is derived from the folder name; "Capability" suffix is
appended if not already present.
]]

local Capabilities = script.Parent
local Types = require(Capabilities.Parent.Common.Types)

local CAPABILITY_SUFFIX = "Capability"

local function deriveCapabilityName(folderName: string): string
	if folderName:sub(-#CAPABILITY_SUFFIX) == CAPABILITY_SUFFIX then
		return folderName
	end
	return folderName .. CAPABILITY_SUFFIX
end

local function registerDiscoveredCapabilities(manager: Types.CapabilityManager): Types.CapabilityManager
	for _, child in ipairs(Capabilities:GetChildren()) do
		if not child:IsA("Folder") and not child:IsA("ModuleScript") then
			continue
		end

		local interfaceModule = child:FindFirstChild("Interface")
		if not interfaceModule then
			continue
		end

		local capabilityName = deriveCapabilityName(child.Name)

		local ok, err = pcall(function()
			manager:registerCapability(capabilityName, require(interfaceModule))
		end)
		if ok then
			print("[registerDiscoveredCapabilities] Registered: " .. capabilityName)
		else
			warn("[registerDiscoveredCapabilities] FAILED to register " .. capabilityName .. ": " .. tostring(err))
		end
	end

	return manager
end

return registerDiscoveredCapabilities

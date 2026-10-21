-- Creates a Configuration instance on the given model from a plain Lua table.
-- Supports number, string, boolean, Vector3, CFrame, and Color3 types.
-- Returns the created Configuration.
local function createConfiguration(model, configTable, configName)
	assert(model and model:IsA("Instance"), "model must be an Instance")
	local configObj = Instance.new("Configuration")
	configObj.Name = configName or "Config"

	if type(configTable) == "table" then
		for key, value in pairs(configTable) do
			local valType = typeof(value)
			local valInstance
			if valType == "number" then
				valInstance = Instance.new("NumberValue")
			elseif valType == "string" then
				valInstance = Instance.new("StringValue")
			elseif valType == "boolean" then
				valInstance = Instance.new("BoolValue")
			elseif valType == "Vector3" then
				valInstance = Instance.new("Vector3Value")
			elseif valType == "CFrame" then
				valInstance = Instance.new("CFrameValue")
			elseif valType == "Color3" then
				valInstance = Instance.new("Color3Value")
			end

			if valInstance then
				valInstance.Name = tostring(key)
				valInstance.Value = value
				valInstance.Parent = configObj
			end
		end
	end

	configObj.Parent = model
	return configObj
end

return createConfiguration
:
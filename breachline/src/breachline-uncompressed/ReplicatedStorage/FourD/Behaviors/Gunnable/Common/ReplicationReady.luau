--[[
	GENERATED -- not part of upstream FourD.

	Upstream client logic runs as a ClientComponent started by FourDClientRuntime.
	A component can start before ObjectValue targets and sibling instances finish
	replicating, so Gunnable clients use these bounded waits before they snapshot
	their rig.
]]

local DEFAULT_TIMEOUT = 10
local ReplicationReady = {}

local function beforeDeadline(deadline: number): boolean
	return os.clock() < deadline
end

local function matchesClass(instance: Instance, classFilter: string | { string }?): boolean
	if classFilter == nil then return true end
	if typeof(classFilter) == "string" then
		return instance:IsA(classFilter)
	end
	for _, className in classFilter do
		if instance:IsA(className) then return true end
	end
	return false
end

function ReplicationReady.waitForAttribute(instance: Instance, name: string, timeout: number?): any
	local deadline = os.clock() + (timeout or DEFAULT_TIMEOUT)
	local value = instance:GetAttribute(name)
	while value == nil and beforeDeadline(deadline) do
		task.wait()
		value = instance:GetAttribute(name)
	end
	return value
end

function ReplicationReady.waitForChild(
	parent: Instance,
	name: string,
	className: string?,
	timeout: number?
): Instance?
	local child = parent:WaitForChild(name, timeout or DEFAULT_TIMEOUT)
	if child and (not className or child:IsA(className)) then
		return child
	end
	return nil
end

function ReplicationReady.waitForDescendant(
	root: Instance,
	name: string,
	className: string?,
	timeout: number?
): Instance?
	local deadline = os.clock() + (timeout or DEFAULT_TIMEOUT)
	repeat
		local descendant = root:FindFirstChild(name, true)
		if descendant and (not className or descendant:IsA(className)) then
			return descendant
		end
		task.wait()
	until not beforeDeadline(deadline)
	return nil
end

function ReplicationReady.waitForObjectValue(
	parent: Instance,
	name: string,
	classFilter: string | { string }?,
	timeout: number?
): Instance?
	local deadline = os.clock() + (timeout or DEFAULT_TIMEOUT)
	local ref = parent:WaitForChild(name, timeout or DEFAULT_TIMEOUT)
	if not ref or not ref:IsA("ObjectValue") then return nil end
	repeat
		local value = ref.Value
		if value and matchesClass(value, classFilter) then
			return value
		end
		task.wait()
	until not beforeDeadline(deadline)
	return nil
end

function ReplicationReady.waitForObjectValues(
	folder: Instance,
	expectedCount: number,
	className: string?,
	timeout: number?
): { Instance }
	local deadline = os.clock() + (timeout or DEFAULT_TIMEOUT)
	repeat
		local values = {}
		for _, child in folder:GetChildren() do
			if child:IsA("ObjectValue") then
				local value = child.Value
				if value and (not className or value:IsA(className)) then
					table.insert(values, value)
				end
			end
		end
		if #values == expectedCount then return values end
		task.wait()
	until not beforeDeadline(deadline)
	return {}
end

return ReplicationReady

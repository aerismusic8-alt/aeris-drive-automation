--[[
	File: NetworkOwnership.luau
]]--

-- Root

local NetworkOwnership = {}

-- Public Functions

local function trySetOwner(part: BasePart, owner: Player?)
	-- SetNetworkOwner errors on anchored parts (and parts welded to anchored
	-- parts). Skip those rather than letting a single un-ownable part throw and
	-- abort the caller mid-script -- at startup that aborts MountAuthority before
	-- it connects the mount prompt, so the prompt renders with no handler and
	-- pressing the interact key does nothing.
	if part:CanSetNetworkOwnership() then
		part:SetNetworkOwner(owner)
	end
end

function NetworkOwnership.setOwner(assembly: Instance, owner: Player?)
	if assembly:IsA("BasePart") then
		trySetOwner(assembly, owner)
	end

	for _, descendant in assembly:GetDescendants() do
		if descendant:IsA("BasePart") then
			trySetOwner(descendant, owner)
		end
	end
end

-- Return

return NetworkOwnership

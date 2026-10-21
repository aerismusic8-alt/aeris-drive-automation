local CollectionService = game:GetService("CollectionService")

local CAPABILITY_TAG = "FourDCapability"

local function stripCapabilityTag(instance: Instance)
	if CollectionService:HasTag(instance, CAPABILITY_TAG) then
		CollectionService:RemoveTag(instance, CAPABILITY_TAG)
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if CollectionService:HasTag(descendant, CAPABILITY_TAG) then
			CollectionService:RemoveTag(descendant, CAPABILITY_TAG)
		end
	end
end

return stripCapabilityTag

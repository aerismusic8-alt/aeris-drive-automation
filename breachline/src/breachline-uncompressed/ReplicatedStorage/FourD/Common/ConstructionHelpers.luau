local ConstructionHelpers = {}

---Creates a `WeldConstraint` between `part0` and `part1`, parented under `part0`.
---@param part0 -- First weld target; the constraint is parented here.
---@param part1 -- Second weld target.
function ConstructionHelpers.makeWeld(part0, part1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
end

function ConstructionHelpers.makeNoCollide(part0: BasePart, part1: BasePart)
	local constraint = Instance.new("NoCollisionConstraint")
	constraint.Part0 = part0
	constraint.Part1 = part1
	constraint.Parent = part0
end

---Recursively welds every BasePart at or beneath `instance` to `anchorPart` and unanchors them.
---Skips `anchorPart` itself so it is not welded to itself.
---@param instance -- Root of the subtree to weld.
---@param anchorPart -- Part that all welds attach to and that remains the anchor.
function ConstructionHelpers.weldAllParts(instance, anchorPart)
	if instance == anchorPart then
		return
	end
	if instance:IsA("BasePart") then
		instance.Anchored = false
		ConstructionHelpers.makeWeld(anchorPart, instance)
	end
	for _, c in instance:GetChildren() do
		ConstructionHelpers.weldAllParts(c, anchorPart)
	end
end

---Returns descendants of `root` whose Name contains any keyword as a case-insensitive substring.
---@param root -- Instance whose descendants will be scanned.
---@param keywords -- Array of keywords; each is lowercased internally before matching.
---@return matches -- Array of descendants matching any keyword. Empty if `keywords` is empty.
function ConstructionHelpers.findDescendantsByKeywords(root: Instance, keywords: { string }): { Instance }
	local matches: { Instance } = {}
	if #keywords == 0 then
		return matches
	end

	local lowerKeywords = table.create(#keywords)
	for _, keyword in keywords do
		table.insert(lowerKeywords, string.lower(keyword))
	end

	for _, descendant in root:GetDescendants() do
		local lowerName = string.lower(descendant.Name)
		for _, keyword in lowerKeywords do
			if string.find(lowerName, keyword, 1, true) then
				table.insert(matches, descendant)
				break
			end
		end
	end

	return matches
end

---Flattens a list of containers into a single array of `BasePart`/`MeshPart`/`UnionOperation` descendants.
---@param components -- Array of root instances to walk.
---@return parts -- Flat array of part-like descendants found across all components.
function ConstructionHelpers.getAllParts(components)
	local parts = {}

	local function addParts(component)
		if component:IsA("BasePart") or component:IsA("MeshPart") or component:IsA("UnionOperation") then
			table.insert(parts, component)
		end

		for _, child in component:GetChildren() do
			addParts(child)
		end
	end

	for _, component in components do
		addParts(component)
	end
	return parts
end

return ConstructionHelpers

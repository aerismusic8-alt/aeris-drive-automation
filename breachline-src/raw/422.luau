 Handle (Part in Workspace)
local Handle = script.Parent.Parent :: BasePart

local OnExpired = Handle:WaitForChild("OnExpired", 10) :: BindableEvent
if not OnExpired then return end

OnExpired.Event:Connect(function(position: Vector3)
	local explosion = Instance.new("Explosion")
	explosion.BlastRadius = RADIUS
	explosion.BlastPressure = 50
	explosion.DestroyJointRadiusPercent = 0
	explosion.Position = position
	explosion.Parent = Workspace

	local parts = Workspace:GetPartBoundsInRadius(position, RADIUS)
	local damagedSet: { [Instance]: boolean } = {}

	for _, part in parts do
		if not part:IsA("BasePart") then continue end

		local character = getCharacterFromPart(part)
		if character then
			if damagedSet[character] then continue end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:TakeDamage(DAMAGE)
				damagedSet[character] = true
			end
			continue
		end

		local damageableModel: Instance? = nil
		local ancestor: Instance? = part
		while ancestor and ancestor ~= Workspace do
			if CollectionService:HasTag(ancestor, "WeaponsSystemDamageable") then
				damageableModel = ancestor
				break
			end
			ancestor = ancestor.Parent
		end

		if damageableModel and not damagedSet[damageableModel] then
			local takeDamageEvent = damageableModel:FindFirstChild("TakeDamage")
			if takeDamageEvent and takeDamageEvent:IsA("BindableEvent") then
				takeDamageEvent:Fire(DAMAGE)
				damagedSet[damageableModel] = true
			end
		end
	end
end)

-- Persisted authoritative damage runtime.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local model = script.Parent
assert(model and model:IsA("Model"), "FourDDamageServer must be parented to a Model")

local health = model:WaitForChild("Health") :: IntValue
local takeDamage = model:WaitForChild("TakeDamage") :: BindableEvent
local config = model:WaitForChild("DamageConfig") :: Configuration
local toughnessValue = config:WaitForChild("Toughness") :: NumberValue
local destroyed = false

local function destroyModel()
	if destroyed then return end
	destroyed = true
	CollectionService:RemoveTag(model, "WeaponsSystemDamageable")

	local explosion = Instance.new("Explosion")
	explosion.BlastRadius = 10
	explosion.ExplosionType = Enum.ExplosionType.Craters
	explosion.Position = if model.PrimaryPart then model.PrimaryPart.Position else model:GetPivot().Position
	explosion.Parent = workspace

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		end
	end
	Debris:AddItem(model, 3)
end

takeDamage.Event:Connect(function(amount)
	if destroyed or type(amount) ~= "number" then return end
	local relative = if amount < 0 then amount else amount / math.max(toughnessValue.Value, 0.001)
	if amount >= 0 and relative < 1 then relative = 0 end
	local old = health.Value
	local nextValue = math.clamp(old - relative, 0, 100)
	health.Value = nextValue
	if old > 0 and nextValue <= 0 then destroyModel() end
end)

script:SetAttribute("RuntimeVersion", 1)
script:SetAttribute("RuntimeReady", true)

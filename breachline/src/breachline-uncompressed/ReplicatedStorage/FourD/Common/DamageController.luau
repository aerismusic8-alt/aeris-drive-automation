--[[
	DamageController authoring facade.

	Construction is serializable: values, event, tag, and one persisted server
	controller are authored into the model. No RBXScriptConnection or lifecycle
	table created here is required at runtime.
]]

local CollectionService = game:GetService("CollectionService")

local DamageController = {}
DamageController.__index = DamageController

local function ensure(className: string, name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing.ClassName == className, `{name} must be a {className}`)
		return existing
	end
	local value = Instance.new(className)
	value.Name = name
	value.Parent = parent
	return value
end

function DamageController.new(model: Model, toughness: number)
	assert(model and model:IsA("Model"), "DamageController requires a Model")
	assert(type(toughness) == "number" and toughness > 0, "toughness must be positive")

	local health = ensure("IntValue", "Health", model) :: IntValue
	health.Value = 100
	local takeDamage = ensure("BindableEvent", "TakeDamage", model) :: BindableEvent
	local config = ensure("Configuration", "DamageConfig", model) :: Configuration
	local toughnessValue = ensure("NumberValue", "Toughness", config) :: NumberValue
	toughnessValue.Value = toughness
	CollectionService:AddTag(model, "WeaponsSystemDamageable")

	local controller = model:FindFirstChild("FourDDamageServer")
	if not controller then
		local template = script:FindFirstChild("DamageControllerServer")
		assert(template and template:IsA("Script"), "DamageControllerServer template is missing")
		controller = template:Clone()
		controller.Name = "FourDDamageServer"
		controller:SetAttribute("CASBehaviorManaged", true)
		controller.Parent = model
		local controllerScript = controller :: Script
		controllerScript.Disabled = false
	end

	local self = setmetatable({
		model = model,
		healthProperty = health,
		takeDamageEvent = takeDamage,
		toughness = toughness,
		controller = controller,
	}, DamageController)
	return self
end

function DamageController:takeDamage(amount: number)
	self.takeDamageEvent:Fire(amount)
end

function DamageController:getHealth(): number
	return self.healthProperty.Value
end

function DamageController:getToughness(): number
	return self.toughness
end

function DamageController:destroy()
	if self.controller then self.controller:Destroy() end
end

return DamageController

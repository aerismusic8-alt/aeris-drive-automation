--[[
Grenade3Capability - Equippable throwable explosive grenade

Composes: Handheld Tool + Throwable Behavior
Schema: Grenade3 (model with grenade body, safety lever, and pull pin sub-models)

Throw to launch the grenade. After 3 seconds it explodes, dealing 40 damage to all
Humanoids and damageable models within a 15-stud radius. 5-second throw debounce.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Throwable = require(Behaviors.Throwable.makeFunctional)

local Grenade3Folder = script.Parent

local EXPIRE_TIME = 2.5
local FORWARD_THROW_FORCE = 75
local UPWARDS_THROW_FORCE = 50
local THROW_DEBOUNCE = 3

-- The pin/lever "pop" runtime effect (constants + helpers + the throw/clone
-- relays) lives in the co-located GrenadePopServer Server Script so it survives
-- to Play; see the note in MakeFunctional.

local function MakeFunctional(model: Model): Tool
	local throwableInstance = Throwable.setup(model, {
		CompensateGravity = false,
		ForwardThrowForce = FORWARD_THROW_FORCE,
		UpwardsThrowForce = UPWARDS_THROW_FORCE,
		ExpireTime = EXPIRE_TIME,
		NotifyOnHit = "never",
		ThrowDebounce = THROW_DEBOUNCE,
		IdleAnimation = "rbxassetid://92774415645913",
		ThrowAnimation = "rbxassetid://83053657496188",
		ThrowReleaseFraction = 0.4,
	})

	local tool = throwableInstance.Tool

	local explosionTemplate = Grenade3Folder:FindFirstChild("GrenadeExplosion")
	if explosionTemplate then
		local explosionScript = explosionTemplate:Clone()
		explosionScript.Enabled = true
		explosionScript.Parent = model
	else
		warn("Grenade3: GrenadeExplosion script template not found")
	end

	-- The pin/lever "pop" effect (fire the safety lever and pull pin off on throw,
	-- strip them from the thrown clone) must run at Play, not here in the edit-time
	-- bind(): a connection made now is discarded when the compiler's RigExec
	-- session ends, so on a compiled grenade the pieces never popped. Instead clone
	-- the durable GrenadePopServer co-located Server Script into the Tool -- the
	-- same mechanism ThrowableServer and GrenadeExplosion already use to survive to
	-- Play. It re-acquires the handle/model/events and reconnects the relays. The
	-- grenade's core throw + explode were never affected (ThrowableServer /
	-- GrenadeExplosion). The pop helpers below now live in GrenadePopServer.
	local popServerTemplate = Grenade3Folder:FindFirstChild("GrenadePopServer")
	if popServerTemplate then
		local popServer = popServerTemplate:Clone()
		if popServer:IsA("BaseScript") then
			popServer.Enabled = true
		end
		popServer.Parent = tool
	else
		warn("Grenade3: GrenadePopServer script template not found")
	end

	return tool
end

local Grenade3 = CapabilityBase.createChild()

function Grenade3:getCapabilityDocumentation()
	return [[
Grenade3Capability creates an equippable throwable grenade players can pick up, equip, and throw.
Clicking throws the grenade in the direction the player is facing. After 3 seconds, the grenade
explodes, dealing 40 damage to all Humanoids and damageable models within a 15-stud radius.
There is a 5-second debounce after each throw before the player can throw again.
Use this for any hand-thrown explosive: frag grenades, flashbangs, smoke grenades, etc.
]]
end

function Grenade3:getModelSpecs()
	return {
		{
			name = "grenade",
			modelSchema = "Grenade3",
			description = "a grenade with a grenade body, safety lever, and pull pin",
		},
	}
end

function Grenade3:getBindParametersDefinition()
	return SchemaBuilder.define():build()
end

function Grenade3:getCapabilitySelectionExamples()
	return {
		{
			user = "a grenade",
			assistant = {
				capability_reasoning = 'The user wants a "grenade" — a hand-thrown explosive that detonates after a short fuse. Grenade3Capability creates an equippable Tool that launches a timed explosive via the Throwable Behavior.',
				capability_selection = "Grenade3Capability",
				overall_size_reasoning = "A frag grenade for a Roblox avatar should be roughly 0.06m wide, 0.10m tall, and 0.06m deep.",
				overall_size_selection = { x = 0.06, y = 0.10, z = 0.06 },
			},
		},
	}
end

function Grenade3:getConfigureCapabilityExamples()
	return {}
end

function Grenade3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Grenade3Capability configuration error: " .. errorMsg)
	end

	local grenadeModel = generatedModels["grenade"]
	if not grenadeModel then
		error("Grenade3Capability: Could not find 'grenade' model")
	end

	return MakeFunctional(grenadeModel)
end

return Grenade3

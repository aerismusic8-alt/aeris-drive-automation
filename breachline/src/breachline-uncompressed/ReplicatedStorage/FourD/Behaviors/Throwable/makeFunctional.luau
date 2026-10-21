--[[
Throwable Behavior - Converts a model into a functional equippable throwable Tool

Every throw clones the assembly and launches the clone. The original tool stays
equipped, allowing the player to throw again immediately.

Dependencies: FourD/Common (GeometryUtils, ConstructionHelpers)
]]

local FourD = script:FindFirstAncestor("FourD")
local Common = FourD.Common
local GeometryUtils = require(Common.GeometryUtils)
local ConstructionHelpers = require(Common.ConstructionHelpers)

local ThrowableFolder = script.Parent

-- Constants

local DEFAULT_PARAMS: ThrowableParams = {
	ForwardThrowForce = 500,
	UpwardsThrowForce = 50,
	CompensateGravity = true,
	CompensateMass = true,
	CollisionsEnabled = true,
	ExpireTime = 0,
	NotifyOnHit = "once",
	HitFilter = {},
	HitFilterMode = "exclude",
	IdleAnimation = "",
	ThrowAnimation = "",
	ThrowDebounce = 0,
	ThrowReleaseFraction = 1.0,
}

-- Root

local Throwable = {}
Throwable.__index = Throwable

-- Private Functions

local function createAnimations(parent: Instance, idleId: string, throwId: string)
	local folder = Instance.new("Folder")
	folder.Name = "Animations"
	folder.Parent = parent

	if idleId ~= "" then
		local idle = Instance.new("Animation")
		idle.Name = "Idle"
		idle.AnimationId = idleId
		idle.Parent = folder
	end

	if throwId ~= "" then
		local throw = Instance.new("Animation")
		throw.Name = "Throw"
		throw.AnimationId = throwId
		throw.Parent = folder
	end
end

local function createHitFilter(parent: Instance, filter: { Instance })
	local folder = Instance.new("Folder")
	folder.Name = "HitFilter"
	folder.Parent = parent

	for i, instance in filter do
		local ref = Instance.new("ObjectValue")
		ref.Name = tostring(i)
		ref.Value = instance
		ref.Parent = folder
	end
end

-- Public Methods

---Destroys the Throwable behavior and cleans up all connections.
function Throwable:Destroy()
	if self._connections == nil then return end

	for _, connection in self._connections do
		pcall(function() connection:Disconnect() end)
	end

	self._connections = nil
	self.Tool = nil
	setmetatable(self, nil)
	table.freeze(self)
end

-- Constructor

---Sets up the Throwable behavior, constructing a fully functional throwable Tool.
---@param model -- The model to convert into a throwable Tool.
---@param params -- Optional configuration parameters.
function Throwable.setup(model: Model, params: ThrowableParams?): ThrowableInstance
	assert(model ~= nil, "model must not be nil.")
	assert(model:IsA("Model"), "model must be a valid Model.")

	local originalParent = model.Parent
	local self = setmetatable({
		_connections = {},
		Tool = nil,
	}, Throwable)

	local resolved: ThrowableParams = params or {}
	for key, value in DEFAULT_PARAMS do
		if resolved[key] ~= nil then continue end
		resolved[key] = value
	end

	local boundingCF, boundingSize = model:GetBoundingBox()

	local tool = Instance.new("Tool")
	tool.Name = model.Name
	tool.RequiresHandle = true
	tool.CanBeDropped = true
	tool.Grip = CFrame.identity

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = boundingSize
	handle.CFrame = boundingCF
	handle.Transparency = 1
	handle.CanCollide = true
	handle.CanTouch = true
	handle.Anchored = false
	handle.Parent = tool

	-- Parent model into the tool BEFORE welding so all parts share the same assembly tree
	model.Parent = tool

	for _, part in GeometryUtils.getInstanceParts(model) do
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = false
		ConstructionHelpers.makeWeld(handle, part)
	end

	tool:SetAttribute("ForwardThrowForce", resolved.ForwardThrowForce)
	tool:SetAttribute("UpwardsThrowForce", resolved.UpwardsThrowForce)
	tool:SetAttribute("CompensateGravity", resolved.CompensateGravity)
	tool:SetAttribute("CompensateMass", resolved.CompensateMass)
	tool:SetAttribute("CollisionsEnabled", resolved.CollisionsEnabled)
	tool:SetAttribute("ExpireTime", resolved.ExpireTime)
	tool:SetAttribute("NotifyOnHit", resolved.NotifyOnHit)
	tool:SetAttribute("HitFilterMode", resolved.HitFilterMode)
	tool:SetAttribute("ThrowDebounce", resolved.ThrowDebounce)
	tool:SetAttribute("ThrowReleaseFraction", math.clamp(resolved.ThrowReleaseFraction :: number, 0, 1))

	createHitFilter(tool, resolved.HitFilter :: { Instance })
	createAnimations(tool, resolved.IdleAnimation :: string, resolved.ThrowAnimation :: string)

	local throwAction = Instance.new("RemoteEvent")
	throwAction.Name = "ThrowAction"
	throwAction.Parent = tool

	local throwStartAction = Instance.new("RemoteEvent")
	throwStartAction.Name = "ThrowStartAction"
	throwStartAction.Parent = tool

	local cloneSpawned = Instance.new("BindableEvent")
	cloneSpawned.Name = "CloneSpawned"
	cloneSpawned.Parent = tool

	local serverTemplate = ThrowableFolder:FindFirstChild("ThrowableServer")
	if serverTemplate then
		local serverScript = serverTemplate:Clone()
		serverScript.Enabled = true
		serverScript.Parent = tool
	else
		warn("Throwable: ThrowableServer script template not found")
	end

	local clientTemplate = ThrowableFolder:FindFirstChild("ThrowableClient")
	if clientTemplate then
		local clientScript = clientTemplate:Clone()
		clientScript.Enabled = true
		clientScript.Parent = tool
	else
		warn("Throwable: ThrowableClient script template not found")
	end

	self._connections.ModelDestroying = model.Destroying:Once(function()
		self:Destroy()
	end)

	self.Tool = tool
	tool.Parent = originalParent
	return self
end

-- Types

export type ThrowableParams = {
	---How much initial forward force is applied when thrown. Default: 1000.
	ForwardThrowForce: number?,
	---How much initial upwards force is applied when thrown. Default: 500.
	UpwardsThrowForce: number?,
	---Whether workspace.Gravity is considered when applying upwardsThrowForce. Default: true.
	CompensateGravity: boolean?,
	---Whether overall assembly mass is considered when applying forces. Default: true.
	CompensateMass: boolean?,
	---Whether or not the thrown assembly has collisions. Default: true.
	CollisionsEnabled: boolean?,
	---Seconds until the thrown assembly is destroyed. Values <= 0 mean it never expires. Default: 0.
	ExpireTime: number?,
	---Whether the thrown assembly fires OnHit on every touch, the first touch, or no touches. Default: "once".
	NotifyOnHit: ("always" | "once" | "never")?,
	---Array of instances (and their children) to filter by. Default: {}.
	HitFilter: { Instance }?,
	---Whether hitFilter acts as a whitelist or blacklist. Default: "exclude".
	HitFilterMode: ("include" | "exclude")?,
	---Optional Idle animation ID that plays when holding the tool. Default: "" (disabled).
	IdleAnimation: string?,
	---Optional Throw animation ID that plays when throwing. Default: "" (disabled).
	ThrowAnimation: string?,
	---Seconds after a throw before the player can throw again. Default: 0 (no debounce).
	ThrowDebounce: number?,
	---Fraction of the Throw animation length at which the toss is released to the server (0-1). Default: 1.0 (release at end).
	ThrowReleaseFraction: number?,
}
export type ThrowableInstance = typeof(Throwable) & {
	Tool: Tool,
}

-- Return

return Throwable

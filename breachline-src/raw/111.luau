--[[
	File: MeleeTool.luau
]]--

-- Root

local MeleeTool = {}
MeleeTool.__index = MeleeTool

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local Dumpster = require(FourD.Libs.Dumpster)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local StripCapabilityTag = require(FourD.Common.stripCapabilityTag)
local recenterModelPivot = require(FourD.Common.recenterModelPivot)

-- Constants

local VERBOSE_LOGGING = false
local DEFAULT_DAMAGE_DEALT = 35
local DEFAULT_SWING_DEBOUNCE = 0.25
local DEFAULT_CHAIN_SWING_THRESHOLD = 0.8
local DEFAULT_CHAIN_SWING_ENABLED = false
local DEFAULT_SWING_SPEED = 1
local DEFAULT_HIT_CHECK_INTERVAL = 1
local DEFAULT_COLLISIONS = true
local DEFAULT_IDLE_ANIMATION_ID = "rbxassetid://93946499701225"
local DEFAULT_SWING1_ANIMATION_ID = "rbxassetid://111122024043577"
local DEFAULT_SWING2_ANIMATION_ID = "rbxassetid://74241212217813"
local DEFAULT_EQUIP_ANIMATION_ID = ""

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function resolveAnimationId(id: (string | number)?): string?
	if id == nil then return nil end
	if typeof(id) == "number" then
		return `rbxassetid://{id}`
	end

	return id
end

local function computeGripCFrame(gripPart: BasePart | Model, bodyParts: { BasePart }, boundingCF: CFrame, boundingSize: Vector3): CFrame
	local gripPos: Vector3
	local excludeSet: { [BasePart]: true } = {}
	if gripPart:IsA("BasePart") then
		gripPos = gripPart.Position
		excludeSet[gripPart] = true
	elseif gripPart:IsA("Model") then
		recenterModelPivot(gripPart)
		gripPos = gripPart:GetBoundingBox().Position
		for _, part in GeometryUtils.getInstanceParts(gripPart) do
			excludeSet[part] = true
		end
	else
		error("computeGripCFrame: GripPart must be BasePart or Model")
	end

	local otherParts: { BasePart } = {}
	for _, part in bodyParts do
		if not excludeSet[part] then
			table.insert(otherParts, part)
		end
	end

	local upDirWorld: Vector3
	if #otherParts > 0 then
		local centroid = GeometryUtils.computeVolumeWeightedCentroid(otherParts)
		upDirWorld = centroid - gripPos
	else
		upDirWorld = boundingCF.Position - gripPos
	end

	if upDirWorld.Magnitude < 1e-4 then
		upDirWorld = Vector3.yAxis
	end

	local upLocal = boundingCF:VectorToObjectSpace(upDirWorld)
	local ax, ay, az = math.abs(upLocal.X), math.abs(upLocal.Y), math.abs(upLocal.Z)
	local upVec: Vector3
	local crossA: Vector3, crossB: Vector3
	local sizeA: number, sizeB: number
	if ax >= ay and ax >= az then
		upVec = if upLocal.X >= 0 then Vector3.xAxis else -Vector3.xAxis
		crossA, sizeA = Vector3.yAxis, boundingSize.Y
		crossB, sizeB = Vector3.zAxis, boundingSize.Z
	elseif ay >= ax and ay >= az then
		upVec = if upLocal.Y >= 0 then Vector3.yAxis else -Vector3.yAxis
		crossA, sizeA = Vector3.xAxis, boundingSize.X
		crossB, sizeB = Vector3.zAxis, boundingSize.Z
	else
		upVec = if upLocal.Z >= 0 then Vector3.zAxis else -Vector3.zAxis
		crossA, sizeA = Vector3.xAxis, boundingSize.X
		crossB, sizeB = Vector3.yAxis, boundingSize.Y
	end

	return CFrame.new(boundingCF:PointToObjectSpace(gripPos))
		* CFrame.fromMatrix(Vector3.zero, if sizeA <= sizeB then crossA else crossB, upVec)
end

-- Private Methods

function MeleeTool:_rigHandle()
	local body: Model = self._body
	local boundingCF, boundingSize = body:GetBoundingBox()

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = boundingSize
	handle.CFrame = boundingCF
	handle.Transparency = 1
	handle.CanCollide = self._params.Collisions
	handle.CanTouch = true
	handle.Anchored = false

	local tool = Instance.new("Tool")
	tool.Name = body.Name
	tool.RequiresHandle = true
	tool.CanBeDropped = true

	handle.Parent = tool
	body.Parent = tool

	local bodyParts = GeometryUtils.getInstanceParts(body)
	for _, part in bodyParts do
		if part == handle then continue end
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		ConstructionHelpers.makeWeld(handle, part)
	end

	self._handle = handle
	self._tool = tool
	self._handleCF = boundingCF
	self._boundingSize = boundingSize
	self._bodyParts = bodyParts
end

function MeleeTool:_rigGrip()
	self._tool.Grip = computeGripCFrame(self._params.GripPart, self._bodyParts, self._handleCF, self._boundingSize)
end

function MeleeTool:_rigAttributes()
	local tool = self._tool
	tool:SetAttribute("DamageDealt", self._params.DamageDealt)
	tool:SetAttribute("SwingDebounce", self._params.SwingDebounce)
	tool:SetAttribute("ChainSwingThreshold", self._params.ChainSwingThreshold)
	tool:SetAttribute("ChainSwingEnabled", self._params.ChainSwingEnabled)
	tool:SetAttribute("SwingSpeed", self._params.SwingSpeed)
	tool:SetAttribute("HitCheckInterval", self._params.HitCheckInterval)
end

function MeleeTool:_rigRemotes()
	local swingAction = Instance.new("RemoteEvent")
	swingAction.Name = "SwingAction"
	swingAction.Parent = self._tool

	local hitRequest = Instance.new("RemoteEvent")
	hitRequest.Name = "HitRequest"
	hitRequest.Parent = self._tool

	local swingSignal = Instance.new("BindableEvent")
	swingSignal.Name = "SwingSignal"
	swingSignal.Parent = self._tool

	local hitSignal = Instance.new("BindableEvent")
	hitSignal.Name = "HitSignal"
	hitSignal.Parent = self._tool

	self._swingSignal = swingSignal
	self._hitSignal = hitSignal

	if self._params.DamagePart then
		local damagePartRef = Instance.new("ObjectValue")
		damagePartRef.Name = "DamagePartRef"
		damagePartRef.Value = self._params.DamagePart
		damagePartRef.Parent = self._tool
	end
end

function MeleeTool:_rigAnimations()
	local folder = Instance.new("Folder")
	folder.Name = "Animations"
	folder.Parent = self._tool

	local idle = Instance.new("Animation")
	idle.Name = "Idle"
	idle.AnimationId = resolveAnimationId(self._params.IdleAnimationId) :: string
	idle.Parent = folder

	local firstSwing = Instance.new("Animation")
	firstSwing.Name = "FirstSwing"
	firstSwing.AnimationId = resolveAnimationId(self._params.Swing1AnimationId) :: string
	firstSwing.Parent = folder

	local secondSwing = Instance.new("Animation")
	secondSwing.Name = "SecondSwing"
	secondSwing.AnimationId = resolveAnimationId(self._params.Swing2AnimationId) :: string
	secondSwing.Parent = folder

	local equipId = resolveAnimationId(self._params.EquipAnimationId)
	if equipId and equipId ~= "" then
		local equip = Instance.new("Animation")
		equip.Name = "Equip"
		equip.AnimationId = equipId
		equip.Parent = folder
	end
end

function MeleeTool:_rigSignals()
	local activatedEvent = Instance.new("BindableEvent")
	self._mainDump:Add(activatedEvent)
	self._activatedEvent = activatedEvent
	self.Activated = activatedEvent.Event

	local swungEvent = Instance.new("BindableEvent")
	self._mainDump:Add(swungEvent)
	self._swungEvent = swungEvent
	self.Swung = swungEvent.Event

	local hitEvent = Instance.new("BindableEvent")
	self._mainDump:Add(hitEvent)
	self._hitEvent = hitEvent
	self.Hit = hitEvent.Event

	self._eventDump:Connect(self._tool.Activated, function()
		activatedEvent:Fire()
	end)

	self._eventDump:Connect(self._swingSignal.Event, function(swingType: string)
		swungEvent:Fire(swingType)
	end)

	self._eventDump:Connect(self._hitSignal.Event, function(humanoid: Humanoid, damage: number)
		hitEvent:Fire(humanoid, damage)
	end)

	self.Deactivated = self._tool.Deactivated
	self.Equipped = self._tool.Equipped
	self.Unequipped = self._tool.Unequipped
end

function MeleeTool:_rigController()
	local serverTemplate = script:FindFirstChild("MeleeToolServer")
	if serverTemplate then
		local clone = serverTemplate:Clone()
		clone.Parent = self._tool
		clone.Disabled = false
	else
		vwarn("MeleeToolServer template not found in", script:GetFullName())
	end

	local clientTemplate = script:FindFirstChild("MeleeToolClient")
	if clientTemplate then
		local clone = clientTemplate:Clone()
		clone.Parent = self._tool
		-- MeleeToolClient is a ClientComponent ModuleScript (no Disabled).
		if clone:IsA("BaseScript") then
			clone.Disabled = false
		end
	else
		vwarn("MeleeToolClient template not found in", script:GetFullName())
	end
end

function MeleeTool:_setupTool()
	local originalParent = self._body.Parent
	self:_rigHandle()
	self:_rigGrip()
	self:_rigAttributes()
	self:_rigRemotes()
	self:_rigAnimations()
	self:_rigSignals()
	self:_rigController()
	self._mainDump:Add(self._tool)
	StripCapabilityTag(self._tool)
	self._tool.Parent = originalParent
end

-- Public Methods

---Destroys class data, cleans up connections, and destroys tracked objects.
function MeleeTool:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self._mainDump:Destroy()
	for k, v in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function MeleeTool.build(body: Model, params: SetupParams)
	assert(body ~= nil, "must supply valid body Model")
	assert(body:IsA("Model"), "body must be a Model")
	assert(params ~= nil, "must supply params with GripPart")
	assert(params.GripPart ~= nil and (params.GripPart:IsA("BasePart") or params.GripPart:IsA("Model")), "params.GripPart must be a BasePart or Model")

	local resolved: SetupParams = params
	if resolved.DamageDealt == nil then resolved.DamageDealt = DEFAULT_DAMAGE_DEALT end
	if resolved.SwingDebounce == nil then resolved.SwingDebounce = DEFAULT_SWING_DEBOUNCE end
	if resolved.ChainSwingThreshold == nil then resolved.ChainSwingThreshold = DEFAULT_CHAIN_SWING_THRESHOLD end
	if resolved.ChainSwingEnabled == nil then resolved.ChainSwingEnabled = DEFAULT_CHAIN_SWING_ENABLED end
	if resolved.SwingSpeed == nil then resolved.SwingSpeed = DEFAULT_SWING_SPEED end
	if resolved.HitCheckInterval == nil then resolved.HitCheckInterval = DEFAULT_HIT_CHECK_INTERVAL end
	resolved.HitCheckInterval = math.max(1, math.floor(resolved.HitCheckInterval :: number))
	if resolved.Collisions == nil then resolved.Collisions = DEFAULT_COLLISIONS end
	if resolved.IdleAnimationId == nil then resolved.IdleAnimationId = DEFAULT_IDLE_ANIMATION_ID end
	if resolved.Swing1AnimationId == nil then resolved.Swing1AnimationId = DEFAULT_SWING1_ANIMATION_ID end
	if resolved.Swing2AnimationId == nil then resolved.Swing2AnimationId = DEFAULT_SWING2_ANIMATION_ID end
	if resolved.EquipAnimationId == nil then resolved.EquipAnimationId = DEFAULT_EQUIP_ANIMATION_ID end

	local self = setmetatable({}, MeleeTool)

	self._mainDump = Dumpster.new()
	self._eventDump = self._mainDump:Extend()

	self._body = body
	self._params = resolved
	self._tool = nil
	self._handle = nil
	self._handleCF = nil
	self._boundingSize = nil
	self._bodyParts = nil
	self._swingSignal = nil
	self._hitSignal = nil
	self._activatedEvent = nil
	self._swungEvent = nil
	self._hitEvent = nil

	self.Tool = nil
	self.Activated = nil
	self.Deactivated = nil
	self.Equipped = nil
	self.Unequipped = nil
	self.Swung = nil
	self.Hit = nil

	self:_setupTool()
	self.Tool = self._tool

	vprint(`Completed setup on {body} with params:`, self._params)
	return self
end

-- Types

export type SetupParams = {
	ChainSwingEnabled: boolean?,
	ChainSwingThreshold: number?,
	Collisions: boolean?,
	DamageDealt: number?,
	DamagePart: BasePart?,
	EquipAnimationId: (string | number)?,
	GripPart: BasePart | Model,
	HitCheckInterval: number?,
	IdleAnimationId: (string | number)?,
	Swing1AnimationId: (string | number)?,
	Swing2AnimationId: (string | number)?,
	SwingDebounce: number?,
	SwingSpeed: number?,
}

-- Return

return MeleeTool

--[[
	File: SimpleTool.luau
]]--

-- Root

local SimpleTool = {}
SimpleTool.__index = SimpleTool

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local Dumpster = require(FourD.Libs.Dumpster)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local StripCapabilityTag = require(FourD.Common.stripCapabilityTag)

-- Constants

local BIND_ATTRIBUTE_PREFIX = "Bind_"
local BIND_ID_PATTERN = "^[A-Za-z_][A-Za-z0-9_]*$"
local DEFAULT_COLLISIONS = false
local DEFAULT_USE_DEBOUNCE = 0.05
local KEY_DELIMITER = ";"
local BIND_BUTTON_PREFIX = "BindBtn_"
local BUTTON_DELIMITER = "|"
local VERBOSE_LOGGING = false

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function vwarns(...: any)
	warn(
		`[{script.Name}]`, ...,
		"\n" .. debug.traceback("Stack Trace:", 2)
	)
end

local function resolveAnimationId(id: (string | number)?): string?
	if id == nil then return nil end
	if typeof(id) == "number" then
		return `rbxassetid://{id}`
	end

	return id
end

local function resolveFrontBasePart(instance: PVInstance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart then return instance.PrimaryPart end
		for _, part in GeometryUtils.getInstanceParts(instance) do
			return part
		end
	end

	return nil
end

local function computeGripCFrame(frontWorldPos: Vector3, handleCF: CFrame): CFrame
	local worldForward = frontWorldPos - handleCF.Position
	local flat = Vector3.new(worldForward.X, 0, worldForward.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new()
	end

	local localForward = handleCF:VectorToObjectSpace(flat.Unit)
	local localFlat = Vector3.new(localForward.X, 0, localForward.Z)
	if localFlat.Magnitude < 1e-3 then
		return CFrame.new()
	end

	return CFrame.lookAt(Vector3.zero, localFlat.Unit)
end

local function getOwnerPlayer(tool: Tool): Player?
	local parent = tool.Parent
	if not parent then return nil end

	local player = Players:GetPlayerFromCharacter(parent)
	if player then return player end

	if parent:IsA("Backpack") then
		local backpackOwner = parent.Parent
		if backpackOwner and backpackOwner:IsA("Player") then
			return backpackOwner
		end
	end

	return nil
end

local function normalizeInputs(inputs: BindInput | { BindInput }): { EnumItem }
	local raw: { any }
	if typeof(inputs) == "EnumItem" then
		raw = { inputs }
	elseif typeof(inputs) == "table" then
		raw = inputs
	else
		error(`inputs must be an EnumItem or array of EnumItems, got {typeof(inputs)}`)
	end

	local normalized: { EnumItem } = {}
	for _, item in raw do
		assert(typeof(item) == "EnumItem", `inputs entry must be EnumItem, got {typeof(item)}`)
		assert(
			item.EnumType == Enum.KeyCode or item.EnumType == Enum.UserInputType,
			`inputs entry must be Enum.KeyCode or Enum.UserInputType, got {tostring(item.EnumType)}`
		)
		table.insert(normalized, item)
	end

	return normalized
end

local function writeBindAttribute(target: Instance, id: string, inputs: { EnumItem }, debounce: number)
	local serialized = { tostring(debounce) }
	for _, item in inputs do
		local enumTypeName = string.gsub(tostring(item.EnumType), "^Enum%.", "")
		table.insert(serialized, `{enumTypeName}.{item.Name}`)
	end
	target:SetAttribute(BIND_ATTRIBUTE_PREFIX .. id, table.concat(serialized, KEY_DELIMITER))
end

local function writeButtonAttribute(target: Instance, id: string, button: ContextActionButton?)
	local attrName = BIND_BUTTON_PREFIX .. id
	if button == nil then
		target:SetAttribute(attrName, nil)
		return
	end

	local title = button.Title or ""
	local image = button.Image or ""
	local positionStr = ""
	if button.Position then
		local p = button.Position
		positionStr = string.format(
			"%s,%s,%s,%s",
			tostring(p.X.Scale), tostring(p.X.Offset),
			tostring(p.Y.Scale), tostring(p.Y.Offset)
		)
	end

	target:SetAttribute(attrName, table.concat({ title, image, positionStr }, BUTTON_DELIMITER))
end

-- Private Methods

function SimpleTool:_rigHandle()
	local body: PVInstance = self._body
	local boundingCF: CFrame
	local boundingSize: Vector3
	if body:IsA("Model") then
		boundingCF, boundingSize = body:GetBoundingBox()
	elseif body:IsA("BasePart") then
		boundingCF = body.CFrame
		boundingSize = body.Size
	else
		error(`body must be Model or BasePart, got {body.ClassName}`)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = boundingSize
	handle.CFrame = boundingCF
	handle.Transparency = 1
	handle.CanCollide = self._params.Collisions
	handle.CanQuery = false
	handle.Anchored = false

	local tool = Instance.new("Tool")
	tool.Name = body.Name
	tool.RequiresHandle = true
	tool.CanBeDropped = true

	handle.Parent = tool
	body.Parent = tool

	for _, part in GeometryUtils.getInstanceParts(body) do
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		ConstructionHelpers.makeWeld(handle, part)
	end

	self._tool = tool
	self._handleCF = boundingCF
end

function SimpleTool:_rigGrip()
	local front = self._params.FrontFacingSchemaPart
	if not front then
		self._tool.Grip = CFrame.new()
		return
	end

	local frontPart = resolveFrontBasePart(front)
	if not frontPart then
		vwarn("FrontFacingSchemaPart has no BasePart; using identity grip")
		self._tool.Grip = CFrame.new()
		return
	end

	local frontWorldPos = GeometryUtils.getInstanceCFrame(front).Position
	self._tool.Grip = computeGripCFrame(frontWorldPos, self._handleCF)
end

function SimpleTool:_rigAttributes()
	local tool = self._tool
	tool:SetAttribute("UseDebounce", self._params.UseDebounce)
	tool:SetAttribute("IdleAnimationId", resolveAnimationId(self._params.IdleAnimationId))
	tool:SetAttribute("ActivateAnimationId", resolveAnimationId(self._params.ActivateAnimationId))
end

function SimpleTool:_rigActivatedSignal()
	local event = Instance.new("BindableEvent")
	self._mainDump:Add(event)
	self.Activated = event.Event

	self._eventDump:Connect(self._tool.Activated, function()
		local now = os.clock()
		if (now - self._lastUseTime) < self._params.UseDebounce then return end
		self._lastUseTime = now
		event:Fire()
	end)
end

function SimpleTool:_rigForwardedSignals()
	self.Deactivated = self._tool.Deactivated
	self.Equipped = self._tool.Equipped
	self.Unequipped = self._tool.Unequipped
end

function SimpleTool:_activateController()
	if self._controllerSpawned then return end

	local controllerScript = script:FindFirstChild("SimpleToolClient")
	if not controllerScript then
		vwarn("SimpleToolClient not found in", script:GetFullName())
		return
	end

	local clone = controllerScript:Clone()
	clone.Parent = self._tool
	-- SimpleToolClient is a ClientComponent ModuleScript now; only guard-enable
	-- if it is ever a real BaseScript.
	if clone:IsA("BaseScript") then
		clone.Disabled = false
	end
	self._controllerClone = clone
	self._controllerSpawned = true
end

function SimpleTool:_ensureCustomBindsRig()
	if self._customBindsRemote then return end

	self:_activateController()

	local remote = Instance.new("RemoteEvent")
	remote.Name = "CustomBindsRemote"
	remote.Parent = self._tool
	self._mainDump:Add(remote)
	self._customBindsRemote = remote

	self._eventDump:Connect(remote.OnServerEvent, function(player: Player, id: any)
		if typeof(id) ~= "string" then return end
		local bind = self._customBinds[id]
		if not bind then return end
		if getOwnerPlayer(self._tool) ~= player then return end

		local now = os.clock()
		if (now - bind.LastFire) < bind.Debounce then return end
		bind.LastFire = now

		local ok, err = pcall(bind.Callback, id)
		if not ok then vwarns(`bind callback for "{id}" errored:`, err) end
	end)
end

function SimpleTool:_setupTool()
	local originalParent = self._body.Parent
	self:_rigHandle()
	self:_rigGrip()
	self:_rigAttributes()
	self:_rigActivatedSignal()
	self:_rigForwardedSignals()
	if self._params.IdleAnimationId or self._params.ActivateAnimationId then
		self:_activateController()
	end
	self._mainDump:Add(self._tool)
	StripCapabilityTag(self._tool)
	self._tool.Parent = originalParent

	self._eventDump:Connect(self._tool.Destroying, function()
		if table.isfrozen(self) then return end
		self:Destroy()
	end)
end

-- Public Methods

---Registers a server-side callback fired when the owning player presses any of the bound inputs while equipped.
---Re-registering the same id replaces the prior bind.
function SimpleTool:RegisterBind(opts: BindOptions, callback: (string) -> ())
	assert(table.isfrozen(self) == false, "cannot register binds on a destroyed architect")
	assert(typeof(opts) == "table", "opts must be a table")
	assert(typeof(callback) == "function", "callback must be a function")

	local id = opts.Id
	assert(typeof(id) == "string" and id ~= "", "opts.Id must be a non-empty string")
	assert(string.match(id, BIND_ID_PATTERN) ~= nil, `opts.Id must match {BIND_ID_PATTERN} (letters, digits, underscore; no leading digit)`)

	local normalized = normalizeInputs(opts.Inputs)
	assert(#normalized > 0, "opts.Inputs must supply at least one input")

	local resolvedDebounce = opts.Debounce or 0
	assert(
		typeof(resolvedDebounce) == "number" and resolvedDebounce >= 0,
		"opts.Debounce must be a non-negative number"
	)

	local button = opts.Button
	if button ~= nil then
		assert(typeof(button) == "table", "opts.Button must be a table when provided")
		if button.Title ~= nil then
			assert(typeof(button.Title) == "string", "opts.Button.Title must be a string")
		end

		if button.Image ~= nil then
			assert(typeof(button.Image) == "string", "opts.Button.Image must be a string")
		end

		if button.Position ~= nil then
			assert(typeof(button.Position) == "UDim2", "opts.Button.Position must be a UDim2")
		end
	end

	self:_ensureCustomBindsRig()

	self._customBinds[id] = {
		Inputs = normalized,
		Callback = callback,
		Debounce = resolvedDebounce,
		LastFire = 0,
	}

	writeBindAttribute(self._controllerClone, id, normalized, resolvedDebounce)
	writeButtonAttribute(self._controllerClone, id, button)
end

---Destroys class data, cleans up connections, and destroys tracked objects.
function SimpleTool:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self._mainDump:Destroy()
	for k in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function SimpleTool.build(body: PVInstance, params: SetupParams?)
	assert(body ~= nil, "must supply valid body PVInstance")
	assert(body:IsA("Model") or body:IsA("BasePart"), "body must be a Model or BasePart")

	local resolved: SetupParams = params or {}
	if resolved.UseDebounce == nil then resolved.UseDebounce = DEFAULT_USE_DEBOUNCE end
	if resolved.Collisions == nil then resolved.Collisions = DEFAULT_COLLISIONS end

	local self = setmetatable({}, SimpleTool)

	self._mainDump = Dumpster.new()
	self._eventDump = self._mainDump:Extend()

	self._body = body
	self._params = resolved
	self._tool = nil
	self._handleCF = nil
	self._lastUseTime = 0
	self._customBinds = {}
	self._customBindsRemote = nil
	self._controllerClone = nil
	self._controllerSpawned = false

	self.Tool = nil
	self.Activated = nil
	self.Deactivated = nil
	self.Equipped = nil
	self.Unequipped = nil

	self:_setupTool()
	self.Tool = self._tool

	vprint(`Completed setup on {body} with params:`, self._params)
	return self
end

-- Types

export type BindInput = Enum.KeyCode | Enum.UserInputType

export type SetupParams = {
	FrontFacingSchemaPart: PVInstance?,
	IdleAnimationId: (string | number)?,
	ActivateAnimationId: (string | number)?,
	UseDebounce: number?,
	Collisions: boolean?,
}

export type ContextActionButton = {
	Title: string?,
	Image: string?,
	Position: UDim2?,
}

export type BindOptions = {
	Id: string,
	Inputs: BindInput | { BindInput },
	Debounce: number?,
	Button: ContextActionButton?,
}

-- Return

return SimpleTool

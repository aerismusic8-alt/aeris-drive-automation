--[[
	File: Spinnable/init.luau

	Spinnable behavior. Adds constant-rate rotation to any PVInstance assembly.
	The rotor spins about the pivot's RightVector axis at a configurable angular
	velocity using a server-physics HingeConstraint Motor. Because the engine
	replicates HingeConstraint state natively, no per-client renderer is needed.

	Public API:
		Spinnable.new(assembly, params) -> Spinnable
		Spinnable:SetRate / GetRate
		Spinnable:GetAssembly
		Spinnable:Destroy
]]--

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local SpinnableRoot = FourD.Behaviors.Spinnable
local Constants = require(SpinnableRoot.Common.Constants)
local Types = require(SpinnableRoot.Common.Types)

-- Root

local Spinnable = {}
Spinnable.__index = Spinnable

-- Local Functions

local function findAnyBasePart(pvInstance: PVInstance): BasePart?
	if pvInstance:IsA("BasePart") then
		return pvInstance
	end
	if pvInstance:IsA("Model") then
		if pvInstance.PrimaryPart then
			return pvInstance.PrimaryPart
		end
		for _, descendant in pvInstance:GetDescendants() do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end
	return nil
end

local function buildSynthPart(name: string, worldCFrame: CFrame, anchored: boolean): BasePart
	local synth = Instance.new("Part")
	synth.Name = name
	synth.Anchored = anchored
	synth.CanCollide = false
	synth.CanQuery = false
	synth.CanTouch = false
	synth.Massless = true
	synth.Transparency = 1
	synth.Size = Vector3.new(0.05, 0.05, 0.05)
	synth.CFrame = worldCFrame
	return synth
end

local function trySetServerOwner(part: BasePart)
	if RunService:IsServer() == false then return end
	if part.Anchored then return end
	pcall(part.SetNetworkOwner, part, nil)
end

-- Internal Methods

function Spinnable:_assertAlive()
	assert(table.isfrozen(self) == false, "cannot operate on a destroyed Spinnable")
end

-- Public Methods

---Returns the assembly passed to the constructor.
function Spinnable:GetAssembly(): PVInstance
	self:_assertAlive()
	return self._assembly
end

---Reads the current angular velocity in rad/s.
function Spinnable:GetRate(): number
	self:_assertAlive()
	return self._rate
end

---Sets the angular velocity. Positive = CCW around axis (right-hand rule).
---Pass 0 to stop. The rotor coasts to a halt based on MaxTorque and physics
---damping (effectively instant with default MaxTorque = math.huge).
function Spinnable:SetRate(rate: number)
	self:_assertAlive()
	self._rate = rate
	self._hinge.AngularVelocity = rate
end

---Drains the Dumpster, nils every field, and freezes self.
function Spinnable:Destroy()
	self:_assertAlive()
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
end

-- Constructor

---Creates a Spinnable on `assembly`. The spin axis is `params.PivotCFrame`'s
---RightVector in `assembly:GetPivot()`-local space. The assembly's as-built
---pose is treated as angle 0.
---
---Side effects: every BasePart in the assembly is unanchored and welded into
---one rigid body around a synthesized invisible rotor part. A HingeConstraint
---Motor drives the body at the requested rate.
function Spinnable.new(assembly: PVInstance, params: Types.SpinnableParams): Spinnable
	assert(params, "params is required")
	assert(params.PivotCFrame, "params.PivotCFrame is required")
	assert(params.Rate ~= nil, "params.Rate is required")
	assert(
		findAnyBasePart(assembly),
		`assembly "{assembly:GetFullName()}" must contain at least one BasePart`
	)

	local maxTorque = params.MaxTorque or Constants.DEFAULTS.MaxTorque
	local mainDump = Dumpster.new()
	mainDump:AttachTo(assembly)

	local axisWorldCFrame = assembly:GetPivot() * params.PivotCFrame

	-- Rotor synth: lives inside the assembly so it streams with it.
	local rotorParent: Instance = workspace
	if assembly:IsA("Model") then
		rotorParent = assembly
	elseif assembly.Parent then
		rotorParent = assembly.Parent
	end

	local rotorPart = buildSynthPart(Constants.ROTOR_PART_NAME, axisWorldCFrame, false)
	rotorPart.Parent = rotorParent
	mainDump:Add(rotorPart)

	-- Weld every BasePart in the assembly into one rigid body.
	ConstructionHelpers.weldAllParts(assembly, rotorPart)

	-- Anchor part: either welded to RelativeTo or Terrain-anchored.
	local anchorPart: BasePart
	if params.RelativeTo then
		local relPart = findAnyBasePart(params.RelativeTo)
		assert(relPart, "params.RelativeTo must contain at least one BasePart")

		local anchorParent: Instance = workspace
		if params.RelativeTo:IsA("Model") then
			anchorParent = params.RelativeTo
		elseif params.RelativeTo.Parent then
			anchorParent = params.RelativeTo.Parent
		end

		anchorPart = buildSynthPart(Constants.ANCHOR_PART_NAME, axisWorldCFrame, false)
		anchorPart.Parent = anchorParent

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchorPart
		weld.Part1 = relPart
		weld.Parent = anchorPart

		mainDump:AttachTo(params.RelativeTo)
	else
		anchorPart = buildSynthPart(Constants.ANCHOR_PART_NAME, axisWorldCFrame, true)
		anchorPart.Parent = workspace.Terrain
	end
	mainDump:Add(anchorPart)

	-- Attachments at the pivot, aligned so the hinge axis = RightVector.
	local rotorAttachment = Instance.new("Attachment")
	rotorAttachment.Name = "Spinnable_RotorAttachment"
	rotorAttachment.Parent = rotorPart
	rotorAttachment.WorldCFrame = axisWorldCFrame
	mainDump:Add(rotorAttachment)

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "Spinnable_AnchorAttachment"
	anchorAttachment.Parent = anchorPart
	anchorAttachment.WorldCFrame = axisWorldCFrame
	mainDump:Add(anchorAttachment)

	-- HingeConstraint Motor: the engine replicates this natively.
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = Constants.HINGE_NAME
	hinge.Attachment0 = anchorAttachment
	hinge.Attachment1 = rotorAttachment
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = maxTorque
	hinge.MotorMaxAcceleration = math.huge
	hinge.AngularVelocity = params.Rate
	hinge.Parent = rotorPart
	mainDump:Add(hinge)

	-- De-collide the spinning assembly from the RelativeTo body so adjacent
	-- geometry cannot jam the motor while preserving collisions with players
	-- and the rest of the world.
	if params.RelativeTo then
		local function getAllBaseParts(root: Instance): {BasePart}
			local parts = {}
			if root:IsA("BasePart") then table.insert(parts, root) end
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("BasePart") then table.insert(parts, descendant) end
			end
			return parts
		end

		local assemblyParts = getAllBaseParts(assembly)
		local seen = {}
		for _, part in assemblyParts do seen[part] = true end
		local index = 1
		while index <= #assemblyParts do
			for _, connected in assemblyParts[index]:GetConnectedParts(true) do
				if not seen[connected] then
					seen[connected] = true
					table.insert(assemblyParts, connected)
				end
			end
			index += 1
		end

		for _, assemblyPart in assemblyParts do
			for _, relativePart in getAllBaseParts(params.RelativeTo) do
				if assemblyPart ~= relativePart then
					local noCollision = Instance.new("NoCollisionConstraint")
					noCollision.Part0 = assemblyPart
					noCollision.Part1 = relativePart
					noCollision.Parent = rotorPart
					mainDump:Add(noCollision)
				end
			end
		end
	end

	trySetServerOwner(rotorPart)

	local self = setmetatable({
		_dumpster = mainDump,
		_assembly = assembly,
		_hinge = hinge,
		_rate = params.Rate,
	}, Spinnable)

	return self
end

-- Types

export type SpinnableParams = Types.SpinnableParams
export type Spinnable = typeof(Spinnable)

return Spinnable

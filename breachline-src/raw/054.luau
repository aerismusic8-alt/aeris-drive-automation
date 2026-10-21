 anything that should swing when bumped.

	Public API:
		Pendulumable.new(assembly, params) -> Pendulumable
		Pendulumable:GetAssembly
		Pendulumable:GetHinge
		Pendulumable:Destroy
]]--

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)

-- Root

local Pendulumable = {}
Pendulumable.__index = Pendulumable

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

function Pendulumable:_assertAlive()
	assert(table.isfrozen(self) == false, "cannot operate on a destroyed Pendulumable")
end

-- Public Methods

---Returns the assembly passed to the constructor.
function Pendulumable:GetAssembly(): PVInstance
	self:_assertAlive()
	return self._assembly
end

---Returns the HingeConstraint driving the swing.
function Pendulumable:GetHinge(): HingeConstraint
	self:_assertAlive()
	return self._hinge
end

---Drains the Dumpster, nils every field, and freezes self.
function Pendulumable:Destroy()
	self:_assertAlive()
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
end

-- Types

export type PendulumableParams = {
	---Hinge pivot in assembly:GetPivot()-local space. RightVector is the swing
	---axis; Position is the pivot point (where the chain/rope attaches to the
	---frame). Required.
	PivotCFrame: CFrame,
	---Optional PVInstance to swing from. When set, the pendulum follows this
	---body's motion (a sign hanging from a moving vehicle). When nil, the
	---pendulum hangs from world space.
	RelativeTo: PVInstance?,
	---Maximum swing angle in radians from rest. When set, limits are symmetric
	---(-SwingLimit to +SwingLimit). When nil, the pendulum swings freely 360
	---degrees (useful for things that can go over the top).
	SwingLimit: number?,
}

-- Constructor

---Creates a Pendulumable on `assembly`. The pivot (hang point) is
---`params.PivotCFrame` in `assembly:GetPivot()`-local space. The assembly
---hangs below the pivot and swings freely under gravity.
---
---Side effects: every BasePart in the assembly is unanchored and welded into
---one rigid body around a synthesized invisible rotor part. A free
---HingeConstraint connects the rotor to a fixed anchor at the pivot.
function Pendulumable.new(assembly: PVInstance, params: PendulumableParams): Pendulumable
	assert(params, "params is required")
	assert(params.PivotCFrame, "params.PivotCFrame is required")
	assert(
		findAnyBasePart(assembly),
		`assembly "{assembly:GetFullName()}" must contain at least one BasePart`
	)

	local mainDump = Dumpster.new()
	mainDump:AttachTo(assembly)

	local axisWorldCFrame = assembly:GetPivot() * params.PivotCFrame

	-- Rotor synth: lives inside the assembly.
	local rotorParent: Instance = workspace
	if assembly:IsA("Model") then
		rotorParent = assembly
	elseif assembly.Parent then
		rotorParent = assembly.Parent
	end

	local rotorPart = buildSynthPart("PendulumableRotor", axisWorldCFrame, false)
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

		anchorPart = buildSynthPart("PendulumableAnchor", axisWorldCFrame, false)
		anchorPart.Parent = anchorParent

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchorPart
		weld.Part1 = relPart
		weld.Parent = anchorPart

		mainDump:AttachTo(params.RelativeTo)
	else
		anchorPart = buildSynthPart("PendulumableAnchor", axisWorldCFrame, true)
		anchorPart.Parent = workspace.Terrain
	end
	mainDump:Add(anchorPart)

	-- Attachments at the pivot.
	local rotorAttachment = Instance.new("Attachment")
	rotorAttachment.Name = "Pendulumable_RotorAttachment"
	rotorAttachment.Parent = rotorPart
	rotorAttachment.WorldCFrame = axisWorldCFrame
	mainDump:Add(rotorAttachment)

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "Pendulumable_AnchorAttachment"
	anchorAttachment.Parent = anchorPart
	anchorAttachment.WorldCFrame = axisWorldCFrame
	mainDump:Add(anchorAttachment)

	-- Free HingeConstraint: no actuator, pure physics swing.
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "Pendulumable_HingeConstraint"
	hinge.Attachment0 = anchorAttachment
	hinge.Attachment1 = rotorAttachment
	hinge.ActuatorType = Enum.ActuatorType.None

	if params.SwingLimit then
		local lim = math.abs(params.SwingLimit)
		hinge.LimitsEnabled = true
		hinge.LowerAngle = -math.deg(lim)
		hinge.UpperAngle = math.deg(lim)
	else
		hinge.LimitsEnabled = false
	end

	hinge.Parent = rotorPart
	mainDump:Add(hinge)

	-- De-collide the swinging assembly from the RelativeTo body so it doesn't
	-- jam against the frame and refuse to swing.
	if params.RelativeTo then
		local function getAllBaseParts(root: Instance): {BasePart}
			local parts = {}
			if root:IsA("BasePart") then table.insert(parts, root) end
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then table.insert(parts, d) end
			end
			return parts
		end

		local assemblyParts = getAllBaseParts(assembly)
		local relativeParts = getAllBaseParts(params.RelativeTo)
		for _, ap in assemblyParts do
			for _, rp in relativeParts do
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = ap
				nc.Part1 = rp
				nc.Parent = rotorPart
				mainDump:Add(nc)
			end
		end
	end

	trySetServerOwner(rotorPart)

	local self = setmetatable({
		_dumpster = mainDump,
		_assembly = assembly,
		_hinge = hinge,
	}, Pendulumable)

	return self
end

export type Pendulumable = typeof(Pendulumable)

return Pendulumable

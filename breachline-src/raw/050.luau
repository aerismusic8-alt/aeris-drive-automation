 programmatic open/close via :SetOpen(bool).

	The PrismaticConstraint Servo replicates natively (the server sets
	TargetPosition and the engine moves the body). For "oscillate" mode a
	server-side Heartbeat connection drives the cycle. No per-client renderer
	is needed.

	Public API:
		Slidable.new(assembly, params) -> Slidable
		Slidable:SetOpen / IsOpen          (toggle mode)
		Slidable:SetSpeed / GetSpeed
		Slidable:GetAssembly
		Slidable:Destroy
]]--

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local SlidableRoot = FourD.Behaviors.Slidable
local Constants = require(SlidableRoot.Common.Constants)
local Types = require(SlidableRoot.Common.Types)

-- Root

local Slidable = {}
Slidable.__index = Slidable

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

-- Internal Methods

function Slidable:_assertAlive()
	assert(table.isfrozen(self) == false, "cannot operate on a destroyed Slidable")
end

-- Public Methods

---Returns the assembly passed to the constructor.
function Slidable:GetAssembly(): PVInstance
	self:_assertAlive()
	return self._assembly
end

---Returns whether the mover is in the "open" (extended) position.
---Only meaningful in "toggle" mode; in "oscillate" mode returns the last
---commanded state (which the oscillator overrides).
function Slidable:IsOpen(): boolean
	self:_assertAlive()
	return self._open
end

---Commands the mover to the open (true) or closed (false) position.
---In "toggle" mode this drives the servo to Travel or 0. In "oscillate" mode
---this is a no-op.
function Slidable:SetOpen(open: boolean)
	self:_assertAlive()
	if self._mode == "oscillate" then return end
	self._open = open
	self._prismatic.TargetPosition = if open then self._travel else 0
end

---Reads the current servo speed in studs/s.
function Slidable:GetSpeed(): number
	self:_assertAlive()
	return self._prismatic.Speed
end

---Sets the servo speed in studs/s.
function Slidable:SetSpeed(speed: number)
	self:_assertAlive()
	self._prismatic.Speed = speed
end

---Drains the Dumpster, nils every field, and freezes self.
function Slidable:Destroy()
	self:_assertAlive()
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
end

-- Constructor

---Creates a Slidable on `assembly`. The slide axis is `params.PivotCFrame`'s
---RightVector in `assembly:GetPivot()`-local space. The mover travels from 0
---to `params.Travel` studs along that axis.
---
---Side effects: every BasePart in the assembly is unanchored and welded into
---one rigid body around a synthesized invisible mover part. A
---PrismaticConstraint Servo drives the body along the axis.
function Slidable.new(assembly: PVInstance, params: Types.SlidableParams): Slidable
	assert(params, "params is required")
	assert(params.PivotCFrame, "params.PivotCFrame is required")
	assert(params.Travel ~= nil, "params.Travel is required")

	local mode = params.Mode or Constants.DEFAULTS.Mode
	if mode == "oscillate" then
		assert(params.Period ~= nil, "params.Period is required when Mode = \"oscillate\"")
	end

	assert(
		findAnyBasePart(assembly),
		`assembly "{assembly:GetFullName()}" must contain at least one BasePart`
	)

	local speed = params.Speed or Constants.DEFAULTS.Speed
	local maxForce = params.MaxForce or Constants.DEFAULTS.MaxForce
	local travel = params.Travel
	local period = params.Period

	local mainDump = Dumpster.new()
	mainDump:AttachTo(assembly)

	local axisWorldCFrame = assembly:GetPivot() * params.PivotCFrame

	-- Mover synth: lives inside the assembly so it streams with it.
	local moverParent: Instance = workspace
	if assembly:IsA("Model") then
		moverParent = assembly
	elseif assembly.Parent then
		moverParent = assembly.Parent
	end

	local moverPart = buildSynthPart(Constants.MOVER_PART_NAME, axisWorldCFrame, false)
	moverPart.Parent = moverParent
	mainDump:Add(moverPart)

	-- Weld every BasePart in the assembly into one rigid body.
	ConstructionHelpers.weldAllParts(assembly, moverPart)

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

	-- Attachments: PrismaticConstraint slides along Attachment0's Axis (its
	-- X-axis / RightVector in world space). axisWorldCFrame's RightVector is
	-- already the desired slide direction, so use it directly.
	local moverAttachment = Instance.new("Attachment")
	moverAttachment.Name = "Slidable_MoverAttachment"
	moverAttachment.Parent = moverPart
	moverAttachment.WorldCFrame = axisWorldCFrame
	mainDump:Add(moverAttachment)

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "Slidable_AnchorAttachment"
	anchorAttachment.Parent = anchorPart
	anchorAttachment.WorldCFrame = axisWorldCFrame
	mainDump:Add(anchorAttachment)

	-- PrismaticConstraint Servo.
	local prismatic = Instance.new("PrismaticConstraint")
	prismatic.Name = Constants.PRISMATIC_NAME
	prismatic.Attachment0 = anchorAttachment
	prismatic.Attachment1 = moverAttachment
	prismatic.ActuatorType = Enum.ActuatorType.Servo
	prismatic.LimitsEnabled = true
	prismatic.LowerLimit = 0
	prismatic.UpperLimit = travel
	prismatic.ServoMaxForce = maxForce
	prismatic.Speed = speed
	prismatic.TargetPosition = 0
	prismatic.Parent = moverPart
	mainDump:Add(prismatic)

	local self = setmetatable({
		_dumpster = mainDump,
		_assembly = assembly,
		_prismatic = prismatic,
		_mode = mode,
		_travel = travel,
		_open = false,
	}, Slidable)

	-- Oscillate mode: drive TargetPosition with a Heartbeat connection.
	if mode == "oscillate" then
		local startTime = workspace:GetServerTimeNow()
		local conn = RunService.Heartbeat:Connect(function()
			local elapsed = workspace:GetServerTimeNow() - startTime
			local phase = (elapsed % period) / period
			-- Triangle wave: 0
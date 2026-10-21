 clients each derive the current angle from a time-anchored
	attribute set on the wrapper and write Motor6D.C0 locally. That keeps
	motorized rotation perfectly smooth regardless of network distance and
	independent of the rotor assembly's mass.

	Public API:
		Hingeable.new(assembly, params) -> Hingeable
		Hingeable:SetMode / GetMode
		Hingeable:SetTargetAngle / GetTargetAngle  -- implies Servo
		Hingeable:SetRate / GetRate                -- implies Motor
		Hingeable:SetLimits / GetLimits            -- Free mode native limits
		Hingeable:Lock / Unlock
		Hingeable:GetAngle / GetAssembly
		Hingeable:Destroy
]]--

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local HingeableRoot = FourD.Behaviors.Hingeable
local Constants = require(HingeableRoot.Common.Constants)
local Types = require(HingeableRoot.Common.Types)
local ResolveAssembly = require(HingeableRoot.Common.ResolveAssembly)
local JointBuilder = require(HingeableRoot.Common.JointBuilder)

-- Root

local Hingeable = {}
Hingeable.__index = Hingeable

-- Constants

local VERBOSE_LOGGING = false

local CURRENT_JOINT_ID = "currentJoint"

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function trySetServerOwner(part: BasePart)
	if RunService:IsServer() == false then return end
	if part.Anchored then return end
	pcall(part.SetNetworkOwner, part, nil)
end


-- Internal Methods

function Hingeable:_assertAlive()
	assert(table.isfrozen(self) == false, "cannot operate on a destroyed Hingeable")
end

function Hingeable:_writeAttr(name: string, value: any)
	self._wrapper:SetAttribute(name, value)
end

function Hingeable:_publishStartSnapshot(angle: number)
	self._startAngle = angle
	self._startTime = workspace:GetServerTimeNow()
	self:_writeAttr(Constants.ATTR_START_ANGLE, angle)
	self:_writeAttr(Constants.ATTR_START_TIME, self._startTime)
end

function Hingeable:_clearCurrentJoint()
	if self._hinge then
		self._dumpster:Remove(CURRENT_JOINT_ID)
		self._hinge = nil
	end

	if self._motor then
		self._dumpster:Remove(CURRENT_JOINT_ID)
		self._motor = nil
	end

	self._motorRef.Value = nil
end

function Hingeable:_installJointForMode(mode: Types.HingeMode)
	if mode == Constants.MODE_FREE then
		if self._motor then
			self._dumpster:Remove(CURRENT_JOINT_ID)
			self._motor = nil
			self._motorRef.Value = nil
		end

		if self._hinge then
			return
		end

		local hinge = JointBuilder.buildHinge(
			self._resolved.rotorAttachment,
			self._resolved.anchorAttachment,
			self._lowerLimit,
			self._upperLimit
		)
		self._hinge = hinge
		self._dumpster:Add(hinge, CURRENT_JOINT_ID)
		trySetServerOwner(self._resolved.rotorPart)
		return
	end

	-- Motor / Servo / Locked share a single kinematic Motor6D. baseC0 / motorC1
	-- are construction-time constants (cached on self), so transitioning between
	-- the three kinematic modes is a no-op at the joint level.
	if self._hinge then
		self._dumpster:Remove(CURRENT_JOINT_ID)
		self._hinge = nil
	end

	if self._motor then
		return
	end

	local motor = JointBuilder.buildMotor6D(
		self._resolved.rotorPart,
		self._resolved.anchorPart,
		self._baseC0,
		self._motorC1
	)
	self._motor = motor
	self._motorRef.Value = motor
	self._dumpster:Add(motor, CURRENT_JOINT_ID)
end

-- Public Methods

---Returns the assembly passed to the constructor.
---@return assembly -- Caller-supplied PVInstance.
function Hingeable:GetAssembly(): PVInstance
	self:_assertAlive()
	return self._assembly
end

---Returns the tagged wrapper folder that carries the persisted pose attributes
---the client renderer reads. A capability can persist a pointer to this folder
---so a Play-time server component can retarget the hinge (write ATTR_TARGET_ANGLE)
---without holding the edit-time Hingeable object, which does not survive to Play.
---@return wrapper -- The `Hingeable_Wrapper` Folder.
function Hingeable:GetWrapper(): Folder
	self:_assertAlive()
	return self._wrapper
end

---Reads the rotor's current angle in radians. In `Free` mode this is the
---live `HingeConstraint.CurrentAngle`; in `Motor` mode it's derived from the
---last published StartAngle + rate * elapsed; in `Servo` it returns the last
---published StartAngle (server does not run the spring integration), which
---is an approximation that converges to the target; in `Locked` it returns
---the recorded LockedAngle.
---@return angle -- Current angle in radians.
function Hingeable:GetAngle(): number
	self:_assertAlive()

	local mode = self._mode
	if mode == Constants.MODE_FREE then
		if self._hinge then
			return math.rad(self._hinge.CurrentAngle)
		end

		return 0
	end

	if mode == Constants.MODE_MOTOR then
		local now = workspace:GetServerTimeNow()
		return self._startAngle + self._rate * (now - self._startTime)
	end

	if mode == Constants.MODE_LOCKED then
		return self._lockedAngle
	end

	-- Servo: approximation
	return self._startAngle
end

---Reads the current operating mode.
---@return mode -- Current `HingeMode`.
function Hingeable:GetMode(): Types.HingeMode
	self:_assertAlive()
	return self._mode
end

---Switches the operating mode. Tears down the current joint, installs the
---new one, and re-stamps the StartAngle/StartTime snapshot so clients
---continue smoothly from the current pose.
---@param mode -- Target `HingeMode`.
function Hingeable:SetMode(mode: Types.HingeMode)
	self:_assertAlive()
	if mode ~= Constants.MODE_FREE
		and mode ~= Constants.MODE_MOTOR
		and mode ~= Constants.MODE_SERVO
		and mode ~= Constants.MODE_LOCKED
	then
		error(`unknown HingeMode "{mode}"`)
	end

	if mode == self._mode then
		return
	end

	local snapshotAngle = self:GetAngle()
	self._mode = mode

	if mode == Constants.MODE_LOCKED then
		self._lockedAngle = snapshotAngle
		self:_writeAttr(Constants.ATTR_LOCKED_ANGLE, snapshotAngle)
	end

	self:_installJointForMode(mode)
	self:_writeAttr(Constants.ATTR_MODE, mode)
	self:_publishStartSnapshot(snapshotAngle)
	vprint("SetMode ->", mode, "@", snapshotAngle)
end

---Sets the target angle and switches to `Servo` mode if not already there.
---Optional `opts` overrides per-call MaxSpeed / Damping / Stiffness; missing
---fields keep the previous value (or the constructor default on first call).
---@param angle -- Desired final angle in radians.
---@param opts -- Optional per-call tuning. See `AngleTargetOpts`.
function Hingeable:SetTargetAngle(angle: number, opts: Types.AngleTargetOpts?)
	self:_assertAlive()

	if opts then
		if opts.MaxSpeed ~= nil then
			self._maxSpeed = opts.MaxSpeed
			self:_writeAttr(Constants.ATTR_MAX_SPEED, opts.MaxSpeed)
		end

		if opts.Damping ~= nil then
			self._damping = opts.Damping
			self:_writeAttr(Constants.ATTR_DAMPING, opts.Damping)
		end

		if opts.Stiffness ~= nil then
			self._stiffness = opts.Stiffness
			self:_writeAttr(Constants.ATTR_STIFFNESS, opts.Stiffness)
		end
	end

	self._targetAngle = angle
	self:_writeAttr(Constants.ATTR_TARGET_ANGLE, angle)

	if self._mode ~= Constants.MODE_SERVO then
		-- Mode switch: capture the current pose so the Servo integrator picks
		-- up from where the previous mode left off, then install the joint.
		local snapshotAngle = self:GetAngle()
		self._mode = Constants.MODE_SERVO
		self:_installJointForMode(Constants.MODE_SERVO)
		self:_writeAttr(Constants.ATTR_MODE, Constants.MODE_SERVO)
		self:_publishStartSnapshot(snapshotAngle)
	end
	-- When already in Servo, do not republish a snapshot. The client renderer
	-- keeps its integrated CurrentAngle as the new effective StartAngle, so a
	-- mid-swing retarget springs smoothly from the live pose toward the new
	-- TargetAngle rather than snapping back to the original StartAngle.
end

---Reads the current Servo target angle in radians.
---@return target -- Last value passed to SetTargetAngle (or 0).
function Hingeable:GetTargetAngle(): number
	self:_assertAlive()
	return self._targetAngle
end

---Sets the continuous angular velocity (rad/s) and switches to `Motor` mode
---if not already there.
---@param rate -- Angular velocity in radians per second; signed.
function Hingeable:SetRate(rate: number)
	self:_assertAlive()

	local snapshotAngle = self:GetAngle()
	self._rate = rate
	self:_writeAttr(Constants.ATTR_RATE, rate)

	if self._mode ~= Constants.MODE_MOTOR then
		self._mode = Constants.MODE_MOTOR
		self:_installJointForMode(Constants.MODE_MOTOR)
		self:_writeAttr(Constants.ATTR_MODE, Constants.MODE_MOTOR)
	end

	self:_publishStartSnapshot(snapshotAngle)
end

---Reads the current Motor rate in radians per second.
---@return rate -- Last value passed to SetRate (or 0).
function Hingeable:GetRate(): number
	self:_assertAlive()
	return self._rate
end

---Sets the swing limits used in `Free` mode. Pass nil to disable either side
---(both nil = unlimited 360 degree swing). Stored across mode changes and
---reapplied whenever the mode returns to `Free`.
---@param lower -- Lower limit in radians, or nil.
---@param upper -- Upper limit in radians, or nil.
function Hingeable:SetLimits(lower: number?, upper: number?)
	self:_assertAlive()
	self._lowerLimit = lower
	self._upperLimit = upper

	if self._mode == Constants.MODE_FREE and self._hinge then
		if lower ~= nil and upper ~= nil then
			self._hinge.LimitsEnabled = true
			self._hinge.LowerAngle = math.deg(lower)
			self._hinge.UpperAngle = math.deg(upper)
		else
			self._hinge.LimitsEnabled = false
		end
	end
end

---Reads the stored swing limits in radians.
---@return lower -- Stored lower limit, or nil.
---@return upper -- Stored upper limit, or nil.
function Hingeable:GetLimits(): (number?, number?)
	self:_assertAlive()
	return self._lowerLimit, self._upperLimit
end

---Freezes the rotor at its current angle without anchoring the assembly.
---Records the previous mode so `Unlock()` can return to it.
function Hingeable:Lock()
	self:_assertAlive()
	if self._mode == Constants.MODE_LOCKED then
		return
	end

	self._preLockMode = self._mode
	self:SetMode(Constants.MODE_LOCKED)
end

---Returns to the pre-`Lock()` mode (or `mode` if supplied). No-op if not
---currently locked.
---@param mode -- Optional override; defaults to the mode in effect before Lock().
function Hingeable:Unlock(mode: Types.HingeMode?)
	self:_assertAlive()
	if self._mode ~= Constants.MODE_LOCKED then
		return
	end

	local target = mode or self._preLockMode or Constants.MODE_FREE
	self:SetMode(target)
end

---Drains the class's Dumpster (joint, wrapper, attachments, synthesized
---anchor part when applicable), nils every field, and freezes `self`.
---Subsequent method calls fail `_assertAlive`.
function Hingeable:Destroy()
	self:_assertAlive()
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
	vprint("Destroyed Hingeable")
end

-- Constructor

---Creates a Hingeable on `assembly`. The pivot is given in
---`assembly:GetPivot()`-local space via `params.PivotCFrame` (RightVector =
---hinge axis). The assembly's as-built pose is treated as angle = 0.
---
---The assembly can be any PVInstance with at least one BasePart inside. No
---PrimaryPart is required. Side effect: every BasePart in the assembly is
---unanchored and welded into one rigid body around a synthesized invisible
---rotor part.
---@param assembly -- BasePart or Model containing at least one BasePart.
---@param params -- Required `PivotCFrame` plus optional mode/limits/rate/target. See `HingeableParams`.
---@return hingeable -- Mutable Hingeable instance.
function Hingeable.new(assembly: PVInstance, params: Types.HingeableParams): Hingeable
	assert(params, "params is required")
	assert(params.PivotCFrame, "params.PivotCFrame is required")

	local mode = params.Mode or Constants.DEFAULTS.Mode
	local mainDump = Dumpster.new()

	local resolved = ResolveAssembly(assembly, params, mainDump)

	local wrapper = Instance.new("Folder")
	wrapper.Name = Constants.WRAPPER_NAME
	wrapper.Parent = resolved.rotorPart
	mainDump:Add(wrapper)

	local rootRef = Instance.new("ObjectValue")
	rootRef.Name = Constants.ROOT_REF_VALUE_NAME
	rootRef.Value = resolved.rotorPart
	rootRef.Parent = wrapper

	local anchorRef = Instance.new("ObjectValue")
	anchorRef.Name = Constants.ANCHOR_REF_VALUE_NAME
	anchorRef.Value = resolved.anchorPart
	anchorRef.Parent = wrapper

	local motorRef = Instance.new("ObjectValue")
	motorRef.Name = Constants.MOTOR_REF_VALUE_NAME
	motorRef.Parent = wrapper

	local baseC0, motorC1 = JointBuilder.computePoseFrames(
		resolved.rotorPart,
		resolved.anchorPart,
		resolved.pivotLocalCFrame
	)
	wrapper:SetAttribute(Constants.ATTR_MODE, mode)
	wrapper:SetAttribute(Constants.ATTR_BASE_C0, baseC0)
	wrapper:SetAttribute(Constants.ATTR_START_ANGLE, 0)
	wrapper:SetAttribute(Constants.ATTR_START_TIME, workspace:GetServerTimeNow())
	wrapper:SetAttribute(Constants.ATTR_RATE, params.Rate or Constants.DEFAULTS.Rate)
	wrapper:SetAttribute(Constants.ATTR_TARGET_ANGLE, params.TargetAngle or Constants.DEFAULTS.TargetAngle)
	wrapper:SetAttribute(Constants.ATTR_MAX_SPEED, Constants.DEFAULTS.MaxSpeed)
	wrapper:SetAttribute(Constants.ATTR_DAMPING, Constants.DEFAULTS.Damping)
	wrapper:SetAttribute(Constants.ATTR_STIFFNESS, Constants.DEFAULTS.Stiffness)
	wrapper:SetAttribute(Constants.ATTR_LOCKED_ANGLE, 0)

	CollectionService:AddTag(wrapper, Constants.WRAPPER_TAG)

	local self = setmetatable({
		_dumpster = mainDump,
		_assembly = assembly,
		_resolved = resolved,
		_wrapper = wrapper,
		_motorRef = motorRef,
		_hinge = nil,
		_motor = nil,
		_baseC0 = baseC0,
		_motorC1 = motorC1,

		_mode = mode,
		_startAngle = 0,
		_startTime = wrapper:GetAttribute(Constants.ATTR_START_TIME),
		_rate = params.Rate or Constants.DEFAULTS.Rate,
		_targetAngle = params.TargetAngle or Constants.DEFAULTS.TargetAngle,
		_maxSpeed = Constants.DEFAULTS.MaxSpeed,
		_damping = Constants.DEFAULTS.Damping,
		_stiffness = Constants.DEFAULTS.Stiffness,
		_lowerLimit = params.LowerLimit,
		_upperLimit = params.UpperLimit,
		_lockedAngle = 0,
		_preLockMode = nil :: Types.HingeMode?,
	}, Hingeable)

	self:_installJointForMode(mode)

	vprint("Created Hingeable on", assembly:GetFullName(), "mode=", mode)
	return self
end

-- Types

export type HingeMode = Types.HingeMode
export type HingeableParams = Types.HingeableParams
export type AngleTargetOpts = Types.AngleTargetOpts
export type Hingeable = typeof(Hingeable)

-- Return

return Hingeable

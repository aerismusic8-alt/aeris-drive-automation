--[[
	File: Common/JointBuilder.luau

	Builds the two joint primitives a Hingeable can install:

		* `HingeConstraint`  -- physics-driven, used only in `Free` mode.
		* `Motor6D`          -- kinematic, used in `Motor` / `Servo` / `Locked`.
		                        Rotated by the per-client renderer.

	Mode swaps tear down whichever joint is currently installed and install the
	other; that lifecycle is owned by the caller (Hingeable.new + SetMode) via
	a Dumpster identifier slot.

	Pose derivations use `:GetPivot()` so the `root` and `anchor` arguments can
	be either a `BasePart` or a `Model` (with a `PrimaryPart`). Motor6D.C0
	itself must live in the anchor BasePart's CFrame-local frame -- that's a
	Roblox engine requirement -- so this module extracts the anchor's BasePart
	internally for the wiring step.
]]--

local JointBuilder = {}

-- Local Functions

local function resolveBasePart(pvInstance: PVInstance, label: string): BasePart
	if pvInstance:IsA("BasePart") then
		return pvInstance
	end

	if pvInstance:IsA("Model") then
		local primary = pvInstance.PrimaryPart
		assert(primary, `{label} Model "{pvInstance.Name}" requires a PrimaryPart`)
		return primary
	end

	error(`{label} must be a BasePart or Model (got {pvInstance.ClassName})`)
end

-- Public Functions

---Computes the Motor6D `C0` value at angle = 0 in the anchor BasePart's
---CFrame-local frame. World axis is derived from `root:GetPivot()` so Models
---with non-default WorldPivot resolve correctly. Anchor decomposition uses
---the anchor BasePart's CFrame (extracted from the PVInstance) because
---Motor6D.C0 lives in that frame by engine contract.
---@param root -- The rotor body. BasePart or Model.
---@param anchor -- The body the hinge pivots against. BasePart or Model.
---@param pivotLocalCFrame -- Pivot relative to `root:GetPivot()`; X axis = hinge axis.
---@return baseC0 -- Initial Motor6D.C0; the value rotated by `Rx(angle)` per frame on each client.
function JointBuilder.computeBaseC0(
	root: PVInstance,
	anchor: PVInstance,
	pivotLocalCFrame: CFrame
): CFrame
	local anchorBasePart = resolveBasePart(anchor, "anchor")
	local axisWorldCFrame = root:GetPivot() * pivotLocalCFrame
	return anchorBasePart.CFrame:Inverse() * axisWorldCFrame
end

---Builds an unactuated `HingeConstraint` between the two existing Attachments.
---Sets MotorMaxTorque / MotorMaxAcceleration / ServoMaxTorque to `math.huge`
---defensively even though they go unused at ActuatorType = None.
---@param rootAttachment -- Attachment on the rotor.
---@param anchorAttachment -- Attachment on the anchor part.
---@param lowerLimit -- Lower swing limit in radians, or nil. Both must be set for limits to apply.
---@param upperLimit -- Upper swing limit in radians, or nil.
---@return hinge -- The new HingeConstraint, parented under `rootAttachment.Parent`.
function JointBuilder.buildHinge(
	rootAttachment: Attachment,
	anchorAttachment: Attachment,
	lowerLimit: number?,
	upperLimit: number?
): HingeConstraint
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "Hingeable_HingeConstraint"
	hinge.Attachment0 = anchorAttachment
	hinge.Attachment1 = rootAttachment
	hinge.ActuatorType = Enum.ActuatorType.None
	hinge.MotorMaxTorque = math.huge
	hinge.MotorMaxAcceleration = math.huge
	hinge.ServoMaxTorque = math.huge

	if lowerLimit ~= nil and upperLimit ~= nil then
		hinge.LimitsEnabled = true
		hinge.LowerAngle = math.deg(lowerLimit)
		hinge.UpperAngle = math.deg(upperLimit)
	else
		hinge.LimitsEnabled = false
	end

	hinge.Parent = rootAttachment.Parent
	return hinge
end

---Computes the Motor6D `C0` and `C1` at angle 0. Both are constant across the
---rotor's lifetime because anchor and rotor remain rigidly welded to their
---respective parts, so callers should cache the result and reuse it across
---kinematic rebuilds rather than recomputing the inverses on every install.
---@param root -- The rotor body. BasePart or Model with PrimaryPart.
---@param anchor -- The body the rotor pivots against. BasePart or Model with PrimaryPart.
---@param pivotLocalCFrame -- Pivot relative to `root:GetPivot()`; X axis = hinge axis.
---@return baseC0 -- Initial Motor6D.C0 in anchor-BasePart-local space.
---@return motorC1 -- Initial Motor6D.C1 in rotor-BasePart-local space.
function JointBuilder.computePoseFrames(
	root: PVInstance,
	anchor: PVInstance,
	pivotLocalCFrame: CFrame
): (CFrame, CFrame)
	local rootBasePart = resolveBasePart(root, "root")
	local anchorBasePart = resolveBasePart(anchor, "anchor")
	local axisWorldCFrame = root:GetPivot() * pivotLocalCFrame
	local baseC0 = anchorBasePart.CFrame:Inverse() * axisWorldCFrame
	local motorC1 = rootBasePart.CFrame:Inverse() * axisWorldCFrame
	return baseC0, motorC1
end

---Builds a kinematic `Motor6D` between the anchor and the rotor using
---pre-computed pose frames. Rotating C0 around its X axis by theta rotates
---the rotor around the hinge axis by theta.
---@param rootBasePart -- The rotor BasePart (resolved by the caller).
---@param anchorBasePart -- The anchor BasePart (resolved by the caller).
---@param baseC0 -- Motor6D.C0 at angle 0; obtain via `computePoseFrames`.
---@param motorC1 -- Motor6D.C1 at angle 0; obtain via `computePoseFrames`.
---@return motor -- The new Motor6D, parented under `rootBasePart`.
function JointBuilder.buildMotor6D(
	rootBasePart: BasePart,
	anchorBasePart: BasePart,
	baseC0: CFrame,
	motorC1: CFrame
): Motor6D
	local motor = Instance.new("Motor6D")
	motor.Name = "Hingeable_Motor6D"
	motor.Part0 = anchorBasePart
	motor.Part1 = rootBasePart
	motor.C0 = baseC0
	motor.C1 = motorC1
	motor.Parent = rootBasePart

	return motor
end

return JointBuilder

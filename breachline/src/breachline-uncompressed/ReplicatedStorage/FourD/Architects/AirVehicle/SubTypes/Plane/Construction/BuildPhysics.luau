--[[
	File: BuildPhysics.luau
]]--

-- Root

local BuildPhysics = {}

-- Constants

local ATTACHMENT_NAME = "PlaneAttachment"
local SURGE_VELOCITY_NAME = "SurgeVelocity"
local LIFT_FORCE_NAME = "LiftForce"
local ORIENTATION_ANGULAR_VELOCITY_NAME = "OrientationAngularVelocity"

-- Public Functions

function BuildPhysics.rig(root: BasePart): PhysicsResult
	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = root

	local surgeVelocity = Instance.new("LinearVelocity")
	surgeVelocity.Name = SURGE_VELOCITY_NAME
	surgeVelocity.Attachment0 = attachment
	surgeVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	surgeVelocity.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	surgeVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	surgeVelocity.VectorVelocity = Vector3.zero
	surgeVelocity.Enabled = false
	surgeVelocity.Parent = root

	local liftForce = Instance.new("VectorForce")
	liftForce.Name = LIFT_FORCE_NAME
	liftForce.ApplyAtCenterOfMass = true
	liftForce.Attachment0 = attachment
	liftForce.Force = Vector3.zero
	liftForce.RelativeTo = Enum.ActuatorRelativeTo.World
	liftForce.Enabled = false
	liftForce.Parent = root

	local orientationAngularVelocity = Instance.new("AngularVelocity")
	orientationAngularVelocity.Name = ORIENTATION_ANGULAR_VELOCITY_NAME
	orientationAngularVelocity.Attachment0 = attachment
	orientationAngularVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	orientationAngularVelocity.MaxTorque = math.huge
	orientationAngularVelocity.ReactionTorqueEnabled = false
	orientationAngularVelocity.AngularVelocity = Vector3.zero
	orientationAngularVelocity.Enabled = false
	orientationAngularVelocity.Parent = root

	return {
		Attachment = attachment,
		SurgeVelocity = surgeVelocity,
		LiftForce = liftForce,
		OrientationAngularVelocity = orientationAngularVelocity,
	}
end

-- Types

export type PhysicsResult = {
	Attachment: Attachment,
	SurgeVelocity: LinearVelocity,
	LiftForce: VectorForce,
	OrientationAngularVelocity: AngularVelocity,
}

-- Return

return BuildPhysics

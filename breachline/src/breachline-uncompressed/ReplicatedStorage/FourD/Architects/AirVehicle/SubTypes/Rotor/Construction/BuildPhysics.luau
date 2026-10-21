--[[
	File: BuildPhysics.luau
]]--

-- Root

local BuildPhysics = {}

-- Constants

local ATTACHMENT_NAME = "RotorAttachment"
local BODY_VELOCITY_NAME = "BodyVelocity"
local BODY_ORIENTATION_NAME = "BodyOrientation"
local ORIENTATION_RESPONSIVENESS = 50
local ORIENTATION_MAX_TORQUE = 1e6

-- Public Functions

function BuildPhysics.rig(root: BasePart): PhysicsResult
	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = root

	local bodyVelocity = Instance.new("LinearVelocity")
	bodyVelocity.Name = BODY_VELOCITY_NAME
	bodyVelocity.Attachment0 = attachment
	bodyVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	bodyVelocity.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	bodyVelocity.VectorVelocity = Vector3.zero
	bodyVelocity.Enabled = false
	bodyVelocity.Parent = root

	local bodyOrientation = Instance.new("AlignOrientation")
	bodyOrientation.Name = BODY_ORIENTATION_NAME
	bodyOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	bodyOrientation.Attachment0 = attachment
	-- Hold the commanded heading rigidly. A rotorcraft's main rotor imparts a
	-- steady reaction torque to the fuselage (no tail rotor models it), which a
	-- spring-style AlignOrientation only damps -- the body creeps in yaw at idle
	-- even with no input. Rigid alignment pins the fuselage to the heading the
	-- controller integrates (see Physics.luau headingYaw), so idle holds still
	-- and a turn follows the commanded rate. Responsiveness/MaxTorque are
	-- retained for documentation but are inert while rigid.
	bodyOrientation.RigidityEnabled = true
	bodyOrientation.Responsiveness = ORIENTATION_RESPONSIVENESS
	bodyOrientation.MaxTorque = ORIENTATION_MAX_TORQUE
	bodyOrientation.ReactionTorqueEnabled = false
	bodyOrientation.CFrame = root.CFrame
	bodyOrientation.Enabled = false
	bodyOrientation.Parent = root

	return {
		Attachment = attachment,
		BodyVelocity = bodyVelocity,
		BodyOrientation = bodyOrientation,
	}
end

-- Types

export type PhysicsResult = {
	Attachment: Attachment,
	BodyVelocity: LinearVelocity,
	BodyOrientation: AlignOrientation,
}

-- Return

return BuildPhysics

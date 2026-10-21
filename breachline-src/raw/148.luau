--[[
	File: BuildPrompt.luau
]]--

-- Root

local BuildPrompt = {}

-- Constants

local MOUNT_PROMPT_NAME = "MountPrompt"
local MOUNT_PROMPT_DEFAULT_OBJECT_TEXT = "Vehicle"
local MOUNT_PROMPT_DEFAULT_ACTION_TEXT = "Pilot"
local MOUNT_PROMPT_DISTANCE_MULT = 1.5
-- Body-size-scaled distance goes tiny for compact craft (a jetpack's
-- min(X,Z) is ~1-2 studs), and the prompt anchors to the assembly root at
-- ground level -- well below the approaching character's torso -- so the
-- measured 3D distance stays above a small radius and the prompt never shows.
-- Floor the radius so every craft is reachable; large bodies keep their
-- larger computed value.
local MOUNT_PROMPT_MIN_DISTANCE = 8
local PROXIMITY_PROMPT_KEYBOARD = Enum.KeyCode.E
local PROXIMITY_PROMPT_GAMEPAD = Enum.KeyCode.ButtonX

-- Public Functions

function BuildPrompt.rig(
	root: BasePart,
	bodySize: Vector3,
	actionText: string?,
	objectText: string?,
	distanceMult: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = MOUNT_PROMPT_NAME
	prompt.ActionText = actionText or MOUNT_PROMPT_DEFAULT_ACTION_TEXT
	prompt.ObjectText = objectText or MOUNT_PROMPT_DEFAULT_OBJECT_TEXT
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(
		math.min(bodySize.X, bodySize.Z) * (distanceMult or MOUNT_PROMPT_DISTANCE_MULT),
		MOUNT_PROMPT_MIN_DISTANCE
	)
	prompt.KeyboardKeyCode = PROXIMITY_PROMPT_KEYBOARD
	prompt.GamepadKeyCode = PROXIMITY_PROMPT_GAMEPAD
	prompt.Enabled = true
	prompt.Parent = root

	return prompt
end

-- Return

return BuildPrompt


local ROTATION_SPEED_TOUCH = Vector2.new(1, 0.66) * math.rad(1) -- (rad/s)

local enabled = false
local connections = {}
local sunkTouchInputs = {}

local touchMovement = Vector2.zero

local function resetInput()
	touchMovement = Vector2.zero
end

-- Adjust the touch sensitivity so that sensitivity is reduced when swiping away
-- from the horizon line. Sensitivity is not adjusted when swiping toward it.
-- This function was pulled from the default camera scripts.
local function adjustTouchPitchSensitivity(delta: Vector2): Vector2
	local camera = Workspace.CurrentCamera

	if not camera then
		return delta
	end

	-- Get the camera pitch in world space
	local pitch = camera.CFrame:ToEulerAnglesYXZ()

	if delta.Y * pitch >= 0 then
		-- Do not reduce sensitivity when pitching towards the horizon
		return delta
	end

	-- Set up a curve f() to fit:
	-- f(0) = 1
	-- f(
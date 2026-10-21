--[[
	File: InputConstants.luau

	Shared input + camera + attribute constants used by both Plane and Rotor
	client controllers. SubType-specific keys (per-vehicle action names, control
	mappings, flight tunables) live in each SubType's `Scripts/Constants.luau`.
]]--

local InputConstants = {
	-- Input deadzones
	GAMEPAD_DEADZONE = 0.1,
	MOBILE_INPUT_DEADZONE = 0.1,

	-- Exit input
	EXIT_KEYBOARD_KEY = Enum.KeyCode.E,
	EXIT_GAMEPAD_KEY = Enum.KeyCode.ButtonX,

	-- Free rotate
	FREE_ROTATE_GAMEPAD_KEY = Enum.KeyCode.ButtonR3,
	FREE_ROTATE_SENSITIVITY_YAW = 0.01,
	FREE_ROTATE_SENSITIVITY_PITCH = 0.01,
	FREE_ROTATE_GAMEPAD_RATE_YAW = 2.5,
	FREE_ROTATE_GAMEPAD_RATE_PITCH = 1.8,
	FREE_ROTATE_MAX_YAW_DEGREES = 180,
	FREE_ROTATE_MAX_PITCH_DEGREES = 60,
	FREE_ROTATE_RETURN_RATE = 4,
	FREE_ROTATE_INPUT_SMOOTH_RATE = 18,

	-- Camera smoothing
	CAMERA_YAW_SMOOTH_RATE = 4.0,
	CAMERA_PITCH_SMOOTH_RATE = 3.0,

	-- Mouse wheel zoom
	MOUSE_WHEEL_ZOOM_FRACTION = 0.10,

	-- Input categories
	INPUT_KEYBOARD = "KeyboardAndMouse",
	INPUT_GAMEPAD = "Gamepad",
	INPUT_TOUCH = "Touch",
	INPUT_UNKNOWN = "Unknown",

	-- Attribute names
	PILOT_USER_ID_ATTRIBUTE = "PilotUserId",
}

return InputConstants
s
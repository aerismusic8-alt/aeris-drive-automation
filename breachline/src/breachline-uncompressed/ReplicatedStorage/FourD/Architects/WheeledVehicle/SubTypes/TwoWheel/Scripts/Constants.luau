local Constants = {
	-- Attribute used to determine the owner of the car
	CAR_OWNER_ATTRIBUTE = "owner",
	-- Attributes used to get/set input values
	NITRO_INPUT_ATTRIBUTE = "nitroInput",
	NITRO_USABLE_ATTRIBUTE = "nitroUsable",
	MUTE_ENGINE_SOUND_ATTRIBUTE = "muteEngineSound",
	HAND_BRAKE_INPUT_ATTRIBUTE = "handBrakeInput",
	THROTTLE_INPUT_ATTRIBUTE = "throttleInput",
	STEERING_INPUT_ATTRIBUTE = "steeringInput",
	-- Attributes prefixed with _ are used to share data easily between systems and not intended to be edited
	ENGINE_SPEED_ATTRIBUTE = "_speed",
	ENGINE_NITRO_ATTRIBUTE = "_nitro",
	NITRO_ENABLED_ATTRIBUTE = "_nitroEnabled",
	-- Pixel size under which a screen is considered 'small'. This is the same threshold used by the default touch UI.
	UI_SMALL_SCREEN_THRESHOLD = 500,
	-- Amount to scale the UI when on a small screen
	UI_SMALL_SCREEN_SCALE = 0.8,
	-- Gamepad input constants
	GAMEPAD_ENTER_KEY_CODE_ATTRIBUTE = "gamepadEnterKeyCode",
	GAMEPAD_CYCLE_CAMERA_MODE_BIND_NAME = "CarGamepadCycleCameraMode",
	GAMEPAD_EXIT_BIND_NAME = "CarGamepadExit",
	GAMEPAD_NITRO_BIND_NAME = "CarGamepadNitro",
	-- Keyboard and mouse input constants
	KEYBOARD_ENTER_KEY_CODE_ATTRIBUTE = "keyboardEnterKeyCode",
	KEYBOARD_CYCLE_CAMERA_MODE_BIND_NAME = "CarKeyboardCycleCameraMode",
	KEYBOARD_EXIT_BIND_NAME = "CarKeyboardExit",
	KEYBOARD_NITRO_BIND_NAME = "CarKeyboardNitro",
	-- Touch input constants
	TOUCH_CYCLE_CAMERA_MODE_BIND_NAME = "CarTouchCycleCameraMode",
	TOUCH_EXIT_BIND_NAME = "CarTouchExit",
	TOUCH_NITRO_BIND_NAME = "CarTouchNitro",
	TOUCH_INPUT_OBJECT_IGNORE_TAG = "IgnoreInput",
}

return Constants

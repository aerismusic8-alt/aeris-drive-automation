return {
	Id = "Trackable",
	ActionPrefix = "Trackable",
	Binds = {
		{
			Id = "Exit",
			Description = "Exit",
			Keyboard = Enum.KeyCode.E,
			Gamepad = Enum.KeyCode.ButtonX,
			OverrideAttribute = { Keyboard = "keyboardExitKeyCode", Gamepad = "gamepadExitKeyCode" },
		},
	},
}

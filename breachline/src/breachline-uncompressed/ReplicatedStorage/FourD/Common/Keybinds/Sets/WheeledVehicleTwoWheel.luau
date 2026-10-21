return {
	Id = "WheeledVehicle.TwoWheel",
	ActionPrefix = "WheeledTwoWheel",
	Binds = {
		{
			Id = "Exit",
			Description = "Exit",
			Keyboard = Enum.KeyCode.E,
			Gamepad = Enum.KeyCode.ButtonX,
			OverrideAttribute = { Keyboard = "keyboardExitKeyCode", Gamepad = "gamepadExitKeyCode" }
		},
		{
			Id = "Nitro",
			Description = "Nitro",
			Keyboard = Enum.KeyCode.N,
			Gamepad = Enum.KeyCode.ButtonR2,
			OverrideAttribute = { Keyboard = "keyboardNitroKeyCode", Gamepad = "gamepadNitroKeyCode" }
		},
		{
			Id = "Jump",
			Description = "Jump",
			Keyboard = Enum.KeyCode.Space,
			Gamepad = Enum.KeyCode.ButtonA,
		},
	},
}

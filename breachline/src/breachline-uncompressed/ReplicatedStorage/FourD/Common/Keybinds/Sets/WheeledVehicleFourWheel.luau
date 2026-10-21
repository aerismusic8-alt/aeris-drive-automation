return {
	Id = "WheeledVehicle.FourWheel",
	ActionPrefix = "WheeledFourWheel",
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
			Keyboard = Enum.KeyCode.LeftShift,
			Gamepad = Enum.KeyCode.ButtonR2,
			OverrideAttribute = { Keyboard = "keyboardNitroKeyCode", Gamepad = "gamepadNitroKeyCode" }
		},
		{
			Id = "HandBrake",
			Description = "Handbrake",
			Keyboard = Enum.KeyCode.Space,
			Gamepad = Enum.KeyCode.ButtonA,
			OverrideAttribute = { Keyboard = "keyboardHandBrakeKeyCode", Gamepad = "gamepadHandBrakeKeyCode" }
		},
	},
}

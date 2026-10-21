return {
	Id = "AirVehicle.Jetpack",
	ActionPrefix = "Jetpack",
	Binds = {
		{
			Id = "Exit",
			Description = "Exit",
			Keyboard = Enum.KeyCode.E,
			Gamepad = Enum.KeyCode.ButtonX
		},
		{
			Id = "Forward",
			Description = "Forward",
			Keyboard = Enum.KeyCode.W,
			Category = "Movement"
		},
		{
			Id = "Reverse",
			Description = "Reverse",
			Keyboard = Enum.KeyCode.S,
			Category = "Movement"
		},
		{
			Id = "StrafeLeft",
			Description = "Strafe Left",
			Keyboard = Enum.KeyCode.A,
			Category = "Movement"
		},
		{
			Id = "StrafeRight",
			Description = "Strafe Right",
			Keyboard = Enum.KeyCode.D,
			Category = "Movement"
		},
		{
			Id = "Ascend",
			Description = "Ascend",
			Keyboard = Enum.KeyCode.Space,
			Gamepad = Enum.KeyCode.ButtonA,
			Category = "Movement"
		},
		{
			Id = "Descend",
			Description = "Descend",
			Keyboard = Enum.KeyCode.LeftControl,
			Gamepad = Enum.KeyCode.ButtonB,
			Category = "Movement"
		},
	},
}

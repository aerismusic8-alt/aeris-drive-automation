return {
	Id = "AirVehicle.Rotor",
	ActionPrefix = "Rotor",
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
			Category = "Movement"
		},
		{
			Id = "Descend",
			Description = "Descend",
			Keyboard = Enum.KeyCode.LeftControl,
			Category = "Movement"
		},
		{
			Id = "SwapSeat",
			Description = "Swap Pilot/Gunner",
			Keyboard = Enum.KeyCode.F,
			Gamepad = Enum.KeyCode.DPadLeft,
			Touch = { Face = "Right", Icon = "Swap" },
		},
	},
}

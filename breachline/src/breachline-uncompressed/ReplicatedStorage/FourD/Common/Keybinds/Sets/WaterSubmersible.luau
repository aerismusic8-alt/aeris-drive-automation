return {
	Id = "WaterSubmersible",
	ActionPrefix = "WaterSubmersible",
	Binds = {
		{
			Id = "Throttle",
			Description = "Throttle",
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
			Id = "SteerLeft",
			Description = "Steer Left",
			Keyboard = Enum.KeyCode.A,
			Category = "Movement"
		},
		{
			Id = "SteerRight",
			Description = "Steer Right",
			Keyboard = Enum.KeyCode.D,
			Category = "Movement"
		},
		{
			Id = "Exit",
			Description = "Exit",
			Keyboard = Enum.KeyCode.E,
			Gamepad = Enum.KeyCode.ButtonY,
		},
		{
			Id = "IncreaseDepth",
			Description = "Dive",
			Keyboard = Enum.KeyCode.LeftControl,
			Gamepad = Enum.KeyCode.ButtonB,
			Category = "Depth"
		},
		{
			Id = "DecreaseDepth",
			Description = "Surface",
			Keyboard = Enum.KeyCode.Space,
			Gamepad = Enum.KeyCode.ButtonA,
			Category = "Depth"
		},
	},
}

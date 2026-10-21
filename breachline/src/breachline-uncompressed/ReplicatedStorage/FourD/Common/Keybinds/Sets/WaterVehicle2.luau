return {
	Id = "WaterVehicle2",
	ActionPrefix = "WaterVehicle2",
	Binds = {
		{
			Id = "Exit",
			Description = "Exit",
			Keyboard = Enum.KeyCode.E,
			Gamepad = Enum.KeyCode.ButtonY,
		},
		{
			Id = "ThrottleUp",
			Description = "Throttle Forward",
			Keyboard = Enum.KeyCode.W,
			Gamepad = Enum.KeyCode.ButtonA,
			Category = "Throttle",
		},
		{
			Id = "ThrottleDown",
			Description = "Reverse",
			Keyboard = Enum.KeyCode.S,
			Gamepad = Enum.KeyCode.ButtonB,
			Category = "Throttle",
		},
		{
			Id = "SteerLeft",
			Description = "Steer Left",
			Keyboard = Enum.KeyCode.A,
			Category = "Steering",
		},
		{
			Id = "SteerRight",
			Description = "Steer Right",
			Keyboard = Enum.KeyCode.D,
			Category = "Steering",
		},
	},
}

return {
	Id = "AirVehicle.Plane",
	ActionPrefix = "Plane",
	Binds = {
		{
			Id = "Exit",
			Description = "Exit",
			Keyboard = Enum.KeyCode.E,
			Gamepad = Enum.KeyCode.ButtonX
		},
		{
			Id = "ThrottleUp",
			Description = "Throttle Up",
			Keyboard = Enum.KeyCode.W,
			Gamepad = Enum.KeyCode.ButtonA,
			Category = "Throttle"
		},
		{
			Id = "ThrottleDown",
			Description = "Throttle Down",
			Keyboard = Enum.KeyCode.S,
			Gamepad = Enum.KeyCode.ButtonB,
			Category = "Throttle"
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

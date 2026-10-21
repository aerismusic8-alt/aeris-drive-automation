return {
	Id = "Gunnable.Turret",
	ActionPrefix = "GunnableTurret",
	Binds = {
		{
			Id = "EnterGunner",
			Description = "Mount Turret",
			Keyboard = Enum.KeyCode.E
		},
		{
			Id = "ExitGunner",
			Description = "Exit Turret",
			Keyboard = Enum.KeyCode.E,
			Gamepad = Enum.KeyCode.ButtonX
		},
		{
			Id = "RoleSwap",
			Description = "Swap Pilot/Gunner",
			Keyboard = Enum.KeyCode.F,
			Gamepad = Enum.KeyCode.ButtonY
		},
	},
}

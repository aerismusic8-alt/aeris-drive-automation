return {
	Id = "Firearm2",
	ActionPrefix = "Firearm2",
	Binds = {
		{
			Id = "Fire",
			Description = "Fire",
			Keyboard = Enum.UserInputType.MouseButton1,
			Gamepad = Enum.KeyCode.ButtonR2,
			Category = "Combat",
			Touch = { Face = "Left", Icon = "Fire" },
		},
		{
			Id = "Aim",
			Description = "Aim",
			Keyboard = Enum.UserInputType.MouseButton2,
			Gamepad = Enum.KeyCode.ButtonL2,
			Category = "Combat",
			Touch = { Face = "Up", Icon = "Aim" },
		},
		{
			Id = "Reload",
			Description = "Reload",
			Keyboard = Enum.KeyCode.R,
			Gamepad = Enum.KeyCode.ButtonX,
			Category = "Combat",
			Touch = { Face = "Down", Icon = "Reload" },
		},
	},
}

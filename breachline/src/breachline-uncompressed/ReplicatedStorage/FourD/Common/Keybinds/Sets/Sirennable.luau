return {
	Id = "Sirennable",
	ActionPrefix = "Sirennable",
	Binds = {
		{
			Id = "Toggle",
			Description = "Toggle Siren",
			Keyboard = Enum.KeyCode.V,
			OverrideAttribute = { Keyboard = "sirenToggleKey" },
			Touch = { Face = "Up", Icon = "Siren" },
		},
	},
}

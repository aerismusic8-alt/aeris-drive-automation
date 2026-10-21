return {
	Id = "Taxi6",
	ActionPrefix = "Taxi6",
	Binds = {
		{
			Id = "Toggle",
			Description = "Toggle Taxi Sign",
			Keyboard = Enum.KeyCode.T,
			OverrideAttribute = { Keyboard = "taxiToggleKey" },
			Touch = { Face = "Up", Icon = "TaxiSign" },
		},
	},
}

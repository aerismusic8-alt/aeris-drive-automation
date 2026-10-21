return {
	Id = "SchoolBus6",
	ActionPrefix = "SchoolBus6",
	Binds = {
		{
			Id = "ToggleStopSign",
			Description = "Toggle Stop Sign",
			Keyboard = Enum.KeyCode.T,
			Gamepad = Enum.KeyCode.DPadLeft,
			OverrideAttribute = { Keyboard = "stopSignToggleKey" },
			Touch = { Face = "Up", Icon = "StopSign" },
		},
	},
}

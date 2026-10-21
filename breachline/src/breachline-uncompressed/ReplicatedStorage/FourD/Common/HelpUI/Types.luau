--[[
	File: HelpUI/Types.luau

	Shared type exports for the HelpUI system. A state is an ordered list of
	sources; each source contributes one or more rows to the overlay.
]]--

export type SourceSet = {
	Type: "Set",
	SetId: string,
	Filter: { string }?,
}

export type SourceManual = {
	Type: "Manual",
	Id: string,
	Keyboard: string?,
	Gamepad: string?,
	Description: string,
}

export type Source = SourceSet | SourceManual

export type StateDefinition = {
	Sources: { Source },
}

return {}

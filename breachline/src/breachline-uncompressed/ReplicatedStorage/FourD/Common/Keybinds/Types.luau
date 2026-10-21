--!strict

export type BindKey = Enum.KeyCode | Enum.UserInputType

export type OverrideAttribute = {
	Keyboard: string?,
	Gamepad: string?,
}

export type TouchFace = "Up" | "Right" | "Down" | "Left" | "Exit"

export type TouchSpec = {
	Face: TouchFace,
	Icon: string?,
}

export type BindSpec = {
	Id: string,
	Description: string,
	Keyboard: BindKey?,
	Gamepad: Enum.KeyCode?,
	Category: string?,
	OverrideAttribute: OverrideAttribute?,
	Touch: TouchSpec?,
}

export type BindSet = {
	Id: string,
	ActionPrefix: string,
	Binds: { BindSpec },
}

export type ResolvedBind = {
	Id: string,
	Description: string,
	Category: string?,
	Keyboard: BindKey?,
	Gamepad: Enum.KeyCode?,
	Touch: TouchSpec?,
}

export type ResolvedBindSet = {
	Id: string,
	ActionPrefix: string,
	Binds: { ResolvedBind },
}

export type ActionHandler = (state: Enum.UserInputState, input: InputObject) -> Enum.ContextActionResult?

export type BindActionsOpts = {
	Priority: number?,
	CreateTouchButton: boolean?,
	TouchPriority: number?,
	HideJump: boolean?,
	--- Replaces Roblox's Jump button with the standard Right-face tool action.
	TouchJump: boolean?,
	BlockTools: boolean?,
	--- Creates only the shared touch action; desktop remains owned elsewhere
	--- (for example, by Tool.Activated).
	TouchOnly: boolean?,
	-- Appended to every ContextActionService action name this call binds. Action
	-- names are otherwise just ActionPrefix .. Id, so two live instances of the same
	-- behaviour collide: the second BindAction replaces the first's handler, and the
	-- first UnbindAction removes the action for both. Pass something unique per
	-- instance when more than one can be bound at a time.
	ActionNameSuffix: string?,
}

export type ApplyToHelpScreenOpts = {
	Filter: { string }?,
	IdPrefix: string?,
}

export type BindActionsHandle = {
	Destroy: (self: BindActionsHandle) -> (),
}

return {}

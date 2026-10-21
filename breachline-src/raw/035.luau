--!strict

--[[
	Glyphs for the shared touch HUD.

	These come from BuilderIcons, the icon font Roblox ships with the client and
	uses for its own interface (player list, purchase prompts). Drawing from it
	means no image asset ids to publish or share between places, and no
	translation burden: a glyph reads the same in every locale, while button
	text would need a localization table per experience.

	Icon names are ligatures. Setting the text to "lightning-bolt" in this font
	renders a single bolt glyph. Every name below was verified against the
	shipped font; an unknown name renders blank, so add names only after
	checking them. The full name list can be read out of the font's GSUB
	ligature table, or browsed at https://kaan650.github.io/builder-icons/.

	BuilderIcons is not part of Roblox's documented API surface. If it ever
	stops resolving, give the affected actions no Icon and the HUD falls back to
	their text labels.
]]

local BUILDER_ICONS = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"

export type IconName =
	"ArrowUp"
	| "ArrowDown"
	| "Plus"
	| "Minus"
	| "Bolt"
	| "Fire"
	| "Brake"
	| "Jump"
	| "Swap"
	| "Exit"
	| "Siren"
	| "Hitch"
	| "StopSign"
	| "TaxiSign"
	| "FlashlightOn"
	| "FlashlightOff"
	| "Swing"
	| "Throw"
	| "Aim"
	| "Reload"
	| "Release"
	| "Push"
	| "Strike"
	| "Ollie"
	| "FlipUpright"

local GLYPHS: { [string]: string } = {
	ArrowUp = "arrow-wide-up",
	ArrowDown = "arrow-wide-down",
	Plus = "circle-plus",
	Minus = "circle-minus",
	Bolt = "lightning-bolt",
	Fire = "circle-outline",
	Brake = "stop-large",
	Jump = "key-caps-lock",
	Swap = "two-arrows-switch-right",
	Exit = "door-open-arrow-to-bottom-right",
	Drop = "hand-arrow-down",
	Siren = "megaphone",
	Hitch = "chain-link",
	StopSign = "stop-large",
	TaxiSign = "tag",
	FlashlightOn = "sun",
	FlashlightOff = "moon-with-stars",
	Swing = "sword",
	Throw = "arrow-up-from-line",
	Aim = "crosshairs",
	Reload = "arrow-spin-clockwise",
	Release = "hand-arrow-down",
	Push = "circle-arrow-right",
	Strike = "cursor-stars",
	Ollie = "key-caps-lock",
	FlipUpright = "person-standing-arrow-reverse",
}

local CONTAINER_NAME = "Icon"

local Icons = {}

---Replaces any existing glyph on `button` with `name`. Passing nil clears it.
function Icons.apply(button: GuiButton, name: IconName?, color: Color3)
	local existing = button:FindFirstChild(CONTAINER_NAME)
	if existing then
		existing:Destroy()
	end
	if not name then return end

	local glyph = GLYPHS[name]
	if not glyph then
		warn(`TouchControls: unknown icon '{name}'`)
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = CONTAINER_NAME
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromScale(0.62, 0.62)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	-- Bold selects the font's Filled face, which reads better at button size
	-- than the hairline Regular outlines.
	label.FontFace = Font.new(BUILDER_ICONS, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	label.Text = glyph
	label.TextColor3 = color
	label.TextScaled = true
	label.ZIndex = button.ZIndex + 1

	-- Glyphs are square; without this they stretch on the wide Exit pill.
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = label

	label.Parent = button
end

return Icons

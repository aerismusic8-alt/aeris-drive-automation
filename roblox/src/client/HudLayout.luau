--!strict
-- How big a panel may be, and how the menu reflows, on the screen it is on.
--
-- The HUD was written in fixed pixels against a 1280x720 reference. Measured
-- against a phone viewport of 640x360 that put the 430px-tall character sheet
-- from -35 to 395, so its close button sat above the top of the screen: the
-- sheet could be opened and not closed. The six-button action menu overflowed
-- the same way, which put its bottom button out of reach.
--
-- Roblox already scales offset pixels so they are a similar physical size on
-- every device, which is why the text stays legible and why shrinking every
-- panel to a fraction of the screen is the wrong fix. What is left is to fit
-- them: measure the viewport, cap a panel that is taller than the room it has,
-- and reflow the one panel that is a grid of buttons.
--
-- This module is arithmetic only. It takes the viewport as an argument rather
-- than reading the camera, so a plain Luau test can drive every device size.
-- Hud.luau owns the panels and asks this module what size they may be.

local HudLayout = {}

-- The reference the panel numbers were written against. Naming it makes the
-- assumption visible rather than implied.
HudLayout.DESIGN_WIDTH = 1280
HudLayout.DESIGN_HEIGHT = 720

-- Room a panel leaves for the chrome it must not cover: the Roblox topbar
-- above, and the movement stick and jump button along the bottom. Roblox's own
-- guidance puts both thumbs in the bottom corners, so a panel that reaches the
-- bottom of the screen is a panel over a control.
HudLayout.SAFE_TOP = 8
HudLayout.SAFE_BOTTOM = 96

-- A panel may fill at most this share of the height. The rest is the game.
HudLayout.MAX_HEIGHT_SHARE = 0.8

-- The smallest a panel may be squeezed to before the cap is ignored. Below this
-- the panel would show nothing, so an absurdly short viewport gets the floor
-- rather than an unusable sliver.
HudLayout.MIN_PANEL_HEIGHT = 160

-- Where the panels that are measured live, how wide and how tall each wants to
-- be. Kept here so the HUD, the tests and the guard script read one set of
-- numbers instead of each carrying a copy.
HudLayout.PANEL_WIDTH = {
	Stats = 216,
	QuestPanel = 300,
	WavePanel = 320,
	BossPanel = 320,
	Rewards = 300,
	TravelPanel = 320,
	Combat = 190,
	CharPanel = 340,
}

HudLayout.PANEL_HEIGHT = {
	Stats = 244,
	QuestPanel = 100,
	WavePanel = 48,
	BossPanel = 54,
	Rewards = 206,
	TravelPanel = 320,
	Combat = 286,
	-- The two that overflow a phone. Actions is a menu of six buttons; the
	-- character sheet is a tab bar over a scrolling list.
	Actions = 412,
	CharPanel = 430,
}

-- A viewport shorter than the reference. A phone in landscape reports roughly
-- 640x360, so this is true there and false on a desktop window.
function HudLayout.isShort(viewportHeight: number): boolean
	return viewportHeight < HudLayout.DESIGN_HEIGHT
end

-- How tall a panel may be on this screen.
function HudLayout.maxPanelHeight(viewportHeight: number): number
	local room = viewportHeight - HudLayout.SAFE_TOP - HudLayout.SAFE_BOTTOM
	local share = viewportHeight * HudLayout.MAX_HEIGHT_SHARE
	return math.max(HudLayout.MIN_PANEL_HEIGHT, math.min(room, share))
end

-- The height to build a panel at: its own, unless that is taller than the room.
function HudLayout.clampHeight(name: string, viewportHeight: number): number
	local wanted = HudLayout.PANEL_HEIGHT[name]
	if not wanted then
		return 0
	end
	return math.min(wanted, HudLayout.maxPanelHeight(viewportHeight))
end

function HudLayout.fits(name: string, viewportHeight: number): boolean
	local wanted = HudLayout.PANEL_HEIGHT[name]
	if not wanted then
		return true
	end
	return wanted <= HudLayout.maxPanelHeight(viewportHeight)
end

-- Panels that will not fit as written, so the caller knows which ones have to
-- reflow instead of running off the screen. Returned rather than applied, so a
-- test can read it.
function HudLayout.overflowing(viewportHeight: number): { string }
	local out = {}
	for name in pairs(HudLayout.PANEL_HEIGHT) do
		if not HudLayout.fits(name, viewportHeight) then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- How many columns the action menu uses. Six 56px buttons stacked is 412px,
-- taller than a phone; two columns of three is about 240px, which is not. A
-- screen with the height to spare keeps the single column it was designed with.
function HudLayout.menuColumns(viewportHeight: number): number
	if HudLayout.isShort(viewportHeight) then
		return 2
	end
	return 1
end

-- The width of one cell in a grid of `columns` inside a panel `panelWidth`
-- wide, with the panel's own padding and the gap between cells taken out.
function HudLayout.menuCellWidth(panelWidth: number, columns: number): number
	local padding = 12
	local gap = 8
	return (panelWidth - padding * 2 - gap * (columns - 1)) / columns
end

-- How tall a grid of buttons is, so a caller can tell whether it fits the panel.
function HudLayout.menuGridHeight(rows: number, rowHeight: number): number
	local gap = 8
	return rows * rowHeight + math.max(0, rows - 1) * gap
end

-- The action menu, as built. Kept here rather than in Hud.luau so the HUD, the
-- tests and the guard script agree on how tall the menu ends up instead of each
-- carrying its own copy of the arithmetic.
HudLayout.ACTION_MENU = {
	top = 44,          -- the charge label above the buttons
	cellHeight = 56,   -- one button
	gap = 8,           -- between buttons
	buttons = 6,
	panelWidth = 200,
	padding = 12,
}

-- How tall the action menu is on this screen: the label, then the grid the
-- buttons reflow into.
function HudLayout.actionMenuHeight(viewportHeight: number): number
	local columns = HudLayout.menuColumns(viewportHeight)
	local rows = math.ceil(HudLayout.ACTION_MENU.buttons / columns)
	local grid = HudLayout.menuGridHeight(rows, HudLayout.ACTION_MENU.cellHeight)
	return HudLayout.ACTION_MENU.top + grid + 8
end

-- The combat panel's two forms. The wide form is what shipped before this
-- module existed; the compact form drops the title and tightens the gaps so the
-- four buttons fit above a phone's bottom edge.
HudLayout.COMBAT_WIDE_HEIGHT = 286
HudLayout.COMBAT_COMPACT_HEIGHT = 176

function HudLayout.combatHeight(viewportHeight: number): number
	if HudLayout.isShort(viewportHeight) then
		return HudLayout.COMBAT_COMPACT_HEIGHT
	end
	return HudLayout.COMBAT_WIDE_HEIGHT
end

-- How tall a panel is actually built on this screen: the reflowed menu and the
-- compact combat panel have their own sizes, everything else is its own height
-- clamped to the room available.
function HudLayout.builtHeight(name: string, viewportHeight: number): number
	if name == "Actions" then
		return HudLayout.actionMenuHeight(viewportHeight)
	elseif name == "Combat" then
		return HudLayout.combatHeight(viewportHeight)
	end
	return HudLayout.clampHeight(name, viewportHeight)
end

-- The vertical position of a panel anchored to the middle of the screen, kept
-- inside the safe area. Without this a panel taller than the screen is centred
-- on the screen and hangs off both ends, which is how the character sheet's
-- close button left the screen.
function HudLayout.centredTop(panelHeight: number, viewportHeight: number): number
	local highest = HudLayout.SAFE_TOP
	local lowest = math.max(highest, viewportHeight - HudLayout.SAFE_BOTTOM - panelHeight)
	local centred = (viewportHeight - panelHeight) / 2
	return math.max(highest, math.min(centred, lowest))
end

-- The skill bar: the row of learned skills a player can tap mid-fight.
--
-- Skills existed but could only be cast from the character sheet, which means
-- opening a menu while something is hitting you. On a phone that is not a
-- rotation, it is a reason to only ever press Attack. The bar puts the skills
-- the player actually owns one tap away, above the combat panel, and it is
-- measured here because it is a row of buttons on a screen that may be short.
HudLayout.SKILL_BUTTON = 56
HudLayout.SKILL_GAP = 6
-- Most skills a player can show at once. More than six is a wall of buttons on a
-- phone; the character sheet still lists every learned skill.
HudLayout.SKILL_SLOTS = 6

-- How wide the bar is for a given number of slots, clamped to the slot cap so it
-- can never grow past what the combat panel can sit under.
function HudLayout.skillBarWidth(slots: number): number
	local n = math.max(1, math.min(slots, HudLayout.SKILL_SLOTS))
	return n * HudLayout.SKILL_BUTTON + (n - 1) * HudLayout.SKILL_GAP
end

function HudLayout.skillBarHeight(): number
	return HudLayout.SKILL_BUTTON
end

-- How far the bar's bottom edge sits above the bottom of the screen. It clears
-- the combat panel by one gap, which is what stops a skill button from landing
-- on top of the attack button on a small screen.
function HudLayout.skillBarBottom(viewportHeight: number): number
	local combatHeight = HudLayout.combatHeight(viewportHeight)
	local base = viewportHeight < HudLayout.DESIGN_HEIGHT and HudLayout.SAFE_BOTTOM or 24
	return base + combatHeight + HudLayout.SKILL_GAP
end

return HudLayout

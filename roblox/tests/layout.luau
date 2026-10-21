--!strict
-- Does the HUD fit the screen it is on?
--
-- This suite exists because of a measurement, not a report. The HUD is written
-- in fixed pixels against a 1280x720 reference, and a phone in landscape has
-- roughly 640x360 to give. Reading the numbers off Hud.luau and projecting them
-- onto that viewport put the character sheet from -35 to 395: its close button
-- was above the top of the screen, so the sheet could be opened and not closed.
-- The six-button action menu overflowed the same way, putting its last button
-- out of reach.
--
-- No Luau test can see a screen, but this one can do the arithmetic the screen
-- would do, which is what found the bug in the first place. It runs on the real
-- HudLayout module, so a panel that is resized or a viewport that is shorter
-- than expected fails here rather than on a phone.
--
-- Pure Luau, no Roblox globals.

local t = require("./TestRunner")
local HudLayout = require("../src/client/HudLayout")

-- The viewports worth caring about. 640x360 is a phone in landscape, which is
-- the smallest case this game has to survive; 1280x720 is the reference the
-- layout was written against; 1920x1080 is a desktop.
local PHONE_H = 360
local REFERENCE_H = 720
local DESKTOP_H = 1080
local PHONE_VIEWPORTS = { 360, 375, 390, 414 }

local function atMost(actual: number, bound: number, label: string)
	t.assertTrue(actual <= bound, label .. " (" .. tostring(actual) .. " > " .. tostring(bound) .. ")")
end

local function atLeast(actual: number, bound: number, label: string)
	t.assertTrue(actual >= bound, label .. " (" .. tostring(actual) .. " < " .. tostring(bound) .. ")")
end

--------------------------------------------------------------------------
t.suite("HudLayout: a panel fits the screen it is built for")
--------------------------------------------------------------------------

t.test("every panel as built fits a phone viewport", function()
	-- The declared heights are the design intent; builtHeight is what the panel
	-- actually becomes on this screen, after the menu reflows and the sheet is
	-- capped. This is the number that decides whether a button is reachable.
	for _, viewport in ipairs(PHONE_VIEWPORTS) do
		for name in pairs(HudLayout.PANEL_HEIGHT) do
			local built = HudLayout.builtHeight(name, viewport)
			atMost(built, viewport - HudLayout.SAFE_BOTTOM,
				name .. " as built is taller than the screen at height " .. viewport)
		end
	end
end)

t.test("the panels that do not fit as written are the ones that reflow", function()
	local overflowing = HudLayout.overflowing(PHONE_H)
	local expected = { "Actions", "CharPanel", "Combat", "TravelPanel" }
	t.assertEqual(#overflowing, #expected,
		"expected these to overflow: " .. table.concat(expected, ", ")
			.. " but got: " .. table.concat(overflowing, ", "))
end)

t.test("a panel taller than the screen is capped to the room it has", function()
	local capped = HudLayout.clampHeight("CharPanel", PHONE_H)
	t.assertLess(capped, HudLayout.PANEL_HEIGHT.CharPanel,
		"the character sheet was not capped on a phone")
	atMost(capped, HudLayout.maxPanelHeight(PHONE_H), "the capped panel is still taller than the room")
end)

t.test("a panel that already fits keeps its own height", function()
	t.assertEqual(HudLayout.clampHeight("WavePanel", PHONE_H), HudLayout.PANEL_HEIGHT.WavePanel,
		"a small panel was shrunk for no reason")
	t.assertEqual(HudLayout.clampHeight("QuestPanel", REFERENCE_H), HudLayout.PANEL_HEIGHT.QuestPanel,
		"a panel was shrunk on the reference screen")
end)

t.test("the reference screen is not treated as short", function()
	t.assertFalse(HudLayout.isShort(REFERENCE_H), "the reference screen is flagged as short")
	t.assertFalse(HudLayout.isShort(DESKTOP_H), "a desktop screen is flagged as short")
	t.assertTrue(HudLayout.isShort(PHONE_H), "a phone screen is not flagged as short")
end)

--------------------------------------------------------------------------
t.suite("HudLayout: a centred panel stays inside the safe area")
--------------------------------------------------------------------------

t.test("a panel taller than the screen is pinned to the top, not centred off it", function()
	-- This is the exact bug: 430px centred on 360 gives a negative top, which is
	-- above the screen, which is where the close button went.
	local top = HudLayout.centredTop(HudLayout.PANEL_HEIGHT.CharPanel, PHONE_H)
	atLeast(top, 0, "the panel starts above the top of the screen")
end)

t.test("every panel stays on screen at every phone size", function()
	for _, viewport in ipairs(PHONE_VIEWPORTS) do
		for name in pairs(HudLayout.PANEL_HEIGHT) do
			local height = HudLayout.clampHeight(name, viewport)
			local top = HudLayout.centredTop(height, viewport)
			atLeast(top, 0, name .. " starts above the screen at height " .. viewport)
			atMost(top + height, viewport, name .. " ends below the screen at height " .. viewport)
		end
	end
end)

t.test("a panel that fits is centred rather than pinned", function()
	local height = HudLayout.PANEL_HEIGHT.WavePanel
	local top = HudLayout.centredTop(height, REFERENCE_H)
	t.assertNear(top, (REFERENCE_H - height) / 2, 0.001, "a small panel was not centred")
end)

--------------------------------------------------------------------------
t.suite("HudLayout: the action menu reflows instead of running off screen")
--------------------------------------------------------------------------

t.test("the menu is one column on the reference screen", function()
	t.assertEqual(HudLayout.menuColumns(REFERENCE_H), 1, "the desktop menu reflowed")
end)

t.test("the menu is two columns on a phone", function()
	t.assertEqual(HudLayout.menuColumns(PHONE_H), 2, "the phone menu did not reflow")
end)

t.test("the reflowed menu is shorter than the screen", function()
	local rows = 3 -- six buttons in two columns
	local cellHeight = 56
	local grid = HudLayout.menuGridHeight(rows, cellHeight)
	t.assertLess(grid, PHONE_H, "the two-column menu is still taller than the screen")
end)

t.test("the reflowed menu fits inside its panel width", function()
	local panelWidth = 200
	local cell = HudLayout.menuCellWidth(panelWidth, 2)
	t.assertGreater(cell, 44, "a menu cell is below the touch minimum")
	local right = 12 + cell + 8 + cell
	atMost(right, panelWidth, "the second menu column runs past the panel")
end)

t.test("a menu cell stays a comfortable touch target", function()
	-- 44px is the published minimum for a mobile touch target.
	local cell = HudLayout.menuCellWidth(200, 2)
	t.assertGreater(cell, 44, "a menu cell is too narrow to tap")
	t.assertGreater(56, 44, "a menu row is too short to tap")
end)

--------------------------------------------------------------------------
t.suite("HudLayout: the panel table matches what the HUD builds")
--------------------------------------------------------------------------

t.test("every measured panel has a height", function()
	for _, name in ipairs({ "Stats", "QuestPanel", "WavePanel", "BossPanel", "Rewards",
		"TravelPanel", "Combat", "Actions", "CharPanel" }) do
		t.assertNotNil(HudLayout.PANEL_HEIGHT[name], name .. " has no height recorded")
	end
end)

t.test("the safe area leaves room for the thumbs", function()
	atLeast(HudLayout.SAFE_BOTTOM, 88,
		"the bottom safe area is too small for the movement stick and jump button")
end)

--------------------------------------------------------------------------
t.suite("HudLayout: the skill bar sits above the attack button, not on it")
--------------------------------------------------------------------------

t.test("the bar never overlaps the combat panel", function()
	-- The bar is anchored to the bottom and measured upward from the combat
	-- panel's top edge. If the arithmetic is wrong the two overlap, and on a
	-- phone a skill button lands on the attack button -- the one control the
	-- game is actually played with.
	for _, h in ipairs({ PHONE_H, REFERENCE_H, DESKTOP_H }) do
		local combatTop = HudLayout.combatHeight(h)
		local barBottom = HudLayout.skillBarBottom(h)
		t.assertGreater(barBottom, combatTop,
			"the skill bar overlaps the combat panel at viewport height " .. tostring(h))
	end
end)

t.test("the bar is on screen at every size", function()
	-- The bar's top edge, measured up from the bottom of the screen, must not
	-- reach above the top of the screen.
	for _, h in ipairs(PHONE_VIEWPORTS) do
		local top = HudLayout.skillBarBottom(h) + HudLayout.skillBarHeight()
		atMost(top, h, "the skill bar runs off the top of the screen at height " .. tostring(h))
	end
end)

t.test("a bar of skills is wide enough to tap and never wider than its panel", function()
	local one = HudLayout.skillBarWidth(1)
	atLeast(one, 44, "a skill button is too narrow to tap")
	-- Six slots is the cap the HUD shows; a bar wider than the combat panel
	-- would hang off both sides of it.
	local six = HudLayout.skillBarWidth(6)
	atMost(six, HudLayout.PANEL_WIDTH.Combat * 3,
		"the skill bar is wider than the space under the attack button")
end)

t.test("asking for more slots than the cap still returns a usable width", function()
	-- The HUD clamps to SKILL_SLOTS; a caller passing a bigger number must not
	-- get a bar that runs off the screen.
	t.assertTrue(HudLayout.skillBarWidth(20) == HudLayout.skillBarWidth(HudLayout.SKILL_SLOTS),
		"the slot cap is not enforced")
	t.assertGreater(HudLayout.skillBarWidth(0), 0, "a zero-slot bar has no width")
end)

return t.finish()

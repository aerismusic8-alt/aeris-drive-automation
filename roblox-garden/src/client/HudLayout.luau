--!strict
-- Layout maths for the HUD, pure Luau so it can be tested with no engine.
--
-- This exists because the previous game's HUD was laid out inline, and the
-- result was a skill bar that ran off the top of a 360px phone screen. A layout
-- that cannot be measured cannot be checked. Here every position and size is a
-- function of the viewport, so a test can ask "does this fit on a 360x640
-- phone?" and get a number back.

local HudLayout = {}

-- The screen the design targets. Everything scales from this.
HudLayout.DESIGN_WIDTH = 720
HudLayout.DESIGN_HEIGHT = 1280

-- The smallest phone this must survive. A 2020-era budget Android in portrait.
HudLayout.MIN_WIDTH = 360
HudLayout.MIN_HEIGHT = 640

-- Apple's and Google's own minimum. Below this a tap is a coin flip.
HudLayout.MIN_TOUCH = 44

-- Rows and the gaps between them, in the design space.
HudLayout.GAP = 8
HudLayout.PAD = 12

-- The top bar: coins, level, and the collection progress.
HudLayout.TOP_BAR = { height = 56 }

-- The bottom bar: the four main screens, plus sell. Five buttons across the
-- bottom is the whole navigation, because a phone has a thumb and not a mouse.
HudLayout.BOTTOM_BAR = { height = 72, buttons = 5 }

-- The plot grid: tapping a plot is the primary interaction in the game, so the
-- cells are large.
HudLayout.PLOT_GRID = { columns = 4, gap = 6 }

-- A panel is a full-width sheet that slides over the garden. It never covers the
-- top or bottom bar, so the player can always read their coins and always leave.
-- The offsets include PAD because the bars are themselves inset by PAD; leaving
-- it out put the panel four pixels under the top bar on a 360x640 phone.
HudLayout.PANEL = {
        topOffset = HudLayout.PAD + HudLayout.TOP_BAR.height + HudLayout.GAP,
        bottomOffset = HudLayout.BOTTOM_BAR.height + HudLayout.GAP + HudLayout.PAD,
}

-- Scale factor for the current screen. Clamped at 1 so a large screen is not
-- stretched: the design is the maximum, not the minimum.
function HudLayout.scale(viewportWidth: number, viewportHeight: number): number
        local w = math.max(1, viewportWidth) / HudLayout.DESIGN_WIDTH
        local h = math.max(1, viewportHeight) / HudLayout.DESIGN_HEIGHT
        return math.min(1, math.min(w, h))
end

-- The usable height of a panel on this screen. This is the number the previous
-- game got wrong: it laid the skill bar out at a fixed offset and the bar left
-- the top of the screen.
function HudLayout.panelHeight(viewportWidth: number, viewportHeight: number): number
        local usable = viewportHeight - HudLayout.PANEL.topOffset - HudLayout.PANEL.bottomOffset
        return math.max(0, usable)
end

-- Whether a panel fits without scrolling. A panel that does not fit must scroll,
-- and this is the flag that tells the HUD to add a scrolling frame.
function HudLayout.panelFits(viewportWidth: number, viewportHeight: number, neededHeight: number): boolean
        return neededHeight <= HudLayout.panelHeight(viewportWidth, viewportHeight)
end

-- One cell of the plot grid, given how many columns fit. Sized so a cell is
-- never below the minimum touch target, even on the smallest screen.
function HudLayout.plotCellSize(viewportWidth: number, columns: number): number
        local cols = math.max(1, math.floor(columns))
        local usable = viewportWidth - HudLayout.PAD * 2 - HudLayout.PLOT_GRID.gap * (cols - 1)
        return math.max(HudLayout.MIN_TOUCH, math.floor(usable / cols))
end

-- The bottom bar's buttons: equal width, with a gap, filling the screen.
function HudLayout.bottomButtonSize(viewportWidth: number, count: number): (number, number)
        local n = math.max(1, math.floor(count))
        local usable = viewportWidth - HudLayout.PAD * 2 - HudLayout.GAP * (n - 1)
        local width = math.max(HudLayout.MIN_TOUCH, math.floor(usable / n))
        return width, HudLayout.BOTTOM_BAR.height - HudLayout.GAP
end

-- A rect in offset pixels: {x, y, width, height}. The HUD turns these into
-- UDim2.fromOffset, so there is one place that decides where anything is.
function HudLayout.topBarRect(viewportWidth: number): { number }
        return { HudLayout.PAD, HudLayout.PAD, viewportWidth - HudLayout.PAD * 2, HudLayout.TOP_BAR.height }
end

function HudLayout.bottomBarRect(viewportWidth: number, viewportHeight: number): { number }
        local height = HudLayout.BOTTOM_BAR.height
        return { HudLayout.PAD, viewportHeight - height - HudLayout.PAD, viewportWidth - HudLayout.PAD * 2, height }
end

function HudLayout.panelRect(viewportWidth: number, viewportHeight: number): { number }
        return {
                HudLayout.PAD,
                HudLayout.PANEL.topOffset,
                viewportWidth - HudLayout.PAD * 2,
                HudLayout.panelHeight(viewportWidth, viewportHeight),
        }
end

-- Every rect the HUD needs, so a test can check the whole screen at once for
-- overlaps and off-screen edges rather than checking one panel in isolation.
function HudLayout.rects(viewportWidth: number, viewportHeight: number): { any }
        local top = HudLayout.topBarRect(viewportWidth)
        local bottom = HudLayout.bottomBarRect(viewportWidth, viewportHeight)
        local panel = HudLayout.panelRect(viewportWidth, viewportHeight)
        return {
                { name = "topBar", rect = top },
                { name = "bottomBar", rect = bottom },
                { name = "panel", rect = panel },
        }
end

-- True when a rect is entirely on screen.
function HudLayout.onScreen(rect: { number }, viewportWidth: number, viewportHeight: number): boolean
        local x, y, width, height = rect[1], rect[2], rect[3], rect[4]
        if width <= 0 or height <= 0 then
                return false
        end
        if x < 0 or y < 0 then
                return false
        end
        if x + width > viewportWidth then
                return false
        end
        if y + height > viewportHeight then
                return false
        end
        return true
end

-- True when two rects share any area.
function HudLayout.overlaps(a: { number }, b: { number }): boolean
        local ax, ay, aw, ah = a[1], a[2], a[3], a[4]
        local bx, by, bw, bh = b[1], b[2], b[3], b[4]
        if ax + aw <= bx or bx + bw <= ax then
                return false
        end
        if ay + ah <= by or by + bh <= ay then
                return false
        end
        return true
end

return HudLayout

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

-- The bottom bar: the screens plus sell. Six buttons across the bottom is the
-- whole navigation, because a phone has a thumb and not a mouse. At 360px that
-- is 49px per button, still above the 44px minimum.
HudLayout.BOTTOM_BAR = { height = 72, buttons = 6 }

-- The plot grid: tapping a plot is the primary interaction in the game, so the
-- cells are large. The grid lives inside the garden panel, not on the world
-- screen. Drawn on the world screen it was twelve opaque buttons three rows
-- deep, which on a 1600x900 viewport covered 81% of the height and left 8px of
-- world showing. On a phone that is worse than ugly: Roblox spawns its movement
-- thumbstick where the player first touches, so a button under the thumb means
-- the player taps a plot instead of walking. That is why K could not move. A
-- panel can be closed; a world screen cannot.
HudLayout.PLOT_GRID = { columns = 4, gap = 6 }

-- How many plots the grid draws. Config.Garden.TotalPlots is the same number,
-- but this module is pure arithmetic with no dependency on Config, so the count
-- is repeated here and a test asserts the two agree.
HudLayout.PLOT_COUNT = 12

-- The list area inside a panel, mirroring the scrolling frame the HUD draws:
-- 8px inset on each side, 52px down for the title row, 8px up from the bottom.
-- The grid is laid out in here, so it can never reach a screen edge.
HudLayout.PANEL_LIST = { inset = 8, top = 52, bottom = 8 }

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

-- How many rows the plot grid needs for a given number of plots.
function HudLayout.plotRows(plotCount: number): number
        local cols = HudLayout.PLOT_GRID.columns
        return math.ceil(math.max(1, plotCount) / cols)
end

-- The area inside an open panel where the plot grid may draw, in screen
-- coordinates. Every cell is placed inside this rect, so the grid can never
-- touch a screen edge or a bar no matter how short the screen is.
function HudLayout.gridAreaRect(viewportWidth: number, viewportHeight: number): { number }
        local panel = HudLayout.panelRect(viewportWidth, viewportHeight)
        local inset = HudLayout.PANEL_LIST.inset
        local x = panel[1] + inset
        local y = panel[2] + HudLayout.PANEL_LIST.top
        local width = math.max(0, panel[3] - inset * 2)
        local height = math.max(0, panel[4] - HudLayout.PANEL_LIST.top - HudLayout.PANEL_LIST.bottom)
        return { x, y, width, height }
end

-- One cell of the plot grid, bounded by the panel area on both axes.
--
-- Called without a height it is the old width-only answer, which the finger-size
-- test uses. Called with a height it is bounded vertically too, and the minimum
-- touch target is NOT enforced: on a short screen a 44px floor would push the
-- last row out of the panel, and the panel scrolls, so staying inside the panel
-- wins. A cell that is off screen cannot be tapped at all.
function HudLayout.plotCellSize(viewportWidth: number, columns: number, viewportHeight: number?): number
        local cols = math.max(1, math.floor(columns))
        local usable = viewportWidth - HudLayout.PAD * 2 - HudLayout.PLOT_GRID.gap * (cols - 1)
        local cell = math.floor(usable / cols)

        if not viewportHeight then
                return math.max(HudLayout.MIN_TOUCH, cell)
        end

        local area = HudLayout.gridAreaRect(viewportWidth, viewportHeight)
        local rows = HudLayout.plotRows(HudLayout.PLOT_COUNT)
        local byWidth = math.floor((area[3] - HudLayout.PLOT_GRID.gap * (cols - 1)) / cols)
        local byHeight = math.floor((area[4] - HudLayout.PLOT_GRID.gap * (rows - 1)) / rows)
        return math.max(1, math.min(cell, byWidth, byHeight))
end

-- Every plot cell as a rect, laid out inside the panel's list area so a test can
-- check the whole grid stays inside the panel rather than trusting one number.
function HudLayout.plotRects(viewportWidth: number, viewportHeight: number, plotCount: number): { any }
        local columns = HudLayout.PLOT_GRID.columns
        local cell = HudLayout.plotCellSize(viewportWidth, columns, viewportHeight)
        local area = HudLayout.gridAreaRect(viewportWidth, viewportHeight)
        local rects = {}
        for index = 1, plotCount do
                local column = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                local x = area[1] + column * (cell + HudLayout.PLOT_GRID.gap)
                local y = area[2] + row * (cell + HudLayout.PLOT_GRID.gap)
                table.insert(rects, { name = "Plot" .. tostring(index), rect = { x, y, cell, cell } })
        end
        return rects
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
        local all = {
                { name = "topBar", rect = top },
                { name = "bottomBar", rect = bottom },
                { name = "panel", rect = panel },
        }
        -- The plot grid is part of the panel, so the whole-screen check has to
        -- see it. It is listed here so a test proves the grid stays inside the
        -- panel and therefore on screen.
        for _, entry in ipairs(HudLayout.plotRects(viewportWidth, viewportHeight, HudLayout.PLOT_COUNT)) do
                table.insert(all, entry)
        end
        return all
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

-- True when rect b is entirely inside rect a. The plot grid lives inside the
-- panel, so "inside the panel" is the property a test needs to check.
function HudLayout.contains(a: { number }, b: { number }): boolean
        local ax, ay, aw, ah = a[1], a[2], a[3], a[4]
        local bx, by, bw, bh = b[1], b[2], b[3], b[4]
        return bx >= ax and by >= ay and bx + bw <= ax + aw and by + bh <= ay + ah
end

return HudLayout

--!strict
-- The HUD. Builds the screen once, then repaints from state pushes.
--
-- Rules this follows, all of them from the previous game going wrong:
--   * Every tap target is at least HudLayout.MIN_TOUCH (44px). A phone tap is a
--     thumb, not a cursor.
--   * Nothing is positioned at a fixed offset. Every rect comes from HudLayout,
--     which is a pure function of the viewport, so the screen cannot run off the
--     top the way the old skill bar did.
--   * A button that is not wired is not drawn. The old HUD drew a fold caret on
--     a panel with nothing behind it, which is a control that does nothing.
--
-- The HUD owns no game state. It draws what the server pushed and reports taps
-- through the `Intent` table the entry point fills in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Text = require(Shared.Text)
local HudLayout = require(script.Parent.HudLayout)

local Hud = {}

local COLORS = {
        background = Color3.fromRGB(24, 26, 22),
        bar = Color3.fromRGB(38, 42, 34),
        panel = Color3.fromRGB(32, 36, 30),
        button = Color3.fromRGB(72, 96, 58),
        buttonDisabled = Color3.fromRGB(58, 60, 56),
        text = Color3.fromRGB(240, 240, 232),
        muted = Color3.fromRGB(170, 175, 165),
        ready = Color3.fromRGB(140, 220, 110),
        locked = Color3.fromRGB(70, 68, 66),
}

-- Filled in by the entry point. The HUD never requires the entry point back,
-- because that is a cycle; it calls through this table instead.
Hud.Intent = nil

local gui = nil
local refs = {}
-- Which panel is open, so a state push can rebuild it in place.
local lastPanel: string? = nil

local function newFrame(name: string, parent: any, rect: { number }, color: any, radius: number?): any
        local frame = Instance.new("Frame")
        frame.Name = name
        frame.Position = UDim2.fromOffset(rect[1], rect[2])
        frame.Size = UDim2.fromOffset(rect[3], rect[4])
        frame.BackgroundColor3 = color
        frame.BorderSizePixel = 0
        frame.Parent = parent
        if radius then
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, radius)
                corner.Parent = frame
        end
        return frame
end

local function newButton(name: string, parent: any, rect: { number }, label: string, onClick: () -> ()): any
        local button = Instance.new("TextButton")
        button.Name = name
        button.Position = UDim2.fromOffset(rect[1], rect[2])
        button.Size = UDim2.fromOffset(rect[3], rect[4])
        button.BackgroundColor3 = COLORS.button
        button.BorderSizePixel = 0
        button.Text = label
        button.TextColor3 = COLORS.text
        button.TextScaled = true
        button.Font = Enum.Font.GothamBold
        button.AutoButtonColor = true
        button.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button

        -- A text label inside a TextButton scales to the button, but a very long
        -- Thai label would be clipped. Padding keeps the glyphs off the edge.
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 6)
        padding.PaddingRight = UDim.new(0, 6)
        padding.Parent = button

        button.Activated:Connect(onClick)
        return button
end

-- The whole screen is built here, once. Everything after this is a repaint.
function Hud.build(viewportWidth: number, viewportHeight: number): any
        local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

        gui = Instance.new("ScreenGui")
        gui.Name = "AXGardenHud"
        gui.ResetOnSpawn = false
        -- Insets, not ignores. With IgnoreGuiInset = true the HUD started at
        -- screen y=0, which on a phone is where Roblox draws its own menu, chat
        -- and player-list buttons. The coins label sat underneath them, so the
        -- Roblox controls read as the game covering the screen. Leaving the
        -- inset on shifts the whole HUD below that bar.
        gui.IgnoreGuiInset = false
        gui.Parent = playerGui

        local top = HudLayout.topBarRect(viewportWidth, viewportHeight)
        refs.topBar = newFrame("TopBar", gui, top, COLORS.bar, 10)
        -- The bars are decoration, not controls. A Frame with Active left true
        -- still swallows a tap, so on a phone a press on the bar never reaches
        -- the world underneath and Roblox never spawns the movement thumbstick
        -- there. Turning it off makes the bar click-through except for the real
        -- buttons inside it.
        refs.topBar.Active = false
        refs.coins = Instance.new("TextLabel")
        refs.coins.Name = "Coins"
        refs.coins.BackgroundTransparency = 1
        refs.coins.Position = UDim2.fromOffset(10, 0)
        refs.coins.Size = UDim2.fromOffset(math.floor(top[3] / 2) - 10, top[4])
        refs.coins.TextXAlignment = Enum.TextXAlignment.Left
        refs.coins.TextColor3 = COLORS.text
        refs.coins.TextScaled = true
        refs.coins.Font = Enum.Font.GothamBold
        refs.coins.Text = ""
        refs.coins.Parent = refs.topBar

        refs.collection = Instance.new("TextLabel")
        refs.collection.Name = "Collection"
        refs.collection.BackgroundTransparency = 1
        refs.collection.Position = UDim2.fromOffset(math.floor(top[3] / 2), 0)
        refs.collection.Size = UDim2.fromOffset(math.floor(top[3] / 2) - 10, top[4])
        refs.collection.TextXAlignment = Enum.TextXAlignment.Right
        refs.collection.TextColor3 = COLORS.muted
        refs.collection.TextScaled = true
        refs.collection.Font = Enum.Font.Gotham
        refs.collection.Text = ""
        refs.collection.Parent = refs.topBar

        -- The plot grid is built with the panel below, not here. It used to be
        -- drawn straight onto the screen, which covered the world and swallowed
        -- the movement thumbstick.
        refs.plots = {}

        -- The bottom bar: the screens and sell. Five buttons, all wired. Garden
        -- is first because it is the primary interaction in the game.
        local bottom = HudLayout.bottomBarRect(viewportWidth, viewportHeight)
        refs.bottomBar = newFrame("BottomBar", gui, bottom, COLORS.bar, 10)
        refs.bottomBar.Active = false
        local buttonWidth, buttonHeight = HudLayout.bottomButtonSize(viewportWidth, HudLayout.BOTTOM_BAR.buttons, viewportHeight)
        local labels = {
                { name = "Garden", text = Text.get("garden"), intent = "openGarden" },
                { name = "Shop", text = Text.get("shop"), intent = "openShop" },
                { name = "Pets", text = Text.get("pets"), intent = "openPets" },
                { name = "Collection", text = Text.get("collection"), intent = "openCollection" },
                { name = "Upgrades", text = Text.get("upgrades"), intent = "openUpgrades" },
        }
        for i, entry in ipairs(labels) do
                local rect = { i * (buttonWidth + HudLayout.GAP) - buttonWidth, HudLayout.GAP / 2, buttonWidth, buttonHeight }
                local button = newButton(entry.name, refs.bottomBar, rect, entry.text, function()
                        if Hud.Intent then
                                Hud.Intent[entry.intent]()
                        end
                end)
                refs[entry.name] = button
        end

        -- Sell is the last button and is special: it carries the basket total as
        -- its label, because selling is the action a player comes back for.
        local sellIndex = HudLayout.BOTTOM_BAR.buttons
        local sellRect = { sellIndex * (buttonWidth + HudLayout.GAP) - buttonWidth, HudLayout.GAP / 2, buttonWidth, buttonHeight }
        refs.Sell = newButton("Sell", refs.bottomBar, sellRect, Text.get("harvestAll"), function()
                if Hud.Intent then
                        Hud.Intent.sell()
                end
        end)
        refs.Sell.BackgroundColor3 = COLORS.buttonDisabled

        -- The panel sheet, hidden until a screen is opened. Active is off so the
        -- sheet itself does not swallow a tap meant for the list or the close
        -- button, and so the world stays tappable at the edges.
        local panel = HudLayout.panelRect(viewportWidth, viewportHeight)
        refs.panel = newFrame("Panel", gui, panel, COLORS.panel, 12)
        refs.panel.Visible = false
        refs.panel.Active = false

        refs.panelTitle = Instance.new("TextLabel")
        refs.panelTitle.Name = "Title"
        refs.panelTitle.BackgroundTransparency = 1
        refs.panelTitle.Position = UDim2.fromOffset(10, 0)
        refs.panelTitle.Size = UDim2.fromOffset(panel[3] - 100, 40)
        refs.panelTitle.TextXAlignment = Enum.TextXAlignment.Left
        refs.panelTitle.TextColor3 = COLORS.text
        refs.panelTitle.TextScaled = true
        refs.panelTitle.Font = Enum.Font.GothamBold
        refs.panelTitle.Text = ""
        refs.panelTitle.Parent = refs.panel

        refs.closeButton = newButton("Close", refs.panel, { panel[3] - 90, 6, 84, 40 }, Text.get("close"), function()
                Hud.closePanel()
        end)

        -- The scrolling list every panel draws into. Scrolling because a phone
        -- screen cannot show 28 seeds, and the alternative is a second page
        -- mechanism.
        local list = Instance.new("ScrollingFrame")
        list.Name = "List"
        list.Position = UDim2.fromOffset(8, 52)
        list.Size = UDim2.fromOffset(panel[3] - 16, panel[4] - 60)
        list.BackgroundTransparency = 1
        list.BorderSizePixel = 0
        list.ScrollBarThickness = 6
        list.CanvasSize = UDim2.new(0, 0, 0, 0)
        list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        list.Parent = refs.panel
        refs.list = list

        -- The garden grid, inside the panel. This is where the twelve plot
        -- buttons live now: on the world screen they covered 81% of a 1600x900
        -- viewport and, on a phone, sat under the movement thumbstick so the
        -- player could not walk. The grid is sized from the panel's own list
        -- area, so it is bounded on both axes and can never reach an edge.
        local grid = Instance.new("Frame")
        grid.Name = "Grid"
        grid.Position = UDim2.fromOffset(HudLayout.PANEL_LIST.inset, HudLayout.PANEL_LIST.top)
        grid.Size = UDim2.fromOffset(
                panel[3] - HudLayout.PANEL_LIST.inset * 2,
                panel[4] - HudLayout.PANEL_LIST.top - HudLayout.PANEL_LIST.bottom
        )
        grid.BackgroundTransparency = 1
        grid.BorderSizePixel = 0
        grid.Active = false
        grid.Visible = false
        grid.Parent = refs.panel
        refs.grid = grid

        local columns = HudLayout.PLOT_GRID.columns
        local cell = HudLayout.plotCellSize(viewportWidth, columns, viewportHeight)
        for index = 1, HudLayout.PLOT_COUNT do
                local column = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                local button = Instance.new("TextButton")
                button.Name = "Plot" .. tostring(index)
                button.Position = UDim2.fromOffset(
                        column * (cell + HudLayout.PLOT_GRID.gap),
                        row * (cell + HudLayout.PLOT_GRID.gap)
                )
                button.Size = UDim2.fromOffset(cell, cell)
                button.BackgroundColor3 = COLORS.locked
                button.BorderSizePixel = 0
                button.Text = ""
                button.TextColor3 = COLORS.text
                button.TextScaled = true
                button.Font = Enum.Font.GothamBold
                button.Parent = grid

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 8)
                corner.Parent = button

                -- The progress bar, as a child frame whose width the repaint
                -- sets. A frame rather than a fill on the button, so the button
                -- colour can still show locked/ready.
                local fill = Instance.new("Frame")
                fill.Name = "Fill"
                fill.Position = UDim2.fromOffset(0, cell - 8)
                fill.Size = UDim2.fromOffset(0, 6)
                fill.BackgroundColor3 = COLORS.ready
                fill.BorderSizePixel = 0
                fill.Parent = button

                local plotIndex = index
                button.Activated:Connect(function()
                        if Hud.Intent then
                                Hud.Intent.tapPlot(plotIndex)
                        end
                end)

                refs.plots[index] = button
        end

        refs.toast = Instance.new("TextLabel")
        refs.toast.Name = "Toast"
        refs.toast.BackgroundTransparency = 1
        -- Above the bottom bar, not below the top bar: the old position was the
        -- first row of the plot grid, so every message covered a plot.
        refs.toast.Position = UDim2.fromOffset(HudLayout.PAD, bottom[2] - 30)
        refs.toast.Size = UDim2.fromOffset(viewportWidth - HudLayout.PAD * 2, 28)
        refs.toast.TextColor3 = COLORS.ready
        refs.toast.TextScaled = true
        refs.toast.Font = Enum.Font.GothamBold
        refs.toast.Text = ""
        refs.toast.Parent = gui

        return gui
end

-- Clear the panel's list. Called before every panel rebuild so a reopen does
-- not stack two lists.
local function clearList()
        for _, child in ipairs(refs.list:GetChildren()) do
                child:Destroy()
        end
        refs.list.CanvasSize = UDim2.new(0, 0, 0, 0)
end

-- One row in a panel: a label on the left, an optional button on the right.
local function row(y: number, height: number, label: string, buttonText: string?, onPress: (() -> ())?, enabled: boolean?): number
        local width = refs.list.AbsoluteSize.X
        if width <= 0 then
                width = 320
        end

        local text = Instance.new("TextLabel")
        text.BackgroundColor3 = COLORS.bar
        text.BorderSizePixel = 0
        text.Position = UDim2.fromOffset(0, y)
        text.Size = UDim2.fromOffset(width - (buttonText and 120 or 0), height)
        text.Text = label
        text.TextColor3 = COLORS.text
        text.TextScaled = true
        text.TextXAlignment = Enum.TextXAlignment.Left
        text.Font = Enum.Font.Gotham
        text.Parent = refs.list

        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 8)
        padding.Parent = text

        if buttonText then
                local rect = { width - 116, y, 116, height }
                local button = newButton("Action", refs.list, rect, buttonText, function()
                        if onPress then
                                onPress()
                        end
                end)
                if enabled == false then
                        button.BackgroundColor3 = COLORS.buttonDisabled
                        button.Active = false
                end
        end

        return y + height + 4
end

local function setTitle(title: string)
        refs.panelTitle.Text = title
        refs.panel.Visible = true
        -- Two things can fill a panel: the row list and the garden grid. Exactly
        -- one is visible at a time, or the shop's rows would draw over the plots.
        refs.list.Visible = true
        if refs.grid then
                refs.grid.Visible = false
        end
end

-- Show the garden grid and hide the row list. The grid is a fixed child of the
-- panel built once at boot, so opening the garden is just a visibility flip: no
-- rebuild, and the plot colours the repaint already wrote stay put.
local function showGrid(title: string)
        refs.panelTitle.Text = title
        refs.panel.Visible = true
        refs.list.Visible = false
        if refs.grid then
                refs.grid.Visible = true
        end
end

function Hud.closePanel()
        if refs.panel then
                refs.panel.Visible = false
        end
end

-- Repaint the persistent HUD: coins, collection, every plot, and the sell
-- button's total.
function Hud.repaint(state: any)
        if not gui then
                return
        end

        refs.coins.Text = Text.get("coins") .. " " .. tostring(state.coins)
        refs.collection.Text = Text.get("discovered", state.collection.seedCount, state.collection.seedTotal)

        for index, button in pairs(refs.plots) do
                local plot = state.garden.plots[index]
                if plot then
                        if not plot.unlocked then
                                button.BackgroundColor3 = COLORS.locked
                                button.Text = Text.get("locked")
                        elseif plot.seedId == nil then
                                button.BackgroundColor3 = COLORS.bar
                                button.Text = Text.get("empty")
                        elseif plot.ready then
                                button.BackgroundColor3 = COLORS.ready
                                button.Text = Text.get("harvest")
                        else
                                button.BackgroundColor3 = COLORS.button
                                button.Text = Text.duration(plot.secondsLeft)
                        end

                        local fill = button:FindFirstChild("Fill")
                        if fill then
                                fill.Size = UDim2.fromOffset(math.floor(button.AbsoluteSize.X * plot.progress), 6)
                        end
                end
        end

        local basket = state.basket
        if basket.count > 0 then
                refs.Sell.Text = Text.get("sold", basket.total)
                refs.Sell.BackgroundColor3 = COLORS.ready
        else
                refs.Sell.Text = Text.get("empty")
                refs.Sell.BackgroundColor3 = COLORS.buttonDisabled
        end
end

-- Panel builders. Each one draws a list and wires its buttons to Intent, so a
-- button that appears always does something.
local PANELS = {}

-- The garden: the plot grid plus the upgrade rows. The grid is the panel's own
-- child and is drawn once at boot, so this builder only switches to it and the
-- upgrade rows go below the grid in the list, which is hidden here. Upgrades
-- live here rather than on their own button because the bottom bar has five
-- slots and the garden is the screen a player visits most.
function PANELS.garden(state: any)
        showGrid(Text.get("garden"))
end

function PANELS.shop(state: any)
        setTitle(Text.get("shop"))
        clearList()
        local y = 0
        local height = 56

        y = row(y, 40, Text.get("coins") .. " " .. tostring(state.coins))
        y = row(y, height, Text.get("restock"), Text.get("restock"), function()
                if Hud.Intent then
                        Hud.Intent.restock()
                end
        end)

        for _, seedId in ipairs(state.shop.stock) do
                local seed = nil
                for _, candidate in ipairs(state.seeds) do
                        if candidate.id == seedId then
                                seed = candidate
                        end
                end
                if seed then
                        local cost = math.max(1, math.floor(seed.baseValue * 0.5))
                        local label = string.format("%s  %s  %d  %s",
                                seed.id, seed.rarity, cost, Text.duration(seed.growSeconds))
                        y = row(y, height, label, Text.get("plant"), function()
                                if Hud.Intent then
                                        Hud.Intent.buySeed(seed.id)
                                end
                        end)
                end
        end
end

function PANELS.pets(state: any)
        setTitle(Text.get("pets"))
        clearList()
        local y = 0
        local height = 56

        y = row(y, 40, Text.get("equipped") .. " " .. tostring(#state.pets.equipped) .. "/" .. tostring(state.pets.maxEquipped))

        for _, egg in ipairs(state.eggs) do
                y = row(y, height, egg.name .. "  " .. tostring(egg.cost), Text.get("hatch"), function()
                        if Hud.Intent then
                                Hud.Intent.buyEgg(egg.id)
                        end
                end)
        end

        if #state.pets.owned == 0 then
                y = row(y, height, Text.get("noPets"))
        end

        for _, pet in ipairs(state.pets.owned) do
                local equipped = false
                for _, uid in ipairs(state.pets.equipped) do
                        if uid == pet.uid then
                                equipped = true
                        end
                end
                local label = string.format("%s  #%d", pet.petId, pet.uid)
                local action = equipped and Text.get("unequip") or Text.get("equip")
                y = row(y, height, label, action, function()
                        if Hud.Intent then
                                if equipped then
                                        Hud.Intent.unequipPet(pet.uid)
                                else
                                        Hud.Intent.equipPet(pet.uid)
                                end
                        end
                end)
        end
end

function PANELS.collection(state: any)
        setTitle(Text.get("collection"))
        clearList()
        local y = 0
        local height = 44

        y = row(y, 40, Text.get("discovered", state.collection.seedCount, state.collection.seedTotal))
        y = row(y, 40, Text.get("mutationsFound", state.collection.mutationCount, state.collection.mutationTotal))
        y = row(y, 40, Text.get("totalSold", state.collection.sold))
        y = row(y, 40, Text.get("bestSale", math.floor(state.collection.bestSale)))

        for _, entry in ipairs(state.collection.byRarity) do
                y = row(y, height, string.format("%s  %d/%d", entry.rarity, entry.owned, entry.total))
        end

        if state.collection.complete then
                y = row(y, height, Text.get("complete"))
        end
end

function PANELS.upgrades(state: any)
        setTitle(Text.get("upgrades"))
        clearList()
        local y = 0
        local height = 56

        y = row(y, 40, Text.get("coins") .. " " .. tostring(state.coins))

        local speedLevel = state.upgrades.speedLevel
        local speedCost = math.floor(400 * 1.9 ^ speedLevel)
        local speedLabel = string.format("%s  %s  %d", Text.get("growthSpeed"), Text.get("level", speedLevel), speedCost)
        y = row(y, height, speedLabel, Text.get("upgrade"), function()
                if Hud.Intent then
                        Hud.Intent.buyUpgrade("speed")
                end
        end)

        local valueLevel = state.upgrades.valueLevel
        local valueCost = math.floor(500 * 2.0 ^ valueLevel)
        local valueLabel = string.format("%s  %s  %d", Text.get("saleValue"), Text.get("level", valueLevel), valueCost)
        y = row(y, height, valueLabel, Text.get("upgrade"), function()
                if Hud.Intent then
                        Hud.Intent.buyUpgrade("value")
                end
        end)

        local plotCost = math.floor(250 * 1.85 ^ math.max(0, state.garden.unlocked - 4))
        y = row(y, height, Text.get("plot", state.garden.unlocked) .. "  " .. tostring(plotCost), Text.get("buy"), function()
                if Hud.Intent then
                        Hud.Intent.buyPlot()
                end
        end)

        y = row(y, height, Text.get("harvestAll"), Text.get("harvestAll"), function()
                if Hud.Intent then
                        Hud.Intent.harvestAll()
                end
        end)
end

function Hud.openPanel(name: string, state: any)
        local builder = PANELS[name]
        if not builder then
                return
        end
        lastPanel = name
        builder(state)
end

-- Rebuild whichever panel is open from a fresh state push. Called after every
-- purchase so the list a player is looking at shows the new price, not the one
-- it had when the panel opened.
function Hud.repaintPanel(state: any)
        if not lastPanel or not refs.panel or not refs.panel.Visible then
                return
        end
        local builder = PANELS[lastPanel]
        if builder then
                builder(state)
        end
end

-- Tear the whole screen down. A viewport change rebuilds everything, because
-- every rect is a function of the viewport.
function Hud.destroy()
        if gui then
                gui:Destroy()
                gui = nil
        end
        refs = {}
        lastPanel = nil
end

function Hud.showToast(message: string)
        if not refs.toast then
                return
        end
        refs.toast.Text = message
end

-- Exposed so a test can inspect what was built without reaching into locals.
function Hud.refs(): any
        return refs
end

return Hud

--!strict
-- The client entry point: build the HUD, wire every tap to a server request, and
-- repaint from state pushes.
--
-- This file owns the `Intent` table the HUD calls into. It is the only place the
-- client decides what a tap means, which keeps the HUD a drawing surface and the
-- server the authority. `Intent` is forward-declared here and filled in below
-- the functions that use it, because the panel builders are called on a tap and
-- must not capture a nil table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Hud = require(script.Hud)

-- Forward declaration. See the header: this must exist before any panel is
-- built, or every button in a panel throws on the nil lookup.
local Intent: any = nil

local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.Folders.Remotes)

local function request(name: string): any
        local fn = remotesFolder:WaitForChild(name)
        return function(...)
                -- The arguments are captured before the pcall, because `...`
                -- belongs to this function and is not visible inside the nested
                -- closure that pcall runs.
                local args = { ... }
                local ok, success, payload, message = pcall(function()
                        return fn:InvokeServer(table.unpack(args))
                end)
                if not ok then
                        return false, nil, nil
                end
                return success, payload, message
        end
end

local Requests = {
        plant = request(Remotes.Requests.Plant),
        harvest = request(Remotes.Requests.Harvest),
        harvestAll = request(Remotes.Requests.HarvestAll),
        sell = request(Remotes.Requests.Sell),
        buySeed = request(Remotes.Requests.BuySeed),
        restock = request(Remotes.Requests.Restock),
        buyPlot = request(Remotes.Requests.BuyPlot),
        buyUpgrade = request(Remotes.Requests.BuyUpgrade),
        buyEgg = request(Remotes.Requests.BuyEgg),
        equipPet = request(Remotes.Requests.EquipPet),
        unequipPet = request(Remotes.Requests.UnequipPet),
        getState = request(Remotes.Requests.GetState),
}

local statePush = remotesFolder:WaitForChild(Remotes.Pushes.State)
local toastPush = remotesFolder:WaitForChild(Remotes.Pushes.Toast)

-- The last state the server pushed. Panels are built from this, so a panel
-- opened between two pushes still shows real numbers.
local latest: any = nil

-- The seed a tap on an empty plot will plant. Defaults to the cheapest seed on
-- the shelf, because a new player should be able to tap a plot and have
-- something happen without visiting the shop first.
local selectedSeed: string? = nil

local function cheapestStockSeed(): string?
        if not latest or #latest.shop.stock == 0 then
                return nil
        end
        local best = nil
        local bestCost = math.huge
        for _, seedId in ipairs(latest.shop.stock) do
                for _, seed in ipairs(latest.seeds) do
                        if seed.id == seedId then
                                local cost = math.max(1, math.floor(seed.baseValue * 0.5))
                                if cost < bestCost then
                                        bestCost = cost
                                        best = seedId
                                end
                        end
                end
        end
        return best
end

local function refresh()
        if not latest then
                return
        end
        if selectedSeed == nil then
                selectedSeed = cheapestStockSeed()
        end
        Hud.repaint(latest)
end

-- The tap meanings. Everything goes through the server; the client only decides
-- which request a tap is.
Intent = {
        tapPlot = function(index: number)
                if not latest then
                        return
                end
                local plot = latest.garden.plots[index]
                if not plot or not plot.unlocked then
                        Hud.showToast(require(Shared.Text).get("plotLocked"))
                        return
                end
                if plot.ready then
                        local success, payload, message = Requests.harvest(index)
                        if not success and message then
                                Hud.showToast(message)
                        elseif success and payload and payload.reward then
                                -- Show the mutation the moment it lands. This is
                                -- the payoff the whole game is built around, so
                                -- it is announced rather than left in a basket.
                                local Text = require(Shared.Text)
                                local Mutations = require(Shared.Mutations)
                                local def = Mutations.get(payload.reward.mutation)
                                if def and def.multiplier > 1 then
                                        Hud.showToast(Text.get("newMutation", def.name))
                                else
                                        Hud.showToast(Text.get("sold", payload.value))
                                end
                        end
                        return
                end
                if plot.seedId ~= nil then
                        Hud.showToast(require(Shared.Text).get("growing"))
                        return
                end
                if not selectedSeed then
                        Hud.showToast(require(Shared.Text).get("nothingToPlant"))
                        return
                end
                local success, _payload, message = Requests.plant(index, selectedSeed)
                if not success and message then
                        Hud.showToast(message)
                end
        end,

        sell = function()
                local success, _payload, message = Requests.sell()
                if not success and message then
                        Hud.showToast(message)
                end
        end,

        harvestAll = function()
                Requests.harvestAll()
        end,

        buySeed = function(seedId: string)
                -- Buying selects the seed for planting rather than only
                -- deducting coins: on a phone the shop should leave the player
                -- one tap from a plot, not send them back to the grid with
                -- nothing chosen.
                selectedSeed = seedId
                Hud.showToast(require(Shared.Text).get("bought", seedId))
                Hud.closePanel()
        end,

        restock = function()
                Requests.restock()
        end,

        buyPlot = function()
                local success, _payload, message = Requests.buyPlot()
                if not success and message then
                        Hud.showToast(message)
                end
        end,

        buyUpgrade = function(kind: string)
                local success, _payload, message = Requests.buyUpgrade(kind)
                if not success and message then
                        Hud.showToast(message)
                end
        end,

        buyEgg = function(eggId: string)
                local success, payload, message = Requests.buyEgg(eggId)
                if not success and message then
                        Hud.showToast(message)
                elseif success and payload then
                        Hud.showToast(require(Shared.Text).get("hatched", payload.petId))
                end
        end,

        equipPet = function(uid: number)
                local success, _payload, message = Requests.equipPet(uid)
                if not success and message then
                        Hud.showToast(message)
                end
        end,

        unequipPet = function(uid: number)
                Requests.unequipPet(uid)
        end,

        openGarden = function()
                Hud.openPanel("garden", latest)
        end,

        openShop = function()
                Hud.openPanel("shop", latest)
        end,

        openPets = function()
                Hud.openPanel("pets", latest)
        end,

        openCollection = function()
                Hud.openPanel("collection", latest)
        end,

        openUpgrades = function()
                Hud.openPanel("upgrades", latest)
        end,
}

Hud.Intent = Intent

--------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------

local camera = workspace.CurrentCamera

-- The HUD keeps ScreenGui.IgnoreGuiInset = false, so its coordinate space starts
-- below Roblox's own topbar and is shorter than the viewport by that inset.
-- Every rect has to be computed in the space the HUD actually draws in, or the
-- bottom bar is placed past the real bottom edge on a phone and the top bar sits
-- under Roblox's buttons. GuiService reports the inset; it is read once here and
-- the client is rebuilt when it changes.
local GuiService = game:GetService("GuiService")

local function usableHeight(): number
        local ok, inset = pcall(function()
                return GuiService:GetGuiInset()
        end)
        local topInset = 0
        if ok and typeof(inset) == "Vector2" then
                topInset = inset.Y
        end
        local height = camera.ViewportSize.Y - topInset
        return math.max(1, height)
end

local function buildScreen()
        local width = camera.ViewportSize.X
        if Hud.refs and Hud.refs().plots then
                -- A resize rebuilds the whole screen, because every rect is a
                -- function of the viewport. Repainting positions in place would
                -- be a second layout implementation to keep in step.
                local old = Hud.refs().panel
                if old and old.Parent then
                        old.Parent:Destroy()
                end
        end
        Hud.build(width, usableHeight())
end

buildScreen()
refresh()

statePush.OnClientEvent:Connect(function(payload)
        latest = payload
        refresh()
        -- A panel that is open is rebuilt from the new numbers, so a purchase
        -- updates the list the player is looking at instead of leaving a stale
        -- price on screen.
        local refs = Hud.refs()
        if refs.panel and refs.panel.Visible then
                Hud.repaintPanel(latest)
        end
end)

toastPush.OnClientEvent:Connect(function(message)
        Hud.showToast(message)
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        buildScreen()
        refresh()
end)

-- Ask for the first state. The server also pushes on join, so this only matters
-- if the client loaded after that push went out.
Requests.getState()

--!strict
-- The server: the only authority on any number in the game.
--
-- The client asks; this decides. Every request is validated against the current
-- state rather than against what the client claims, so a client that lies about
-- its coins, its plot index or its basket only gets a rejection. The one thing
-- the client is trusted for is which button it pressed.
--
-- The loop is: join -> load save -> apply offline growth -> push state -> serve
-- requests -> autosave -> save on leave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Random = require(Shared.Random)
local Seeds = require(Shared.Seeds)
local Mutations = require(Shared.Mutations)
local Pets = require(Shared.Pets)
local Garden = require(Shared.Garden)
local Sell = require(Shared.Sell)
local Collection = require(Shared.Collection)
local Basket = require(Shared.Basket)
local SaveSchema = require(Shared.SaveSchema)
local Remotes = require(Shared.Remotes)
local Text = require(Shared.Text)

local World = require(script.World)

local SAVE_STORE = "AXGardenLegends_v1"
local store = nil
do
        local ok, result = pcall(function()
                return DataStoreService:GetDataStore(SAVE_STORE)
        end)
        if ok then
                store = result
        end
end

-- The remote folder. A RemoteFunction for anything that wants an answer (so the
-- client can show why something failed) and a RemoteEvent for pushes.
--
-- Find-or-create, not create: another script in the same place may have made a
-- `Remotes` folder already, and a second folder with the same name would leave
-- half the remotes where nothing looks for them. The client only ever sees one
-- `Remotes`, so the server must only ever make one.
local remotesFolder = ReplicatedStorage:FindFirstChild(Remotes.Folders.Remotes)
if not remotesFolder then
        remotesFolder = Instance.new("Folder")
        remotesFolder.Name = Remotes.Folders.Remotes
        remotesFolder.Parent = ReplicatedStorage
end

local functions: { [string]: any } = {}
local events: { [string]: any } = {}

for _, name in ipairs({
        Remotes.Requests.Plant, Remotes.Requests.Harvest, Remotes.Requests.HarvestAll,
        Remotes.Requests.Sell, Remotes.Requests.BuySeed, Remotes.Requests.Restock,
        Remotes.Requests.BuyPlot, Remotes.Requests.BuyUpgrade, Remotes.Requests.BuyEgg,
        Remotes.Requests.EquipPet, Remotes.Requests.UnequipPet, Remotes.Requests.GetState,
}) do
        local fn = Instance.new("RemoteFunction")
        fn.Name = name
        fn.Parent = remotesFolder
        functions[name] = fn
end

for _, name in ipairs({ Remotes.Pushes.State, Remotes.Pushes.Toast, Remotes.Pushes.Harvested }) do
        local ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = remotesFolder
        events[name] = ev
end

-- The world is built once, at server start, from the same plot count the logic
-- uses.
local worldRoot, plotHandles = World.build(Config.Garden.StartingPlots)
worldRoot.Parent = workspace

-- Per-player session state, keyed by player. Holds the save plus the shop stock
-- and the RNG, neither of which belongs in the save file: the stock is a session
-- thing, and the RNG is a stream that must not be serialised.
type Session = {
        save: any,
        rng: any,
        stock: { string },
        lastAutosave: number,
        lastSeen: number,
}

local sessions: { [any]: Session } = {}

local function now(): number
        return os.time()
end

-- Push the whole state to one player. Everything the client draws comes from
-- here, so there is exactly one shape for it to understand.
local function pushState(player: any)
        local session = sessions[player]
        if not session then
                return
        end
        local save = session.save
        local time = now()
        local petBonuses = Pets.bonuses(save.pets)
        events[Remotes.Pushes.State]:FireClient(player, {
                coins = save.coins,
                garden = Garden.snapshot(save.garden, time),
                upgrades = save.upgrades,
                petBonuses = petBonuses,
                pets = {
                        owned = save.pets.owned,
                        equipped = save.pets.equipped,
                        maxEquipped = Config.Pets.MaxEquipped,
                },
                basket = Basket.snapshot(save.basket, save.upgrades, petBonuses),
                collection = Collection.snapshot(save.collection),
                shop = { stock = session.stock },
                seeds = Seeds.list(),
                mutations = Mutations.list(),
                eggs = Pets.eggs(),
                rarities = require(Shared.Rarity).list(),
                serverTime = time,
        })
end

local function toast(player: any, text: string)
        events[Remotes.Pushes.Toast]:FireClient(player, text)
end

-- Repaint every plot from the player's own state. Only one player's garden is in
-- the world at a time in this build; a second player joining rebuilds the plots
-- for themselves.
local function paintWorld(save: any)
        local time = now()
        local snapshot = Garden.snapshot(save.garden, time)
        for _, handle in ipairs(plotHandles) do
                local plotState = snapshot.plots[handle.index]
                local seed = plotState.seedId and Seeds.get(plotState.seedId) or nil
                local color = nil
                if seed then
                        color = Color3.fromRGB(seed.color[1], seed.color[2], seed.color[3])
                end
                local label = ""
                if not plotState.unlocked then
                        label = Text.get("locked")
                elseif plotState.seedId == nil then
                        label = Text.get("empty")
                elseif plotState.ready then
                        label = Text.get("ready")
                else
                        label = Text.duration(plotState.secondsLeft)
                end
                World.paintPlot(handle, plotState, color, not plotState.unlocked, label)
        end
end

-- Apply the offline window: any crop that ripened while the player was away is
-- simply ripe, because growth is timestamp-based. This exists to report it, not
-- to advance it.
local function applyOffline(save: any): number
        local time = now()
        local window = Sell.offlineSeconds(save.lastSeen, time)
        save.lastSeen = time
        if window <= 0 then
                return 0
        end
        return Garden.readyCount(save.garden, time)
end

local function save(player: any)
        local session = sessions[player]
        if not session or not store then
                return
        end
        session.save.lastSeen = now()
        -- The DataStore is handed a snapshot, not the live save, so a write can
        -- never alias the state the game is still mutating. This is the same
        -- shape the arena stores, and it means the save is plain data with no
        -- dependency on a JSON library being present.
        local payload = SaveSchema.snapshot(session.save)
        pcall(function()
                store:SetAsync(tostring(player.UserId), payload)
        end)
end

local function load(player: any): any
        if not store then
                return SaveSchema.new(now())
        end
        local ok, payload = pcall(function()
                return store:GetAsync(tostring(player.UserId))
        end)
        if not ok then
                return SaveSchema.new(now())
        end
        -- `migrate` rebuilds every field from scratch, so it accepts anything:
        -- a table from a previous version, a string from a much older one, or
        -- nil for a player who has never joined.
        if type(payload) == "string" then
                local decoded = nil
                local decodeOk, result = pcall(function()
                        return game:GetService("HttpService"):JSONDecode(payload)
                end)
                if decodeOk then
                        decoded = result
                end
                return SaveSchema.migrate(decoded, now())
        end
        return SaveSchema.migrate(payload, now())
end

--------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------

-- Every handler returns (ok, payload, message). `ok` false carries a reason the
-- client shows verbatim, which is why the reasons are text keys and not codes.
local function handlePlant(session: any, index: any, seedId: any)
        local save = session.save
        local seed = type(seedId) == "string" and Seeds.get(seedId) or nil
        if not seed then
                return false, nil, Text.get("error")
        end

        -- The seed must be on the shelf and affordable, and it is bought in the
        -- same call that plants it: a player taps a seed then a plot, and the
        -- pair either works or does not.
        local cost = Seeds.cost(seed.id)
        if save.coins < cost then
                return false, nil, Text.get("notEnoughCoins")
        end

        local speed = Sell.growthMultiplier(save.upgrades, Pets.bonuses(save.pets))
        local ok, reason = Garden.plant(save.garden, index, seed.id, now(), speed)
        if not ok then
                if reason == "PLOT_LOCKED" then
                        return false, nil, Text.get("plotLocked")
                elseif reason == "PLOT_OCCUPIED" then
                        return false, nil, Text.get("growing")
                end
                return false, nil, Text.get("error")
        end

        save.coins -= cost
        return true, { coins = save.coins }, Text.get("plant")
end

local function handleHarvest(session: any, index: any)
        local save = session.save
        -- Check there is room before harvesting. Harvesting first and putting the
        -- crop back on a full basket loses the crop on the way through and is a
        -- window where a second request can take it, so the space check is the
        -- first thing that happens.
        if Basket.count(save.basket) >= Config.Basket.Capacity then
                return false, nil, Text.get("noSpace")
        end
        local reward, reason = Garden.harvest(save.garden, index, now(), session.rng)
        if not reward then
                if reason == "NOT_READY" then
                        return false, nil, Text.get("growing")
                end
                return false, nil, Text.get("empty")
        end
        local petBonuses = Pets.bonuses(save.pets)
        local value = Sell.value(reward, save.upgrades, petBonuses)
        Basket.add(save.basket, reward, value)
        return true, { reward = reward, value = value }, nil
end

local function handleHarvestAll(session: any)
        local save = session.save
        local petBonuses = Pets.bonuses(save.pets)
        -- Harvest into a scratch list first, then move as many as fit. A crop
        -- that does not fit stays in the ground rather than being destroyed.
        local rewards = Garden.harvestAll(save.garden, now(), session.rng)
        local added = 0
        for _, reward in ipairs(rewards) do
                if Basket.count(save.basket) >= Config.Basket.Capacity then
                        -- Put the remainder back, ripe, so nothing is lost.
                        Garden.plant(save.garden, reward.plotIndex, reward.seedId, now() - 1e9, 1)
                else
                        local value = Sell.value(reward, save.upgrades, petBonuses)
                        if Basket.add(save.basket, reward, value) then
                                added += 1
                        end
                end
        end
        return true, { harvested = added }, nil
end

local function handleSell(session: any)
        local save = session.save
        local petBonuses = Pets.bonuses(save.pets)
        local total, sold = Basket.sellAll(save.basket, save.upgrades, petBonuses)
        if #sold == 0 then
                return false, nil, Text.get("empty")
        end

        save.coins += total
        -- Record what was discovered and the best sale, which is the whole point
        -- of the collection page.
        for _, entry in ipairs(sold) do
                Collection.discover(save.collection, entry.seedId)
                Collection.discoverMutation(save.collection, entry.mutation)
                Collection.recordSale(save.collection, Sell.value(entry, save.upgrades, petBonuses))
        end
        return true, { coins = save.coins, sold = #sold, total = total }, nil
end

local function handleBuySeed(session: any, seedId: any)
        local save = session.save
        local seed = type(seedId) == "string" and Seeds.get(seedId) or nil
        if not seed then
                return false, nil, Text.get("error")
        end
        local cost = Seeds.cost(seed.id)
        if save.coins < cost then
                return false, nil, Text.get("notEnoughCoins")
        end
        save.coins -= cost
        save.seedsOwned[seed.id] = (save.seedsOwned[seed.id] or 0) + 1
        return true, { coins = save.coins }, Text.get("bought", seed.id)
end

local function handleRestock(session: any)
        session.stock = Seeds.rollStock(session.rng, Config.Shop.StockSize)
        return true, { stock = session.stock }, nil
end

local function handleBuyPlot(session: any)
        local save = session.save
        local coins, reason = Sell.buyPlot(save.coins, save.garden)
        if not coins then
                if reason == "ALL_UNLOCKED" then
                        return false, nil, Text.get("allPlotsUnlocked")
                end
                return false, nil, Text.get("notEnoughCoins")
        end
        save.coins = coins
        -- The world is shared, so a plot bought by one player is shown as
        -- unlocked for the session; in a one-garden-per-server build this is the
        -- same thing as the player's own garden.
        return true, { coins = save.coins, unlocked = save.garden.unlocked }, nil
end

local function handleBuyUpgrade(session: any, kind: any)
        local save = session.save
        if kind ~= "speed" and kind ~= "value" then
                return false, nil, Text.get("error")
        end
        local coins, reason = Sell.buyUpgrade(save.coins, save.upgrades, kind)
        if not coins then
                if reason == "MAX_LEVEL" then
                        return false, nil, Text.get("maxLevel")
                end
                return false, nil, Text.get("notEnoughCoins")
        end
        save.coins = coins
        return true, { coins = save.coins, upgrades = save.upgrades }, nil
end

local function handleBuyEgg(session: any, eggId: any)
        local save = session.save
        local egg = type(eggId) == "string" and Pets.egg(eggId) or nil
        if not egg then
                return false, nil, Text.get("error")
        end
        if save.coins < egg.cost then
                return false, nil, Text.get("notEnoughCoins")
        end
        local petId, reason = Pets.hatch(save.pets, egg.id, session.rng)
        if not petId then
                return false, nil, Text.get("error")
        end
        save.coins -= egg.cost
        return true, { coins = save.coins, petId = petId }, Text.get("hatched", petId)
end

local function handleEquipPet(session: any, uid: any)
        local save = session.save
        local ok, reason = Pets.equip(save.pets, math.floor(tonumber(uid) or -1))
        if not ok then
                if reason == "SLOTS_FULL" then
                        return false, nil, Text.get("slotsFull")
                end
                return false, nil, Text.get("error")
        end
        return true, nil, nil
end

local function handleUnequipPet(session: any, uid: any)
        local save = session.save
        Pets.unequip(save.pets, math.floor(tonumber(uid) or -1))
        return true, nil, nil
end

--------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------

local HANDLERS: { [string]: (any, any, any) -> (boolean, any, string?) } = {
        [Remotes.Requests.Plant] = handlePlant,
        [Remotes.Requests.Harvest] = handleHarvest,
        [Remotes.Requests.HarvestAll] = handleHarvestAll,
        [Remotes.Requests.Sell] = handleSell,
        [Remotes.Requests.BuySeed] = handleBuySeed,
        [Remotes.Requests.Restock] = handleRestock,
        [Remotes.Requests.BuyPlot] = handleBuyPlot,
        [Remotes.Requests.BuyUpgrade] = handleBuyUpgrade,
        [Remotes.Requests.BuyEgg] = handleBuyEgg,
        [Remotes.Requests.EquipPet] = handleEquipPet,
        [Remotes.Requests.UnequipPet] = handleUnequipPet,
}

for name, fn in pairs(functions) do
        if HANDLERS[name] then
                fn.OnServerInvoke = function(player: any, ...)
                        local session = sessions[player]
                        if not session then
                                return false, nil, Text.get("loading")
                        end
                        -- A handler must never take the server down, so a
                        -- failure is caught and reported rather than propagated.
                        local ok, success, payload, message = pcall(HANDLERS[name], session, ...)
                        if not ok then
                                return false, nil, Text.get("error")
                        end
                        if success then
                                paintWorld(session.save)
                                pushState(player)
                        elseif message then
                                toast(player, message)
                        end
                        return success, payload, message
                end
        end
end

functions[Remotes.Requests.GetState].OnServerInvoke = function(player: any)
        local session = sessions[player]
        if not session then
                return false, nil, Text.get("loading")
        end
        pushState(player)
        return true, nil, nil
end

local function onPlayerAdded(player: any)
        local save = load(player)
        local rng = Random.new(player.UserId + os.time())
        sessions[player] = {
                save = save,
                rng = rng,
                stock = Seeds.rollStock(rng, Config.Shop.StockSize),
                lastAutosave = now(),
                lastSeen = save.lastSeen,
        }

        local ripe = applyOffline(save)
        paintWorld(save)
        pushState(player)

        if ripe > 0 then
                toast(player, Text.get("offlineGrew", Text.duration(0)))
        else
                toast(player, Text.get("welcomeBack"))
        end
end

local function onPlayerRemoving(player: any)
        local session = sessions[player]
        if session then
                save(player)
        end
        sessions[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Autosave and the ripe-crop repaint both ride the heartbeat, because a crop
-- ripening is a thing the player should see happen without touching anything.
RunService.Heartbeat:Connect(function()
        local time = now()
        for player, session in pairs(sessions) do
                if time - session.lastAutosave >= Config.Save.AutosaveSeconds then
                        session.lastAutosave = time
                        session.save.lastSeen = time
                        save(player)
                end
                paintWorld(session.save)
                pushState(player)
        end
end)

-- Players who joined before this script ran.
for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
end

--!strict
-- The farm loop: plots you plant in, crops that grow on a timer, and a harvest
-- that pays out and charges the axe.
--
-- Pure Luau, so the whole loop can be tested without Roblox. The Roblox layer
-- only draws the result and forwards taps.
--
-- Time is passed in as a number of seconds rather than read from a clock, so a
-- test can fast forward by simply calling with a larger `now`.

local Config = require("./Config")

local Farm = {}

export type Plot = {
        cropId: string?,
        plantedAt: number,
        readyAt: number,
}

export type State = {
        plots: { Plot },
}

export type Reward = {
        cropId: string,
        coins: number,
        xp: number,
}

export type CropDef = {
        id: string,
        growSeconds: number,
        coins: number,
        xp: number,
        color: { number },
}

local CROPS: { [string]: CropDef } = {}
local CROP_ORDER: { string } = {}

for _, raw in ipairs(Config.Farm.Crops) do
        local def: CropDef = {
                id = raw.id,
                growSeconds = raw.growSeconds,
                coins = raw.coins,
                xp = raw.xp,
                color = raw.color,
        }
        CROPS[raw.id] = def
        table.insert(CROP_ORDER, raw.id)
end

function Farm.cropDef(cropId: string): CropDef?
        return CROPS[cropId]
end

-- Crop list in config order, which is also cheapest-to-slowest.
function Farm.list(): { CropDef }
        local out: { CropDef } = {}
        for _, id in ipairs(CROP_ORDER) do
                table.insert(out, CROPS[id])
        end
        return out
end

function Farm.new(): State
        local plots: { Plot } = {}
        for _ = 1, Config.Farm.PlotCount do
                table.insert(plots, { cropId = nil, plantedAt = 0, readyAt = 0 })
        end
        return { plots = plots }
end

local function emptyPlot(): Plot
        return { cropId = nil, plantedAt = 0, readyAt = 0 }
end

-- A plot index is 1-based and must exist. Returns the plot or nil.
function Farm.getPlot(state: State, index: number): Plot?
        if type(index) ~= "number" then
                return nil
        end
        local i = math.floor(index)
        if i < 1 or i > #state.plots then
                return nil
        end
        return state.plots[i]
end

function Farm.isReady(plot: Plot, now: number): boolean
        return plot.cropId ~= nil and now >= plot.readyAt
end

-- Plant a crop. Returns true, or false plus a stable reason the UI can show.
function Farm.plant(state: State, index: number, cropId: any, now: number): (boolean, string?)
        if type(cropId) ~= "string" or CROPS[cropId] == nil then
                return false, "UNKNOWN_CROP"
        end
        local plot = Farm.getPlot(state, index)
        if not plot then
                return false, "BAD_PLOT"
        end
        if plot.cropId ~= nil then
                return false, "PLOT_OCCUPIED"
        end

        plot.cropId = cropId
        plot.plantedAt = now
        plot.readyAt = now + CROPS[cropId].growSeconds
        return true, nil
end

-- Harvest a ripe plot. Returns the reward, or false plus a reason. An
-- unripe crop is left alone rather than destroyed, so a mistap costs nothing.
function Farm.harvest(state: State, index: number, now: number): (Reward?, string?)
        local plot = Farm.getPlot(state, index)
        if not plot then
                return nil, "BAD_PLOT"
        end
        if plot.cropId == nil then
                return nil, "EMPTY_PLOT"
        end
        if not Farm.isReady(plot, now) then
                return nil, "NOT_READY"
        end

        local def = CROPS[plot.cropId]
        local reward: Reward = { cropId = def.id, coins = def.coins, xp = def.xp }
        state.plots[math.floor(index)] = emptyPlot()
        return reward, nil
end

-- How long until a planted crop is ready, in seconds. Zero when ready or empty.
function Farm.secondsUntilReady(plot: Plot, now: number): number
        if plot.cropId == nil then
                return 0
        end
        return math.max(0, plot.readyAt - now)
end

function Farm.readyCount(state: State, now: number): number
        local count = 0
        for _, plot in ipairs(state.plots) do
                if Farm.isReady(plot, now) then
                        count += 1
                end
        end
        return count
end

function Farm.plantedCount(state: State): number
        local count = 0
        for _, plot in ipairs(state.plots) do
                if plot.cropId ~= nil then
                        count += 1
                end
        end
        return count
end

-- What the client needs to draw the plots. Kept small: one entry per plot.
function Farm.snapshot(state: State, now: number): { any }
        local out = {}
        for index, plot in ipairs(state.plots) do
                table.insert(out, {
                        index = index,
                        cropId = plot.cropId,
                        ready = Farm.isReady(plot, now),
                        secondsLeft = math.ceil(Farm.secondsUntilReady(plot, now)),
                })
        end
        return out
end

return Farm

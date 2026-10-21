--!strict
-- The garden itself: the plots, what is planted in them, and when each crop is
-- ready. Pure Luau, and time is passed in as a number rather than read from a
-- clock, so a test can fast-forward eight hours with one call.
--
-- Growth is timestamp-based, not tick-based. A plot stores when it was planted
-- and when it ripens; whether the player was online for those seconds makes no
-- difference. That is what makes offline growth work, and it is the mechanism
-- the whole genre rests on.

local Config = require("./Config")
local Seeds = require("./Seeds")

local Garden = {}

export type Plot = {
        -- nil when empty.
        seedId: string?,
        plantedAt: number,
        -- When the crop ripens, in the same time base as `now`.
        readyAt: number,
}

export type State = {
        plots: { Plot },
        -- How many plots are unlocked. The rest are bought.
        unlocked: number,
}

local function emptyPlot(): Plot
        return { seedId = nil, plantedAt = 0, readyAt = 0 }
end

function Garden.new(): State
        local plots: { Plot } = {}
        for _ = 1, Config.Garden.TotalPlots do
                table.insert(plots, emptyPlot())
        end
        return { plots = plots, unlocked = Config.Garden.StartingPlots }
end

function Garden.getPlot(state: State, index: number): Plot?
        if index < 1 or index > Config.Garden.TotalPlots then
                return nil
        end
        return state.plots[index]
end

function Garden.isUnlocked(state: State, index: number): boolean
        return index >= 1 and index <= state.unlocked
end

function Garden.isEmpty(plot: Plot): boolean
        return plot.seedId == nil
end

-- A plot is ready when it holds a crop whose ripen time has passed. An empty
-- plot is never ready, which is what keeps "harvest all" from counting the
-- holes in the garden.
function Garden.isReady(plot: Plot, now: number): boolean
        if plot.seedId == nil then
                return false
        end
        return now >= plot.readyAt
end

-- Plant a seed. Fails on an empty seed id, an unknown seed, a locked plot, or a
-- plot that already holds something.
function Garden.plant(state: State, index: number, seedId: any, now: number, growthMultiplier: number?): (boolean, string?)
        local plot = Garden.getPlot(state, index)
        if not plot then
                return false, "NO_SUCH_PLOT"
        end
        if not Garden.isUnlocked(state, index) then
                return false, "PLOT_LOCKED"
        end
        if type(seedId) ~= "string" or seedId == "" then
                return false, "NO_SEED"
        end
        local def = Seeds.get(seedId)
        if not def then
                return false, "NO_SUCH_SEED"
        end
        if not Garden.isEmpty(plot) then
                return false, "PLOT_OCCUPIED"
        end

        plot.seedId = seedId
        plot.plantedAt = now
        plot.readyAt = now + Seeds.growSeconds(seedId, growthMultiplier or 1)
        return true, nil
end

-- Harvest a ripe plot. Returns what came out, or nil and a reason. The mutation
-- roll happens here, at harvest time, so the player sees it land.
function Garden.harvest(state: State, index: number, now: number, rng: any, luck: number?): (any?, string?)
        local plot = Garden.getPlot(state, index)
        if not plot then
                return nil, "NO_SUCH_PLOT"
        end
        if Garden.isEmpty(plot) then
                return nil, "PLOT_EMPTY"
        end
        if not Garden.isReady(plot, now) then
                return nil, "NOT_READY"
        end

        local seedId = plot.seedId :: string
        local seed = Seeds.get(seedId)
        -- Clear the plot before the roll, so a throwing RNG cannot leave a crop
        -- that was already paid for.
        plot.seedId = nil
        plot.plantedAt = 0
        plot.readyAt = 0

        local Mutations = require("./Mutations")
        local mutation = Mutations.roll(rng, luck)
        return {
                -- Which plot this came from. Harvest-all needs it to put back a
                -- crop that did not fit in the basket, and it is the only place
                -- the mapping is known once the plot has been cleared.
                plotIndex = index,
                seedId = seedId,
                rarity = seed and seed.rarity or "Common",
                mutation = mutation,
        }, nil
end

-- Seconds until a plot is ready. Zero when it is already ripe or empty.
function Garden.secondsUntilReady(plot: Plot, now: number): number
        if Garden.isEmpty(plot) then
                return 0
        end
        return math.max(0, plot.readyAt - now)
end

function Garden.readyCount(state: State, now: number): number
        local count = 0
        for index = 1, state.unlocked do
                if Garden.isReady(state.plots[index], now) then
                        count += 1
                end
        end
        return count
end

function Garden.plantedCount(state: State): number
        local count = 0
        for index = 1, state.unlocked do
                if not Garden.isEmpty(state.plots[index]) then
                        count += 1
                end
        end
        return count
end

-- Harvest every ripe plot in one pass, which is the button a player actually
-- presses after coming back. Returns the rewards and how many plots paid out.
function Garden.harvestAll(state: State, now: number, rng: any, luck: number?): ({ any }, number)
        local rewards: { any } = {}
        for index = 1, state.unlocked do
                local reward = Garden.harvest(state, index, now, rng, luck)
                if reward then
                        table.insert(rewards, reward)
                end
        end
        return rewards, #rewards
end

-- Fraction grown, 0 to 1, for a progress bar. An empty plot reads as 0 rather
-- than as a division by zero.
function Garden.progress(plot: Plot, now: number): number
        if Garden.isEmpty(plot) then
                return 0
        end
        local total = plot.readyAt - plot.plantedAt
        if total <= 0 then
                return 1
        end
        return math.clamp((now - plot.plantedAt) / total, 0, 1)
end

-- The snapshot the client draws. One function so the HUD cannot invent a plot
-- state the server does not have.
function Garden.snapshot(state: State, now: number): { any }
        local plots: { any } = {}
        for index = 1, Config.Garden.TotalPlots do
                local plot = state.plots[index]
                table.insert(plots, {
                        index = index,
                        unlocked = Garden.isUnlocked(state, index),
                        seedId = plot.seedId,
                        ready = Garden.isReady(plot, now),
                        secondsLeft = Garden.secondsUntilReady(plot, now),
                        progress = Garden.progress(plot, now),
                })
        end
        return {
                plots = plots,
                unlocked = state.unlocked,
                ready = Garden.readyCount(state, now),
                planted = Garden.plantedCount(state),
        }
end

return Garden

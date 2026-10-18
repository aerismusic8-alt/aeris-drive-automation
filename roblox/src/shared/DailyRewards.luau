--!strict
-- Daily login rewards. Pure Luau: no Roblox globals.
--
-- Retention is what makes a game trend, and a daily reason to return is the
-- cheapest form of it. The streak is the point: missing a day resets it, so
-- players come back even when they do not feel like farming.

local Config = require("./Config")

local DailyRewards = {}

export type State = {
	streak: number,
	lastClaimAt: number,
	totalClaims: number,
}

export type Reward = {
	coins: number,
	xp: number,
	luckCharges: number,
	day: number,
}

local DAY_SECONDS = 24 * 60 * 60

function DailyRewards.new(): State
	return { streak = 0, lastClaimAt = 0, totalClaims = 0 }
end

-- Reward for a given day in the streak. Day 1 is the first claim.
function DailyRewards.rewardForDay(day: number): Reward
	local cfg = Config.Daily
	local d = math.max(1, math.floor(day))

	-- Past the configured cycle the rewards keep climbing rather than repeating,
	-- so a long streak never becomes worthless.
	local cyclePos = ((d - 1) % cfg.CycleLength) + 1
	local cycles = math.floor((d - 1) / cfg.CycleLength)

	local base = cfg.Rewards[cyclePos]
	assert(base ~= nil, "daily reward table is missing day " .. cyclePos)

	local scale = cfg.CycleGrowth ^ cycles
	return {
		coins = math.floor(base.coins * scale + 0.5),
		xp = math.floor(base.xp * scale + 0.5),
		luckCharges = base.luckCharges or 0,
		day = d,
	}
end

-- Seconds since the last claim. math.huge when never claimed.
function DailyRewards.sinceLastClaim(state: State, now: number): number
	if state.lastClaimAt <= 0 then
		return math.huge
	end
	return math.max(0, now - state.lastClaimAt)
end

-- Can this player claim right now?
function DailyRewards.canClaim(state: State, now: number): (boolean, string)
	local cfg = Config.Daily
	local elapsed = DailyRewards.sinceLastClaim(state, now)

	if elapsed == math.huge then
		return true, "FIRST_CLAIM"
	end

	if elapsed < cfg.CooldownSeconds then
		return false, "TOO_SOON"
	end

	return true, "READY"
end

-- Seconds until the next claim is allowed. Zero when ready now.
function DailyRewards.timeUntilClaim(state: State, now: number): number
	local cfg = Config.Daily
	local elapsed = DailyRewards.sinceLastClaim(state, now)
	if elapsed == math.huge then
		return 0
	end
	return math.max(0, cfg.CooldownSeconds - elapsed)
end

-- Claim the reward. Returns the new state and the reward, or nil plus a reason.
-- A gap longer than the grace window breaks the streak back to day one.
function DailyRewards.claim(state: State, now: number): (State?, Reward?, string?)
	local ok, reason = DailyRewards.canClaim(state, now)
	if not ok then
		return nil, nil, reason
	end

	local cfg = Config.Daily
	local elapsed = DailyRewards.sinceLastClaim(state, now)

	local streak
	if elapsed == math.huge then
		streak = 1
	elseif elapsed > cfg.StreakGraceSeconds then
		-- Missed too long: start over rather than pretend the streak held.
		streak = 1
	else
		streak = math.min(state.streak + 1, cfg.MaxStreak)
	end

	local reward = DailyRewards.rewardForDay(streak)
	local next: State = {
		streak = streak,
		lastClaimAt = now,
		totalClaims = state.totalClaims + 1,
	}
	return next, reward, nil
end

function DailyRewards.snapshot(state: State): State
	return {
		streak = math.max(0, math.floor(tonumber(state.streak) or 0)),
		lastClaimAt = math.max(0, math.floor(tonumber(state.lastClaimAt) or 0)),
		totalClaims = math.max(0, math.floor(tonumber(state.totalClaims) or 0)),
	}
end

-- Rebuild from a save. Bad or missing data yields a fresh state rather than
-- an error, so an old save never blocks a player from logging in.
function DailyRewards.fromSnapshot(raw: any): State
	local fresh = DailyRewards.new()
	if type(raw) ~= "table" then
		return fresh
	end
	local snap = DailyRewards.snapshot({
		streak = raw.streak,
		lastClaimAt = raw.lastClaimAt,
		totalClaims = raw.totalClaims,
	})
	if snap.streak > Config.Daily.MaxStreak then
		snap.streak = Config.Daily.MaxStreak
	end
	return snap
end

DailyRewards.DAY_SECONDS = DAY_SECONDS

return DailyRewards

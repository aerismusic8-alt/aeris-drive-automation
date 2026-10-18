--!strict
-- Rebirth (prestige) system. Pure Luau.
--
-- Rebirth is the long-term retention loop: it wipes progress in exchange for
-- a permanent multiplier, so the player replays the early game faster and
-- stronger. It is also the natural place to attach a paid skip.

local Config = require("./Config")

local Rebirth = {}

export type State = {
	count: number,
}

function Rebirth.new(): State
	return { count = 0 }
end

-- Level needed for the next rebirth, given how many are already done.
function Rebirth.levelRequirement(count: number): number
	local cfg = Config.Rebirth
	local c = math.max(0, math.floor(count))
	if c >= cfg.MaxRebirths then
		return math.huge
	end
	return math.floor(cfg.BaseLevelRequirement * (cfg.LevelGrowth ^ c) + 0.5)
end

-- Check whether a rebirth is allowed. Returns (ok, reason).
function Rebirth.canRebirth(state: State, level: number): (boolean, string?)
	local cfg = Config.Rebirth
	if state.count >= cfg.MaxRebirths then
		return false, "MAX_REBIRTHS"
	end
	local required = Rebirth.levelRequirement(state.count)
	if level < required then
		return false, "LEVEL_TOO_LOW"
	end
	return true, nil
end

-- Permanent multipliers granted by the current rebirth count.
-- Returns (coinMultiplier, damageMultiplier).
function Rebirth.multipliers(count: number): (number, number)
	local cfg = Config.Rebirth
	local c = math.max(0, math.min(math.floor(count), cfg.MaxRebirths))
	return 1 + cfg.CoinMultiplierPerRebirth * c, 1 + cfg.DamageMultiplierPerRebirth * c
end

-- Perform a rebirth. Returns the new state plus the fresh starting values the
-- caller should apply. Returns nil plus a reason when not allowed.
export type Outcome = {
	state: State,
	coins: number,
	level: number,
	xp: number,
	resetUpgrades: boolean,
}

function Rebirth.perform(state: State, level: number): (Outcome?, string?)
	local ok, reason = Rebirth.canRebirth(state, level)
	if not ok then
		return nil, reason
	end

	local cfg = Config.Rebirth
	local next: State = { count = state.count + 1 }

	return {
		state = next,
		coins = cfg.StartingCoinsAfterRebirth,
		level = 1,
		xp = 0,
		resetUpgrades = cfg.ResetUpgrades,
	}, nil
end

function Rebirth.fromSnapshot(data: any): State
	if type(data) ~= "table" then
		return Rebirth.new()
	end
	local count = math.floor(tonumber(data.count) or 0)
	return { count = math.clamp(count, 0, Config.Rebirth.MaxRebirths) }
end

return Rebirth

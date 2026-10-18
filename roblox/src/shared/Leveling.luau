--!strict
-- Level and XP progression. Pure Luau: no Roblox globals.
--
-- Levels gate rebirths and zone unlocks, and each level grants a small
-- permanent coin bonus so farming always feels like it moves forward.

local Config = require("./Config")

local Leveling = {}

export type Progress = {
	level: number,
	xp: number,
}

-- XP required to advance from `level` to `level + 1`.
-- Returns math.huge at the level cap so callers can treat it as "no more".
function Leveling.xpForNext(level: number): number
	local cfg = Config.Leveling
	local clamped = math.max(1, math.floor(level))
	if clamped >= cfg.MaxLevel then
		return math.huge
	end
	return math.floor(cfg.BaseXp * (cfg.XpGrowth ^ (clamped - 1)) + 0.5)
end

-- Total XP needed to reach `level` from level 1. Used for UI progress bars.
function Leveling.totalXpToReach(level: number): number
	local total = 0
	for l = 1, math.max(1, math.floor(level)) - 1 do
		local step = Leveling.xpForNext(l)
		if step == math.huge then
			break
		end
		total += step
	end
	return total
end

function Leveling.new(): Progress
	return { level = 1, xp = 0 }
end

-- Award XP, carrying over as many level-ups as the amount allows.
-- Returns the new progress plus how many levels were gained.
function Leveling.addXp(progress: Progress, amount: number): (Progress, number)
	local cfg = Config.Leveling
	assert(amount >= 0, "xp amount must be non-negative")

	local level = math.clamp(math.floor(progress.level), 1, cfg.MaxLevel)
	local xp = math.max(0, progress.xp + amount)
	local gained = 0

	while level < cfg.MaxLevel do
		local needed = Leveling.xpForNext(level)
		if xp < needed then
			break
		end
		xp -= needed
		level += 1
		gained += 1
	end

	-- At the cap XP is meaningless; pin it to zero so the bar reads full.
	if level >= cfg.MaxLevel then
		xp = 0
	end

	return { level = level, xp = xp }, gained
end

-- XP dropped by an enemy killed at `wave`.
function Leveling.xpFromKill(wave: number): number
	local cfg = Config.Leveling
	local w = math.max(1, math.floor(wave))
	return math.floor(cfg.BaseXpPerKill * (cfg.XpGrowthPerWave ^ (w - 1)) + 0.5)
end

-- Permanent coin bonus from levels, as a multiplier (1.0 = no bonus).
function Leveling.coinMultiplier(level: number): number
	local cfg = Config.Leveling
	local l = math.clamp(math.floor(level), 1, cfg.MaxLevel)
	return 1 + cfg.CoinBonusPerLevel * (l - 1)
end

function Leveling.progressRatio(progress: Progress): number
	local needed = Leveling.xpForNext(progress.level)
	if needed == math.huge or needed <= 0 then
		return 1
	end
	return math.clamp(progress.xp / needed, 0, 1)
end

return Leveling

--!strict
-- The six primary attributes and the combat numbers they derive.
--
-- This is the classic Korean-MMO stat sheet: STR/AGI/VIT/INT/DEX/LUK. Each
-- point costs more than the last, so a build is a real choice rather than a
-- bar you fill. Pure Luau: no Roblox globals, so the whole sheet is testable
-- outside Studio.
--
-- The derived formulas are simplified on purpose. A faithful copy of the
-- original would need a spreadsheet to predict; these keep the *shape* (STR
-- for melee power, INT for magic, AGI for speed and dodging, VIT for health,
-- DEX for accuracy, LUK for crits) while staying readable.

local Config = require("./Config")

local Attributes = {}

-- Display order. Kept as a list so the UI and the tests iterate the same way.
Attributes.NAMES = { "STR", "AGI", "VIT", "INT", "DEX", "LUK" }

export type Stats = { [string]: number }

export type Derived = {
        maxHealth: number,
        maxSp: number,
        attack: number,
        magicAttack: number,
        defense: number,
        magicDefense: number,
        hit: number,
        flee: number,
        critChance: number,
        -- Seconds between auto attacks. AGI and DEX shorten it.
        attackInterval: number,
}

local MAX = Config.Attributes.MaxValue
local BASE = Config.Attributes.BaseValue

function Attributes.new(): Stats
        local out: Stats = {}
        for _, name in ipairs(Attributes.NAMES) do
                out[name] = BASE
        end
        return out
end

-- A clean copy, so a caller can never mutate shared state through a return.
function Attributes.copy(stats: Stats): Stats
        local out: Stats = {}
        for _, name in ipairs(Attributes.NAMES) do
                out[name] = math.clamp(math.floor(stats[name] or BASE), BASE, MAX)
        end
        return out
end

-- Points to raise a stat from `value` to `value + 1`. Rises every ten points,
-- so the tenth point in a stat costs more than the first.
function Attributes.pointCost(value: number): number
        local v = math.max(BASE, math.floor(value))
        if v >= MAX then
                return math.huge
        end
        return math.floor((v - 1) / 10) + 2
end

-- Total points to go from BASE to `value`. Used for the "respec" readout and
-- for tests that check the curve is monotonic.
function Attributes.totalCost(value: number): number
        local total = 0
        for v = BASE, math.max(BASE, math.floor(value)) - 1 do
                total += Attributes.pointCost(v)
        end
        return total
end

-- Stat points earned by the time a character reaches `level`. The grant grows
-- with the level, which is what keeps a late-game build from feeling capped.
function Attributes.pointsForLevel(level: number): number
        local l = math.max(1, math.floor(level))
        local cfg = Config.Attributes
        local total = 0
        for i = 1, l - 1 do
                total += cfg.PointsPerLevelBase + math.floor(i / cfg.PointsPerLevelStep)
        end
        return total
end

-- Stat points already spent, so the UI can show what is left to assign.
function Attributes.spent(stats: Stats): number
        local total = 0
        for _, name in ipairs(Attributes.NAMES) do
                total += Attributes.totalCost(stats[name] or BASE)
        end
        return total
end

function Attributes.available(stats: Stats, level: number): number
        return math.max(0, Attributes.pointsForLevel(level) - Attributes.spent(stats))
end

-- Spend points on one stat. Returns (ok, newStats, newPointsLeft, reason).
-- `pointsLeft` is passed in rather than derived so the caller stays in charge
-- of where the number came from (a save, a level-up grant, a test).
function Attributes.raise(
        stats: Stats,
        pointsLeft: number,
        stat: string,
        times: number?
): (boolean, Stats, number, string?)
        if not Config.Attributes.Raisable[stat] then
                return false, stats, pointsLeft, "UNKNOWN_STAT"
        end

        local count = math.max(1, math.floor(times or 1))
        local next = Attributes.copy(stats)
        local left = math.max(0, math.floor(pointsLeft))

        for _ = 1, count do
                local cost = Attributes.pointCost(next[stat])
                if cost == math.huge then
                        return false, stats, pointsLeft, "MAX_STAT"
                end
                if left < cost then
                        return false, stats, pointsLeft, "NOT_ENOUGH_POINTS"
                end
                next[stat] += 1
                left -= cost
        end

        return true, next, left, nil
end

-- Add a bonus table onto a stat sheet, clamped. Class bonuses and equipment
-- both arrive this way, so they stack through one code path.
function Attributes.applyBonus(stats: Stats, bonus: Stats?): Stats
        local out = Attributes.copy(stats)
        if not bonus then
                return out
        end
        for _, name in ipairs(Attributes.NAMES) do
                local add = bonus[name]
                if type(add) == "number" then
                        out[name] = math.clamp(out[name] + math.floor(add), BASE, MAX)
                end
        end
        return out
end

-- The stat sheet as the game uses it: allocated points plus class and
-- equipment bonuses.
function Attributes.effective(stats: Stats, bonus: Stats?): Stats
        return Attributes.applyBonus(stats, bonus)
end

-- Turn a stat sheet into the numbers combat actually reads.
--
-- `level` is the base level: it feeds hit and flee directly, so a high-level
-- character with low DEX still lands hits on same-level monsters.
function Attributes.derive(stats: Stats, level: number): Derived
        local cfg = Config.Attributes
        local s = Attributes.copy(stats)
        local l = math.max(1, math.floor(level))

        local str, agi = s.STR, s.AGI
        local vit, int, dex, luk = s.VIT, s.INT, s.DEX, s.LUK

        -- Squares reward specialising: 100 STR is far more than ten times 10.
        local strBonus = math.floor(str / 10) ^ 2
        local intBonus = math.floor(int / 10) ^ 2

        local attack = cfg.BaseAttack + str * cfg.AttackPerStr + strBonus + math.floor(dex * cfg.AttackPerDex)
        local magicAttack = cfg.BaseMagicAttack + int * cfg.MagicAttackPerInt + intBonus

        -- Health and SP scale with level as well as the stat, so a level-up is
        -- felt even when the player banks their points.
        local maxHealth = cfg.BaseHealth + vit * cfg.HealthPerVit + (l - 1) * cfg.HealthPerLevel
        local maxSp = cfg.BaseSp + int * cfg.SpPerInt + (l - 1) * cfg.SpPerLevel

        local defense = cfg.BaseDefense + math.floor(vit * cfg.DefensePerVit)
        local magicDefense = cfg.BaseMagicDefense + math.floor(int * cfg.MagicDefensePerInt)

        local hit = cfg.BaseHit + l + dex * cfg.HitPerDex
        local flee = cfg.BaseFlee + l + agi * cfg.FleePerAgi
        local critChance = math.min(cfg.MaxCrit, cfg.BaseCrit + luk * cfg.CritPerLuk)

        -- Attack speed: each point of AGI and DEX shaves a little off the
        -- interval, floored so a stacked build cannot attack every frame.
        local speedup = agi * cfg.AgilityPerAgi + dex * cfg.AgilityPerDex
        local attackInterval = math.max(cfg.MinAttackInterval, cfg.BaseAttackInterval - speedup)

        return {
                maxHealth = math.max(1, math.floor(maxHealth + 0.5)),
                maxSp = math.max(1, math.floor(maxSp + 0.5)),
                attack = math.max(1, math.floor(attack + 0.5)),
                magicAttack = math.max(1, math.floor(magicAttack + 0.5)),
                defense = math.max(0, math.floor(defense + 0.5)),
                magicDefense = math.max(0, math.floor(magicDefense + 0.5)),
                hit = math.max(1, math.floor(hit + 0.5)),
                flee = math.max(1, math.floor(flee + 0.5)),
                critChance = critChance,
                attackInterval = attackInterval,
        }
end

-- Chance to land a hit, given attacker accuracy and defender evasion.
-- Returns a probability in 0..1 with a floor, so no build is ever hopeless.
function Attributes.hitChance(hit: number, flee: number): number
        local cfg = Config.Attributes
        local chance = cfg.HitBaseChance + (hit - flee) * cfg.HitChancePerPoint
        return math.clamp(chance, cfg.MinHitChance, cfg.MaxHitChance)
end

-- Damage reduction from defense. Diminishing, so armour never makes a player
-- invulnerable to a monster ten levels above them.
function Attributes.mitigate(damage: number, defense: number): number
        local cfg = Config.Attributes
        local reduced = damage * (1 - defense / (defense + cfg.DefenseSoftCap))
        return math.max(1, math.floor(reduced + 0.5))
end

return Attributes

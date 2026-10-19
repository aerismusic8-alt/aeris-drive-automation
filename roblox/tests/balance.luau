--!strict
-- Can a player kill what their level unlocks?
--
-- This suite exists because of a complaint: "the boss will not die". It turned
-- out to be arithmetic, not difficulty. Attack came only from the STR stat, and
-- maxing STR costs 60 of the 99 points a level 99 character has, so attack went
-- from 110 at level 1 to 146 at level 50 while monster health grew 1.18^wave
-- without limit. A wave 5 boss in the first field needed 15 hits and killed the
-- player in 12 seconds. A wave 25 boss needed 406 hits and killed in 3.
--
-- Every unit test passed the whole time, because no test asked whether the two
-- curves were in the same universe. So this one does. It compares time-to-kill
-- against time-to-die for the level that unlocks each field, and it fails when
-- the player cannot win a boss they are meant to fight.
--
-- Pure Luau, no Roblox globals.

local t = require("./TestRunner")

local Config = require("../src/shared/Config")
local Attributes = require("../src/shared/Attributes")
local Classes = require("../src/shared/Classes")
local Items = require("../src/shared/Items")
local Zones = require("../src/shared/Zones")
local Enemies = require("../src/shared/Enemies")
local Fields = require("../src/shared/Fields")
local WaveDirector = require("../src/shared/WaveDirector")
local Stats = require("../src/shared/Stats")

-- The attack a player has at `level` with no equipment, pets or rebirth. This is
-- the floor: anything the player finds makes it easier, so a fight that is
-- winnable here is winnable in practice.
local function bareAttack(level: number): number
        local attrs = Attributes.new()
        local sheet = Attributes.derive(attrs, level)
        local upgrades = Stats.derive(Stats.newUpgrades())
        return sheet.attack + upgrades.damage
end

local function bareHealth(level: number): number
        local sheet = Attributes.derive(Attributes.new(), level)
        return sheet.maxHealth
end

local function attackInterval(level: number): number
        local sheet = Attributes.derive(Attributes.new(), level)
        return sheet.attackInterval
end

-- The stat points a player has by `level`, all spent on STR, which is the most
-- damage a bare character can have. If even that cannot win, nothing can.
local function bestCaseAttack(level: number): number
        local attrs = Attributes.new()
        attrs.STR = Config.Attributes.MaxValue
        local sheet = Attributes.derive(attrs, level)
        return sheet.attack + Stats.derive(Stats.newUpgrades()).damage
end

-- Time to kill one target, in seconds, ignoring crits (which only help).
local function timeToKill(hp: number, attack: number, interval: number): number
        return math.ceil(hp / math.max(1, attack)) * interval
end

-- Time to die to `damage` per hit, in seconds. The enemy attacks on its own
-- interval; the player is assumed to stand still, which is the worst case.
local function timeToDie(hp: number, damage: number): number
        return math.ceil(hp / math.max(1, damage)) * Config.Wave.EnemyAttackInterval
end

local function enemyFor(fieldId: string, wave: number, boss: boolean)
        local difficulty = Zones.difficultyMultiplier(fieldId)
        local director = WaveDirector.new(require("../src/shared/Random").new(1))
        local plan = director:planFor(wave)
        local archetype = boss and Enemies.boss(fieldId) or Enemies.roster(fieldId)[1]
        return Enemies.scale(archetype, plan, difficulty)
end

--------------------------------------------------------------------------
t.suite("Combat balance: the two curves have to meet")
--------------------------------------------------------------------------

t.test("attack grows with level, not only with the STR stat", function()
        local low = Attributes.derive(Attributes.new(), 1).attack
        local mid = Attributes.derive(Attributes.new(), 25).attack
        local high = Attributes.derive(Attributes.new(), 80).attack
        t.assertGreater(mid, low, "level 25 does not hit harder than level 1")
        t.assertGreater(high, mid, "level 80 does not hit harder than level 25")
        -- The bug was a 33 percent gain across fifty levels. Anything that small
        -- means the per-level term has been lost again.
        t.assertGreater(high / low, 2.0, "attack barely grows across the whole game")
end)

t.test("a player can kill a wave 1 monster in their own starting field", function()
        local scaled = enemyFor("Meadow", 1, false)
        local ttk = timeToKill(scaled.health, bestCaseAttack(1), attackInterval(1))
        local ttd = timeToDie(bareHealth(1), scaled.damage)
        t.assertLess(ttk, ttd, string.format(
                "wave 1 monster takes %.0fs to kill but kills the player in %.0fs", ttk, ttd))
end)

t.test("every field boss is killable at the level that unlocks the field", function()
        for _, zone in ipairs(Zones.list()) do
                local level = zone.levelRequirement
                local scaled = enemyFor(zone.id, Config.Enemies.BossEveryWaves, true)
                local ttk = timeToKill(scaled.health, bestCaseAttack(level), attackInterval(level))
                local ttd = timeToDie(bareHealth(level), scaled.damage)
                t.assertLess(ttk, ttd, string.format(
                        "%s boss at unlock level %d: %.0fs to kill, dies in %.0fs",
                        zone.id, level, ttk, ttd))
        end
end)

t.test("no field's own monsters outrun the player who unlocked it", function()
        for _, zone in ipairs(Zones.list()) do
                local level = zone.levelRequirement
                local scaled = enemyFor(zone.id, 1, false)
                local ttk = timeToKill(scaled.health, bestCaseAttack(level), attackInterval(level))
                t.assertLess(ttk, 10, string.format(
                        "%s wave 1 takes %.0fs to clear at unlock level %d", zone.id, ttk, level))
        end
end)

t.test("a boss is a spike, not a wall, next to the wave it appears in", function()
        for _, zone in ipairs(Zones.list()) do
                local level = zone.levelRequirement
                local wave = Config.Enemies.BossEveryWaves
                local normal = enemyFor(zone.id, wave, false)
                local boss = enemyFor(zone.id, wave, true)
                local attack = bestCaseAttack(level)
                local interval = attackInterval(level)
                local normalTtk = timeToKill(normal.health, attack, interval)
                local bossTtk = timeToKill(boss.health, attack, interval)
                -- A boss should take longer than a normal monster, but not so much
                -- longer that the fight stops being a fight.
                t.assertGreater(bossTtk, normalTtk, zone.id .. " boss is not tougher than its trash")
                t.assertLess(bossTtk, normalTtk * 20, string.format(
                        "%s boss takes %.0fs vs %.0fs for trash: the spike is a wall",
                        zone.id, bossTtk, normalTtk))
        end
end)

t.test("the first field cannot kill, so a new player can always recover", function()
        t.assertFalse(Zones.isLethal("Meadow"), "the tutorial field became lethal")
        for _, id in ipairs({ "Cavern", "Volcano", "Void", "Heaven" }) do
                t.assertTrue(Zones.isLethal(id), id .. " is no longer lethal")
        end
end)

t.test("the axe swing beats a single auto attack once charged", function()
        -- This was backwards: the swing read a damage source that ignored
        -- attributes and equipment, so five charges hit softer than one normal
        -- hit and farming cost the player damage.
        local Axe = require("../src/shared/Axe")
        local level = 50
        local attack = bestCaseAttack(level)
        local state = Axe.new()
        for _ = 1, Config.Farm.AxeMaxCharges do
                Axe.addCharges(state, Config.Farm.AxeChargePerHarvest)
        end
        local _, swing = Axe.swing(state, attack)
        t.assertGreater(swing, attack, "a full axe swing is not stronger than one auto attack")
end)

return t.finish()

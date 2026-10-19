--!strict
-- Monster archetypes and their per-field rosters. Pure Luau.
--
-- Each field has its own monsters so the five maps feel like different places
-- rather than the same red cube with a bigger number. An archetype is a
-- multiplier on the wave's base plan, which keeps the wave scaling in one
-- place (WaveDirector) and the monster variety in another (here).
--
-- Names and colours are original to this game; nothing is copied from any
-- existing title.

local Config = require("./Config")

local Enemies = {}

export type Archetype = {
        id: string,
        name: string,
        -- Multiplies the wave base for this monster.
        healthMul: number,
        damageMul: number,
        rewardMul: number,
        speedMul: number,
        sizeMul: number,
        color: { number },
        boss: boolean,
}

local function def(
        id: string,
        name: string,
        color: { number },
        healthMul: number,
        damageMul: number,
        rewardMul: number,
        speedMul: number,
        sizeMul: number,
        boss: boolean?
): Archetype
        return {
                id = id,
                name = name,
                color = color,
                healthMul = healthMul,
                damageMul = damageMul,
                rewardMul = rewardMul,
                speedMul = speedMul,
                sizeMul = sizeMul,
                boss = boss == true,
        }
end

local DEFS: { [string]: Archetype } = {}

local function add(a: Archetype)
        DEFS[a.id] = a
end

-- Meadow: the tutorial field. Squishy, slow, forgiving. The early levels are
-- deliberately gentle: a level 1 character with no gear should win its first
-- waves while still learning the buttons.
add(def("Poring", "Poring", { 255, 170, 200 }, 0.45, 0.5, 0.9, 0.7, 0.8))
add(def("Slime", "Slime", { 120, 220, 130 }, 0.6, 0.7, 1.0, 0.8, 0.9))
add(def("Hornet", "Hornet", { 240, 220, 110 }, 0.5, 0.7, 0.9, 1.2, 0.7))
add(def("BabyBoar", "Baby Boar", { 220, 170, 140 }, 0.8, 0.8, 1.1, 0.95, 1.0))
add(def("Lunatic", "Lunatic", { 240, 240, 240 }, 0.7, 0.6, 1.0, 1.35, 0.75))
add(def("SlimeKing", "Slime King", { 90, 200, 120 }, 1.0, 1.0, 1.0, 0.8, 1.0, true))

-- Cavern: armoured, hits harder, moves slower.
add(def("CaveBat", "Cave Bat", { 150, 130, 200 }, 0.6, 0.9, 1.0, 1.3, 0.75))
add(def("Skeleton", "Skeleton", { 220, 215, 200 }, 0.9, 1.0, 1.1, 0.95, 1.0))
add(def("RockGolem", "Rock Golem", { 140, 140, 150 }, 1.6, 1.3, 1.4, 0.7, 1.3))
add(def("Familiar", "Familiar", { 160, 110, 190 }, 0.7, 1.1, 1.2, 1.15, 0.85))
add(def("CrystalGolem", "Crystal Golem", { 170, 210, 255 }, 1.0, 1.0, 1.0, 0.7, 1.2, true))

-- Desert: fast, fragile, punishing in packs.
add(def("Scorpion", "Scorpion", { 210, 170, 90 }, 0.8, 1.1, 1.1, 1.1, 0.9))
add(def("Mummy", "Mummy", { 220, 210, 180 }, 1.2, 1.0, 1.2, 0.8, 1.1))
add(def("Anubis", "Anubis", { 200, 180, 120 }, 1.3, 1.3, 1.4, 1.0, 1.1))
add(def("SandWraith", "Sand Wraith", { 230, 200, 140 }, 1.0, 1.0, 1.0, 1.0, 1.3, true))

-- Volcano: heavy hitters, the first field that punishes standing still.
add(def("EmberImp", "Ember Imp", { 250, 130, 70 }, 0.7, 1.3, 1.2, 1.15, 0.85))
add(def("MagmaHound", "Magma Hound", { 230, 90, 60 }, 1.1, 1.4, 1.3, 1.2, 1.0))
add(def("FireElemental", "Fire Elemental", { 255, 160, 60 }, 1.2, 1.5, 1.4, 1.0, 1.05))
add(def("LavaToad", "Lava Toad", { 200, 80, 50 }, 1.5, 1.2, 1.3, 0.75, 1.2))
add(def("VolcanoDragon", "Volcano Dragon", { 255, 110, 60 }, 1.0, 1.0, 1.0, 0.9, 1.4, true))

-- Void: endgame. Everything is dangerous, everything pays.
add(def("VoidWisp", "Void Wisp", { 170, 120, 255 }, 0.9, 1.4, 1.5, 1.2, 0.9))
add(def("RiftStalker", "Rift Stalker", { 130, 90, 220 }, 1.4, 1.6, 1.6, 1.05, 1.15))
add(def("AbyssHound", "Abyss Hound", { 100, 70, 190 }, 1.2, 1.7, 1.6, 1.25, 1.05))
add(def("VoidPriest", "Void Priest", { 140, 110, 230 }, 1.1, 1.8, 1.7, 0.95, 1.1))
add(def("VoidSovereign", "Void Sovereign", { 150, 100, 255 }, 1.0, 1.0, 1.0, 1.0, 1.5, true))

-- Heaven: the last gate. Everything here is a wall.
add(def("CelestialGuard", "Celestial Guard", { 240, 240, 255 }, 1.6, 1.6, 1.7, 1.0, 1.2))
add(def("Seraph", "Seraph", { 255, 250, 210 }, 1.4, 1.9, 1.8, 1.2, 1.15))
add(def("DivineKnight", "Divine Knight", { 220, 230, 255 }, 2.0, 1.8, 1.9, 0.95, 1.25))
add(def("HeavenGate", "Heaven's Gate", { 255, 245, 220 }, 1.0, 1.0, 1.0, 0.85, 1.6, true))

-- Field id -> the monsters that live there. The order is the spawn order, so
-- the first entry is the field's signature monster.
local ROSTERS: { [string]: { string } } = {
        Meadow = { "Poring", "Slime", "Hornet", "BabyBoar", "Lunatic" },
        Cavern = { "CaveBat", "Skeleton", "RockGolem", "Familiar" },
        Volcano = { "EmberImp", "MagmaHound", "FireElemental", "LavaToad" },
        Void = { "VoidWisp", "RiftStalker", "AbyssHound", "VoidPriest" },
        Heaven = { "CelestialGuard", "Seraph", "DivineKnight" },
}

local BOSSES: { [string]: string } = {
        Meadow = "SlimeKing",
        Cavern = "CrystalGolem",
        Volcano = "VolcanoDragon",
        Void = "VoidSovereign",
        Heaven = "HeavenGate",
}

function Enemies.getDef(id: string): Archetype?
        return DEFS[id]
end

function Enemies.roster(fieldId: string): { Archetype }
        local ids = ROSTERS[fieldId] or ROSTERS[Config.Zones.Default]
        local out: { Archetype } = {}
        for _, id in ipairs(ids) do
                table.insert(out, DEFS[id])
        end
        return out
end

function Enemies.boss(fieldId: string): Archetype
        local id = BOSSES[fieldId] or BOSSES[Config.Zones.Default]
        return DEFS[id]
end

-- Every Nth wave in a field is a boss wave, capped so a very long session does
-- not turn into a boss every wave.
function Enemies.isBossWave(wave: number): boolean
        local every = math.max(2, math.floor(Config.Enemies.BossEveryWaves))
        return math.max(1, math.floor(wave)) % every == 0
end

-- Pick the monster for one spawn. On a boss wave the first spawn is the boss;
-- everything else is a roster monster chosen by weight, so a wave reads as a
-- mix rather than a single repeated shape.
function Enemies.pick(fieldId: string, wave: number, rng, firstSpawn: boolean): Archetype
        if firstSpawn and Enemies.isBossWave(wave) then
                return Enemies.boss(fieldId)
        end

        local roster = Enemies.roster(fieldId)
        if #roster == 0 then
                return Enemies.boss(fieldId)
        end

        local weights = {}
        for index, archetype in ipairs(roster) do
                -- Weight the signature monster highest so the field keeps its
                -- identity instead of becoming a uniform mix.
                table.insert(weights, { archetype = archetype, weight = 1 / index })
        end
        local picked = rng:pickWeighted(weights)
        return picked and picked.archetype or roster[1]
end

-- Apply an archetype to a wave plan. Returns the concrete stats for one enemy.
-- Kept pure and separate from the spawn so the maths is unit testable.
export type Scaled = {
        health: number,
        damage: number,
        reward: number,
        speed: number,
        sizeMul: number,
        name: string,
        color: { number },
        boss: boolean,
}

function Enemies.scale(archetype: Archetype, plan: any, difficulty: number?): Scaled
        local mul = difficulty or 1
        local health = plan.enemyHealth * archetype.healthMul * mul
        local damage = plan.enemyDamage * archetype.damageMul * mul
        local reward = plan.rewardPerKill * archetype.rewardMul

        if archetype.boss then
                health *= Config.Enemies.BossHealthMul
                damage *= Config.Enemies.BossDamageMul
                reward *= Config.Enemies.BossRewardMul
        end

        return {
                id = archetype.id,
                health = math.max(1, math.floor(health + 0.5)),
                damage = math.max(1, math.floor(damage + 0.5)),
                reward = math.max(1, math.floor(reward + 0.5)),
                speed = Config.Wave.EnemyMoveSpeed * archetype.speedMul,
                sizeMul = archetype.sizeMul * (archetype.boss and Config.Enemies.BossSizeMul or 1),
                name = archetype.name,
                color = archetype.color,
                boss = archetype.boss,
        }
end

return Enemies

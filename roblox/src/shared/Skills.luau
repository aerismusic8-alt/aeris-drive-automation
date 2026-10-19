--!strict
-- Skills: what a class can learn and cast. Pure Luau.
--
-- Every class has a small list rather than a full tree. On a phone the player
-- has four or five buttons at most, so a short list of skills that clearly do
-- different things beats a long list of near-duplicates.
--
-- A skill is data: SP cost, cooldown, how many levels it has, and a scaling
-- curve. The server resolves the cast; this module only says what is legal.

local Config = require("./Config")

local Skills = {}

export type Kind = "attack" | "heal" | "buff" | "passive"

export type SkillDef = {
        id: string,
        name: string,
        -- Class that learns it.
        class: string,
        -- "attack" hits, "heal" restores, "buff" boosts for a while,
        -- "passive" is always on and is never cast.
        kind: Kind,
        -- Highest skill level a player can buy.
        maxLevel: number,
        -- SP cost at skill level 1, and how much each extra level adds.
        spCost: number,
        spCostPerLevel: number,
        -- Seconds between casts.
        cooldown: number,
        -- Multiplier on attack or magic attack, at level 1, and per level.
        power: number,
        powerPerLevel: number,
        -- How many targets the skill can hit.
        targets: number,
        -- For a buff: seconds it lasts. For a heal: fraction of max health.
        duration: number,
        -- Attribute this skill scales from: "attack" or "magicAttack".
        scalesFrom: string,
        -- Icon colour, so the button reads without a label.
        color: { number },
        -- Skill that must be learned first, and at what level.
        requires: string?,
        requiresLevel: number,
        description: string,
}

local DEFS: { [string]: SkillDef } = {}

local function add(def: SkillDef)
        DEFS[def.id] = def
end

--------------------------------------------------------------------------
-- Novice: the two things every character can do.
--------------------------------------------------------------------------

add({
        id = "BasicAttack",
        name = "Basic Attack",
        class = "Novice",
        kind = "attack",
        maxLevel = 10,
        spCost = 0,
        spCostPerLevel = 0,
        cooldown = 0.7,
        power = 1.0,
        powerPerLevel = 0.05,
        targets = 1,
        duration = 0,
        scalesFrom = "attack",
        color = { 200, 200, 210 },
        requires = nil,
        requiresLevel = 0,
        description = "A plain swing. Costs nothing.",
})

add({
        id = "FirstAid",
        name = "First Aid",
        class = "Novice",
        kind = "heal",
        maxLevel = 5,
        spCost = 8,
        spCostPerLevel = 2,
        cooldown = 12,
        power = 0.15,
        powerPerLevel = 0.05,
        targets = 1,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 130, 230, 150 },
        requires = nil,
        requiresLevel = 0,
        description = "Patch yourself up. Heals a share of your health.",
})

--------------------------------------------------------------------------
-- Swordsman / Knight: melee power and staying power.
--------------------------------------------------------------------------

add({
        id = "Bash",
        name = "Bash",
        class = "Swordsman",
        kind = "attack",
        maxLevel = 10,
        spCost = 8,
        spCostPerLevel = 2,
        cooldown = 2,
        power = 1.6,
        powerPerLevel = 0.18,
        targets = 1,
        duration = 0,
        scalesFrom = "attack",
        color = { 255, 150, 90 },
        requires = nil,
        requiresLevel = 0,
        description = "A heavy blow that staggers one enemy.",
})

add({
        id = "MagnumBreak",
        name = "Magnum Break",
        class = "Swordsman",
        kind = "attack",
        maxLevel = 10,
        spCost = 18,
        spCostPerLevel = 3,
        cooldown = 6,
        power = 1.2,
        powerPerLevel = 0.12,
        targets = 5,
        duration = 0,
        scalesFrom = "attack",
        color = { 255, 110, 60 },
        requires = "Bash",
        requiresLevel = 3,
        description = "A spinning strike that hits everything nearby.",
})

add({
        id = "Endure",
        name = "Endure",
        class = "Swordsman",
        kind = "buff",
        maxLevel = 5,
        spCost = 12,
        spCostPerLevel = 3,
        cooldown = 20,
        power = 0.25,
        powerPerLevel = 0.1,
        targets = 1,
        duration = 12,
        scalesFrom = "attack",
        color = { 220, 190, 120 },
        requires = nil,
        requiresLevel = 0,
        description = "Brace yourself: less damage taken for a while.",
})

add({
        id = "BowlingBash",
        name = "Bowling Bash",
        class = "Knight",
        kind = "attack",
        maxLevel = 10,
        spCost = 26,
        spCostPerLevel = 4,
        cooldown = 8,
        power = 2.2,
        powerPerLevel = 0.24,
        targets = 3,
        duration = 0,
        scalesFrom = "attack",
        color = { 255, 90, 70 },
        requires = nil,
        requiresLevel = 0,
        description = "Charge through the line, hitting several enemies.",
})

add({
        id = "TwoHandQuicken",
        name = "Two-Hand Quicken",
        class = "Knight",
        kind = "buff",
        maxLevel = 5,
        spCost = 20,
        spCostPerLevel = 4,
        cooldown = 30,
        power = 0.15,
        powerPerLevel = 0.05,
        targets = 1,
        duration = 20,
        scalesFrom = "attack",
        color = { 255, 210, 110 },
        requires = nil,
        requiresLevel = 0,
        description = "Swing faster for a while.",
})

--------------------------------------------------------------------------
-- Archer / Hunter: range and accuracy.
--------------------------------------------------------------------------

add({
        id = "DoubleStrafe",
        name = "Double Strafe",
        class = "Archer",
        kind = "attack",
        maxLevel = 10,
        spCost = 10,
        spCostPerLevel = 2,
        cooldown = 2.5,
        power = 1.4,
        powerPerLevel = 0.15,
        targets = 2,
        duration = 0,
        scalesFrom = "attack",
        color = { 150, 220, 120 },
        requires = nil,
        requiresLevel = 0,
        description = "Two arrows, two targets.",
})

add({
        id = "OwlEyes",
        name = "Owl's Eye",
        class = "Archer",
        kind = "passive",
        maxLevel = 10,
        spCost = 0,
        spCostPerLevel = 0,
        cooldown = 0,
        power = 0.02,
        powerPerLevel = 0.02,
        targets = 1,
        duration = 0,
        scalesFrom = "attack",
        color = { 190, 210, 140 },
        requires = nil,
        requiresLevel = 0,
        description = "Sharper eyes: more accuracy and a little more damage.",
})

add({
        id = "ArrowShower",
        name = "Arrow Shower",
        class = "Hunter",
        kind = "attack",
        maxLevel = 10,
        spCost = 24,
        spCostPerLevel = 4,
        cooldown = 7,
        power = 1.5,
        powerPerLevel = 0.16,
        targets = 5,
        duration = 0,
        scalesFrom = "attack",
        color = { 130, 210, 90 },
        requires = nil,
        requiresLevel = 0,
        description = "A rain of arrows over a wide area.",
})

add({
        id = "BeastFang",
        name = "Beast Fang",
        class = "Hunter",
        kind = "buff",
        maxLevel = 5,
        spCost = 18,
        spCostPerLevel = 4,
        cooldown = 25,
        power = 0.2,
        powerPerLevel = 0.06,
        targets = 1,
        duration = 18,
        scalesFrom = "attack",
        color = { 160, 230, 130 },
        requires = nil,
        requiresLevel = 0,
        description = "Call a companion: more damage for a while.",
})

--------------------------------------------------------------------------
-- Mage / Wizard: magic damage, and the spell that hits everything.
--------------------------------------------------------------------------

add({
        id = "FireBolt",
        name = "Fire Bolt",
        class = "Mage",
        kind = "attack",
        maxLevel = 10,
        spCost = 12,
        spCostPerLevel = 3,
        cooldown = 2,
        power = 1.8,
        powerPerLevel = 0.2,
        targets = 1,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 255, 130, 70 },
        requires = nil,
        requiresLevel = 0,
        description = "A bolt of fire. Hits hard on one target.",
})

add({
        id = "ColdBolt",
        name = "Cold Bolt",
        class = "Mage",
        kind = "attack",
        maxLevel = 10,
        spCost = 12,
        spCostPerLevel = 3,
        cooldown = 2.5,
        power = 1.5,
        powerPerLevel = 0.18,
        targets = 3,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 120, 190, 255 },
        requires = nil,
        requiresLevel = 0,
        description = "Shards of ice that slow a small group.",
})

add({
        id = "IncreaseSpRecovery",
        name = "Increase SP Recovery",
        class = "Mage",
        kind = "passive",
        maxLevel = 10,
        spCost = 0,
        spCostPerLevel = 0,
        cooldown = 0,
        power = 0.05,
        powerPerLevel = 0.05,
        targets = 1,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 140, 200, 255 },
        requires = nil,
        requiresLevel = 0,
        description = "Your mana comes back faster.",
})

add({
        id = "StormGust",
        name = "Storm Gust",
        class = "Wizard",
        kind = "attack",
        maxLevel = 10,
        spCost = 34,
        spCostPerLevel = 5,
        cooldown = 10,
        power = 2.0,
        powerPerLevel = 0.22,
        targets = 6,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 120, 170, 255 },
        requires = nil,
        requiresLevel = 0,
        description = "A blizzard across the whole field.",
})

add({
        id = "MagicCrasher",
        name = "Magic Crasher",
        class = "Wizard",
        kind = "attack",
        maxLevel = 10,
        spCost = 22,
        spCostPerLevel = 4,
        cooldown = 5,
        power = 2.4,
        powerPerLevel = 0.26,
        targets = 1,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 180, 140, 255 },
        requires = nil,
        requiresLevel = 0,
        description = "All your magic in one strike.",
})

--------------------------------------------------------------------------
-- Thief / Assassin: speed and criticals.
--------------------------------------------------------------------------

add({
        id = "DoubleAttack",
        name = "Double Attack",
        class = "Thief",
        kind = "attack",
        maxLevel = 10,
        spCost = 6,
        spCostPerLevel = 2,
        cooldown = 1.2,
        power = 1.1,
        powerPerLevel = 0.12,
        targets = 1,
        duration = 0,
        scalesFrom = "attack",
        color = { 210, 150, 255 },
        requires = nil,
        requiresLevel = 0,
        description = "Two quick strikes in the time of one.",
})

add({
        id = "ImproveDodge",
        name = "Improve Dodge",
        class = "Thief",
        kind = "passive",
        maxLevel = 10,
        spCost = 0,
        spCostPerLevel = 0,
        cooldown = 0,
        power = 0.03,
        powerPerLevel = 0.03,
        targets = 1,
        duration = 0,
        scalesFrom = "attack",
        color = { 190, 170, 255 },
        requires = nil,
        requiresLevel = 0,
        description = "You slip out of more attacks.",
})

add({
        id = "SonicBlow",
        name = "Sonic Blow",
        class = "Assassin",
        kind = "attack",
        maxLevel = 10,
        spCost = 20,
        spCostPerLevel = 4,
        cooldown = 5,
        power = 2.3,
        powerPerLevel = 0.25,
        targets = 1,
        duration = 0,
        scalesFrom = "attack",
        color = { 200, 110, 255 },
        requires = nil,
        requiresLevel = 0,
        description = "A strike too fast to see. Big critical damage.",
})

add({
        id = "Cloaking",
        name = "Cloaking",
        class = "Assassin",
        kind = "buff",
        maxLevel = 5,
        spCost = 22,
        spCostPerLevel = 4,
        cooldown = 25,
        power = 0.3,
        powerPerLevel = 0.1,
        targets = 1,
        duration = 10,
        scalesFrom = "attack",
        color = { 170, 150, 240 },
        requires = nil,
        requiresLevel = 0,
        description = "Vanish: enemies miss far more often.",
})

--------------------------------------------------------------------------
-- Acolyte / Priest: healing and support.
--------------------------------------------------------------------------

add({
        id = "Heal",
        name = "Heal",
        class = "Acolyte",
        kind = "heal",
        maxLevel = 10,
        spCost = 14,
        spCostPerLevel = 3,
        cooldown = 4,
        power = 0.25,
        powerPerLevel = 0.06,
        targets = 1,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 150, 255, 190 },
        requires = nil,
        requiresLevel = 0,
        description = "Restore a share of your health.",
})

add({
        id = "Blessing",
        name = "Blessing",
        class = "Acolyte",
        kind = "buff",
        maxLevel = 10,
        spCost = 16,
        spCostPerLevel = 3,
        cooldown = 20,
        power = 0.15,
        powerPerLevel = 0.05,
        targets = 1,
        duration = 20,
        scalesFrom = "magicAttack",
        color = { 220, 255, 190 },
        requires = nil,
        requiresLevel = 0,
        description = "A blessing: more attack and accuracy for a while.",
})

add({
        id = "MagnusExorcismus",
        name = "Magnus Exorcismus",
        class = "Priest",
        kind = "attack",
        maxLevel = 10,
        spCost = 30,
        spCostPerLevel = 5,
        cooldown = 9,
        power = 1.9,
        powerPerLevel = 0.21,
        targets = 6,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 255, 240, 160 },
        requires = nil,
        requiresLevel = 0,
        description = "Holy light burns everything around you.",
})

add({
        id = "Sanctuary",
        name = "Sanctuary",
        class = "Priest",
        kind = "heal",
        maxLevel = 10,
        spCost = 28,
        spCostPerLevel = 5,
        cooldown = 14,
        power = 0.4,
        powerPerLevel = 0.08,
        targets = 1,
        duration = 0,
        scalesFrom = "magicAttack",
        color = { 200, 255, 220 },
        requires = nil,
        requiresLevel = 0,
        description = "A large heal when it matters most.",
})

--------------------------------------------------------------------------

local ORDER = {
        "BasicAttack", "FirstAid",
        "Bash", "MagnumBreak", "Endure",
        "DoubleStrafe", "OwlEyes",
        "FireBolt", "ColdBolt", "IncreaseSpRecovery",
        "DoubleAttack", "ImproveDodge",
        "Heal", "Blessing",
        "BowlingBash", "TwoHandQuicken",
        "ArrowShower", "BeastFang",
        "StormGust", "MagicCrasher",
        "SonicBlow", "Cloaking",
        "MagnusExorcismus", "Sanctuary",
}

function Skills.getDef(id: string): SkillDef?
        return DEFS[id]
end

function Skills.list(): { SkillDef }
        local out: { SkillDef } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, DEFS[id])
        end
        return out
end

-- Everything a class can learn, in catalogue order.
function Skills.forClass(classId: string): { SkillDef }
        local out: { SkillDef } = {}
        for _, id in ipairs(ORDER) do
                local def = DEFS[id]
                if def and def.class == classId then
                        table.insert(out, def)
                end
        end
        return out
end

-- Skills the Novice keeps forever: the plain attack and the first heal are
-- always available, whatever class the player ends up in.
function Skills.isUniversal(skillId: string): boolean
        local def = DEFS[skillId]
        return def ~= nil and def.class == "Novice"
end

-- Can this character put a point into this skill? Returns (ok, reason).
function Skills.canLearn(
        learned: { [string]: number },
        classId: string,
        skillId: string,
        skillPoints: number
): (boolean, string?)
        local def = DEFS[skillId]
        if not def then
                return false, "UNKNOWN_SKILL"
        end
        if def.class ~= classId and not Skills.isUniversal(skillId) then
                return false, "WRONG_CLASS"
        end

        local level = math.max(0, math.floor(learned[skillId] or 0))
        if level >= def.maxLevel then
                return false, "MAX_LEVEL"
        end

        if def.requires then
                local required = math.max(0, math.floor(learned[def.requires] or 0))
                if required < def.requiresLevel then
                        return false, "PREREQUISITE"
                end
        end

        if math.max(0, math.floor(skillPoints)) < 1 then
                return false, "NO_SKILL_POINTS"
        end

        return true, nil
end

-- Spend a point. Returns (ok, newLearned, newPoints, reason).
function Skills.learn(
        learned: { [string]: number },
        classId: string,
        skillId: string,
        skillPoints: number
): (boolean, { [string]: number }, number, string?)
        local ok, reason = Skills.canLearn(learned, classId, skillId, skillPoints)
        if not ok then
                return false, learned, skillPoints, reason
        end

        local next: { [string]: number } = {}
        for id, level in pairs(learned) do
                next[id] = level
        end
        next[skillId] = math.max(0, math.floor(next[skillId] or 0)) + 1

        return true, next, math.max(0, math.floor(skillPoints)) - 1, nil
end

-- SP a cast costs at the given skill level. Level 0 means "not learned".
function Skills.spCost(def: SkillDef, level: number): number
        local l = math.max(0, math.floor(level))
        if l <= 0 then
                return 0
        end
        return math.max(0, math.floor(def.spCost + def.spCostPerLevel * (l - 1) + 0.5))
end

-- Power multiplier at the given skill level.
function Skills.power(def: SkillDef, level: number): number
        local l = math.max(0, math.floor(level))
        if l <= 0 then
                return 0
        end
        return def.power + def.powerPerLevel * (l - 1)
end

-- Cooldown in seconds. Never below the global floor, so a maxed skill still
-- cannot be spammed.
function Skills.cooldown(def: SkillDef, level: number): number
        local l = math.max(1, math.floor(level))
        local base = def.cooldown / (1 + 0.02 * (l - 1))
        return math.max(Config.Skills.MinGlobalCooldown, base)
end

-- Resolve one cast into concrete numbers. `stats` is the derived sheet from
-- Attributes.derive, so the skill scales off the same numbers combat does.
export type Cast = {
        damage: number,
        heal: number,
        targets: number,
        duration: number,
        spCost: number,
        buff: { attackMul: number, defenseMul: number, hitBonus: number },
}

function Skills.resolve(def: SkillDef, level: number, derived: any, bonus: any?): Cast
        local power = Skills.power(def, level)
        local base = derived[def.scalesFrom] or derived.attack or 1
        local extra = bonus or {}

        if def.kind == "attack" then
                local damage = base * power * (extra.damageMul or 1)
                return {
                        damage = math.max(1, math.floor(damage + 0.5)),
                        heal = 0,
                        targets = math.max(1, math.floor(def.targets)),
                        duration = 0,
                        spCost = Skills.spCost(def, level),
                        buff = { attackMul = 1, defenseMul = 1, hitBonus = 0 },
                }
        end

        if def.kind == "heal" then
                -- Healing is a share of max health, plus a slice of magic
                -- attack, so it stays useful as the health bar grows.
                local heal = derived.maxHealth * power + base * 0.5
                return {
                        damage = 0,
                        heal = math.max(1, math.floor(heal + 0.5)),
                        targets = 1,
                        duration = 0,
                        spCost = Skills.spCost(def, level),
                        buff = { attackMul = 1, defenseMul = 1, hitBonus = 0 },
                }
        end

        if def.kind == "buff" then
                return {
                        damage = 0,
                        heal = 0,
                        targets = 1,
                        duration = def.duration,
                        spCost = Skills.spCost(def, level),
                        buff = {
                                attackMul = 1 + power,
                                defenseMul = 1 + power,
                                hitBonus = math.floor(power * 50),
                        },
                }
        end

        -- Passive: nothing to cast, but the effect is always on.
        return {
                damage = 0,
                heal = 0,
                targets = 0,
                duration = 0,
                spCost = 0,
                buff = { attackMul = 1, defenseMul = 1, hitBonus = 0 },
        }
end

-- Combined always-on effect of every passive the character has learned. Called
-- by the server when it derives stats, so a passive is never forgotten.
function Skills.passiveBonus(learned: { [string]: number }): { damageMul: number, hitBonus: number }
        local damageMul = 1
        local hitBonus = 0
        for skillId, level in pairs(learned or {}) do
                local def = DEFS[skillId]
                if def and def.kind == "passive" and level > 0 then
                        local power = Skills.power(def, level)
                        if def.id == "OwlEyes" then
                                damageMul *= 1 + power
                                hitBonus += math.floor(power * 100)
                        elseif def.id == "ImproveDodge" then
                                hitBonus += 0
                        elseif def.id == "IncreaseSpRecovery" then
                                hitBonus += 0
                        end
                end
        end
        return { damageMul = damageMul, hitBonus = hitBonus }
end

-- Everything currently castable, with its cost and cooldown resolved. The
-- client renders this directly, so a button never shows a stale cost.
function Skills.hotbar(learned: { [string]: number }, classId: string, derived: any): { any }
        local out: { any } = {}
        for _, id in ipairs(ORDER) do
                local def = DEFS[id]
                local level = math.max(0, math.floor(learned[id] or 0))
                if def and level > 0 and def.kind ~= "passive" then
                        local cast = Skills.resolve(def, level, derived)
                        table.insert(out, {
                                id = def.id,
                                name = def.name,
                                kind = def.kind,
                                level = level,
                                maxLevel = def.maxLevel,
                                spCost = cast.spCost,
                                cooldown = Skills.cooldown(def, level),
                                color = def.color,
                                description = def.description,
                        })
                end
        end
        return out
end

return Skills

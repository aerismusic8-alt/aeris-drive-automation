--!strict
-- Classes and job advancement. Pure Luau.
--
-- The tree is the classic one: a Novice branches into five first jobs, and
-- each first job has exactly one second job to advance into. Advancing is
-- gated on base level *and* job level, so a player has to actually play the
-- class before they can leave it.
--
-- A class carries two things: flat attribute bonuses (so a Swordsman is
-- physically tougher before any points are spent) and a skill list.

local Config = require("./Config")

local Classes = {}

export type ClassDef = {
        id: string,
        name: string,
        -- 0 = Novice, 1 = first job, 2 = second job.
        tier: number,
        -- Flat additions to the stat sheet.
        bonus: { [string]: number },
        -- Class this advances from, or nil for the starting class.
        parent: string?,
        -- Classes this can advance into.
        advancesTo: { string },
        -- Flavour line for the job panel.
        tagline: string,
        -- Which attribute the class leans on, used to hint a build.
        primary: string,
}

local DEFS: { [string]: ClassDef } = {}

local function add(def: ClassDef)
        DEFS[def.id] = def
end

add({
        id = "Novice",
        name = "Novice",
        tier = 0,
        bonus = {},
        parent = nil,
        advancesTo = { "Swordsman", "Archer", "Mage", "Thief", "Acolyte" },
        tagline = "Everyone starts here.",
        primary = "STR",
})

-- First jobs.
add({
        id = "Swordsman",
        name = "Swordsman",
        tier = 1,
        bonus = { STR = 4, VIT = 4, DEX = 1 },
        parent = "Novice",
        advancesTo = { "Knight" },
        tagline = "Heavy armour, heavier swings.",
        primary = "STR",
})
add({
        id = "Archer",
        name = "Archer",
        tier = 1,
        bonus = { DEX = 5, AGI = 3, STR = 1 },
        parent = "Novice",
        advancesTo = { "Hunter" },
        tagline = "Kill it before it reaches you.",
        primary = "DEX",
})
add({
        id = "Mage",
        name = "Mage",
        tier = 1,
        bonus = { INT = 5, DEX = 2, VIT = 1 },
        parent = "Novice",
        advancesTo = { "Wizard" },
        tagline = "The elements do the walking.",
        primary = "INT",
})
add({
        id = "Thief",
        name = "Thief",
        tier = 1,
        bonus = { AGI = 4, LUK = 3, STR = 2 },
        parent = "Novice",
        advancesTo = { "Assassin" },
        tagline = "Fast, quiet, and already behind you.",
        primary = "AGI",
})
add({
        id = "Acolyte",
        name = "Acolyte",
        tier = 1,
        bonus = { INT = 4, VIT = 3, DEX = 2 },
        parent = "Novice",
        advancesTo = { "Priest" },
        tagline = "Keeps the party standing.",
        primary = "INT",
})

-- Second jobs.
add({
        id = "Knight",
        name = "Knight",
        tier = 2,
        bonus = { STR = 8, VIT = 8, DEX = 2 },
        parent = "Swordsman",
        advancesTo = {},
        tagline = "The line holds because you are in it.",
        primary = "STR",
})
add({
        id = "Hunter",
        name = "Hunter",
        tier = 2,
        bonus = { DEX = 10, AGI = 6, STR = 2 },
        parent = "Archer",
        advancesTo = {},
        tagline = "Nothing outruns an arrow.",
        primary = "DEX",
})
add({
        id = "Wizard",
        name = "Wizard",
        tier = 2,
        bonus = { INT = 10, DEX = 4, VIT = 2 },
        parent = "Mage",
        advancesTo = {},
        tagline = "Reality is a suggestion.",
        primary = "INT",
})
add({
        id = "Assassin",
        name = "Assassin",
        tier = 2,
        bonus = { AGI = 8, LUK = 6, STR = 4 },
        parent = "Thief",
        advancesTo = {},
        tagline = "Two blades, one answer.",
        primary = "AGI",
})
add({
        id = "Priest",
        name = "Priest",
        tier = 2,
        bonus = { INT = 8, VIT = 6, DEX = 4 },
        parent = "Acolyte",
        advancesTo = {},
        tagline = "The light arrives before you do.",
        primary = "INT",
})

-- Display order: the tree, top to bottom.
local ORDER = {
        "Novice",
        "Swordsman", "Knight",
        "Archer", "Hunter",
        "Mage", "Wizard",
        "Thief", "Assassin",
        "Acolyte", "Priest",
}

function Classes.getDef(id: string): ClassDef?
        return DEFS[id]
end

function Classes.list(): { ClassDef }
        local out: { ClassDef } = {}
        for _, id in ipairs(ORDER) do
                table.insert(out, DEFS[id])
        end
        return out
end

function Classes.starting(): ClassDef
        local id = Config.Classes.StartingClass
        return DEFS[id] or DEFS.Novice
end

-- Can this character advance into `target`? Returns (ok, reason).
--
-- Both gates are checked: the branch must be reachable from the current class,
-- and both the base level and job level must be met. The reason string is
-- stable so the UI can turn it into a sentence.
function Classes.canAdvance(
        currentClass: string,
        target: string,
        baseLevel: number,
        jobLevel: number
): (boolean, string?)
        local from = DEFS[currentClass]
        local to = DEFS[target]
        if not from or not to then
                return false, "UNKNOWN_CLASS"
        end

        local reachable = false
        for _, id in ipairs(from.advancesTo) do
                if id == target then
                        reachable = true
                        break
                end
        end
        if not reachable then
                return false, "NOT_A_BRANCH"
        end

        local cfg = Config.Classes
        if to.tier == 1 then
                if baseLevel < cfg.FirstJobLevel then
                        return false, "BASE_LEVEL_TOO_LOW"
                end
                if jobLevel < cfg.FirstJobJobLevel then
                        return false, "JOB_LEVEL_TOO_LOW"
                end
        elseif to.tier == 2 then
                if baseLevel < cfg.SecondJobLevel then
                        return false, "BASE_LEVEL_TOO_LOW"
                end
                if jobLevel < cfg.SecondJobJobLevel then
                        return false, "JOB_LEVEL_TOO_LOW"
                end
        else
                return false, "NOT_A_BRANCH"
        end

        return true, nil
end

-- Advance into a class. Job level resets to 1, which is what makes the new
-- skill list start from nothing rather than being handed for free.
function Classes.advance(target: string): { class: string, jobLevel: number, jobXp: number }
        return { class = target, jobLevel = 1, jobXp = 0 }
end

-- XP needed for the next job level at the given job level.
function Classes.jobXpForNext(jobLevel: number): number
        local cfg = Config.Classes
        local l = math.max(1, math.floor(jobLevel))
        if l >= cfg.MaxJobLevel then
                return math.huge
        end
        return math.floor(cfg.JobXpBase * (cfg.JobXpGrowth ^ (l - 1)) + 0.5)
end

-- Award job XP, carrying over as many job levels as the amount allows.
-- Returns the new job level, the leftover XP, and how many levels were gained.
function Classes.addJobXp(jobLevel: number, jobXp: number, amount: number): (number, number, number)
        local cfg = Config.Classes
        local level = math.clamp(math.floor(jobLevel), 1, cfg.MaxJobLevel)
        local xp = math.max(0, jobXp + math.max(0, amount))
        local gained = 0

        while level < cfg.MaxJobLevel do
                local needed = Classes.jobXpForNext(level)
                if xp < needed then
                        break
                end
                xp -= needed
                level += 1
                gained += 1
        end

        if level >= cfg.MaxJobLevel then
                xp = 0
        end

        return level, xp, gained
end

-- Skill points earned by a job level. One per level, so the count is simple
-- to reason about and to show.
function Classes.skillPointsForJobLevel(jobLevel: number): number
        local l = math.max(1, math.floor(jobLevel))
        return (l - 1) * Config.Classes.SkillPointsPerJobLevel
end

-- Flat attribute bonus from the class, so a caller can stack it onto a sheet.
function Classes.bonus(classId: string): { [string]: number }
        local def = DEFS[classId]
        if not def then
                return {}
        end
        local out: { [string]: number } = {}
        for name, value in pairs(def.bonus) do
                out[name] = value
        end
        return out
end

-- Every class reachable from the current one, including through a second job.
-- Used by the job panel to show the whole branch, not just the next step.
function Classes.branch(classId: string): { ClassDef }
        local out: { ClassDef } = {}
        local current = DEFS[classId]
        if not current then
                return out
        end
        table.insert(out, current)
        for _, first in ipairs(current.advancesTo) do
                local def = DEFS[first]
                if def then
                        table.insert(out, def)
                        for _, second in ipairs(def.advancesTo) do
                                local sub = DEFS[second]
                                if sub then
                                        table.insert(out, sub)
                                end
                        end
                end
        end
        return out
end

return Classes

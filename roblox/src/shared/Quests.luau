--!strict
-- The story spine. A new player was dropped into a field with no idea what to
-- do, why the farm exists, or why they are holding an axe. Everything worked and
-- nothing explained itself.
--
-- So this is a single ordered line of objectives, each one teaching the next
-- mechanic and paying for it: kill something, pick a class, plant and harvest to
-- charge the axe, swing it, wear your first gear, kill the field boss, move on.
-- One quest is active at a time and it always names a concrete next action, so
-- "what do I do now" has an answer on screen at all times.
--
-- Pure Luau: no Roblox globals. The server feeds it events and the client draws
-- the snapshot, so the whole spine is testable outside Studio.

local Config = require("./Config")

local Quests = {}

-- Objective kinds. Each maps to one event the server already produces, so the
-- quest layer never polls and never invents state.
--   KILL        - kill N monsters, optionally of one archetype
--   KILL_BOSS   - kill the boss of a named field
--   HARVEST     - harvest N crops
--   ENTER_FIELD - travel to a named field
--   REACH_LEVEL - reach a level
--   CHOOSE_CLASS- pick a first job
--   EQUIP       - put on a piece of equipment in a named slot

export type QuestDef = {
        id: string,
        -- Text key for the title and the objective line.
        titleKey: string,
        bodyKey: string,
        kind: string,
        -- What the objective is about: an archetype id, a field id, a slot.
        target: string?,
        count: number,
        -- Paid on completion.
        coins: number,
        xp: number,
        -- Optional item grant, so the spine also hands over the gear it teaches.
        item: string?,
        itemCount: number,
}

export type State = {
        -- 1-based index of the active quest.
        index: number,
        progress: number,
        done: { [string]: boolean },
}

local QUESTS: { QuestDef } = {
        {
                -- A new player spawns in town, and town has no monsters. The old
                -- opening objective said "kill 3 monsters" while the player stood
                -- in the one place that cannot satisfy it, which is the worst
                -- possible first instruction: the game is asking for something
                -- and the player has no idea where. Send them to the field
                -- first, so the very first line names a place they can reach.
                id = "go_to_meadow",
                titleKey = "qGoToMeadow",
                bodyKey = "qGoToMeadowBody",
                kind = "ENTER_FIELD",
                target = "Meadow",
                count = 1,
                coins = 60,
                xp = 15,
                item = nil,
                itemCount = 0,
        },
        {
                id = "first_blood",
                titleKey = "qFirstBlood",
                bodyKey = "qFirstBloodBody",
                kind = "KILL",
                target = nil,
                count = 3,
                coins = 150,
                xp = 40,
                item = nil,
                itemCount = 0,
        },
        {
                id = "pick_a_job",
                titleKey = "qPickJob",
                bodyKey = "qPickJobBody",
                kind = "CHOOSE_CLASS",
                target = nil,
                count = 1,
                coins = 300,
                xp = 80,
                item = nil,
                itemCount = 0,
        },
        {
                id = "plant_and_pick",
                titleKey = "qPlantAndPick",
                bodyKey = "qPlantAndPickBody",
                kind = "HARVEST",
                target = nil,
                count = 3,
                coins = 250,
                xp = 60,
                item = nil,
                itemCount = 0,
        },
        {
                id = "swing_the_axe",
                titleKey = "qSwingAxe",
                bodyKey = "qSwingAxeBody",
                kind = "KILL",
                target = nil,
                count = 10,
                coins = 400,
                xp = 120,
                item = nil,
                itemCount = 0,
        },
        {
                id = "wear_something",
                titleKey = "qWearGear",
                bodyKey = "qWearGearBody",
                kind = "EQUIP",
                target = nil,
                count = 1,
                coins = 350,
                xp = 90,
                item = "NoviceKnife",
                itemCount = 1,
        },
        {
                id = "slime_king",
                titleKey = "qSlimeKing",
                bodyKey = "qSlimeKingBody",
                kind = "KILL_BOSS",
                target = "Meadow",
                count = 1,
                coins = 900,
                xp = 400,
                item = nil,
                itemCount = 0,
        },
        {
                id = "into_the_cavern",
                titleKey = "qCavern",
                bodyKey = "qCavernBody",
                kind = "ENTER_FIELD",
                target = "Cavern",
                count = 1,
                coins = 800,
                xp = 300,
                item = nil,
                itemCount = 0,
        },
        {
                id = "crystal_golem",
                titleKey = "qCrystalGolem",
                bodyKey = "qCrystalGolemBody",
                kind = "KILL_BOSS",
                target = "Cavern",
                count = 1,
                coins = 2000,
                xp = 900,
                item = nil,
                itemCount = 0,
        },
        {
                id = "into_the_volcano",
                titleKey = "qVolcano",
                bodyKey = "qVolcanoBody",
                kind = "ENTER_FIELD",
                target = "Volcano",
                count = 1,
                coins = 1600,
                xp = 600,
                item = nil,
                itemCount = 0,
        },
        {
                id = "volcano_dragon",
                titleKey = "qVolcanoDragon",
                bodyKey = "qVolcanoDragonBody",
                kind = "KILL_BOSS",
                target = "Volcano",
                count = 1,
                coins = 4500,
                xp = 2000,
                item = nil,
                itemCount = 0,
        },
        {
                id = "into_the_void",
                titleKey = "qVoid",
                bodyKey = "qVoidBody",
                kind = "ENTER_FIELD",
                target = "Void",
                count = 1,
                coins = 3600,
                xp = 1400,
                item = nil,
                itemCount = 0,
        },
        {
                id = "void_sovereign",
                titleKey = "qVoidSovereign",
                bodyKey = "qVoidSovereignBody",
                kind = "KILL_BOSS",
                target = "Void",
                count = 1,
                coins = 10000,
                xp = 4500,
                item = nil,
                itemCount = 0,
        },
        {
                id = "the_last_gate",
                titleKey = "qHeaven",
                bodyKey = "qHeavenBody",
                kind = "ENTER_FIELD",
                target = "Heaven",
                count = 1,
                coins = 8000,
                xp = 3000,
                item = nil,
                itemCount = 0,
        },
        {
                id = "heavens_gate",
                titleKey = "qHeavenGate",
                bodyKey = "qHeavenGateBody",
                kind = "KILL_BOSS",
                target = "Heaven",
                count = 1,
                coins = 25000,
                xp = 12000,
                item = nil,
                itemCount = 0,
        },
}

export type Reward = {
        questId: string,
        coins: number,
        xp: number,
        item: string?,
        itemCount: number,
}

function Quests.list(): { QuestDef }
        return QUESTS
end

function Quests.count(): number
        return #QUESTS
end

function Quests.new(): State
        return { index = 1, progress = 0, done = {} }
end

-- The active quest, or nil when the whole spine is finished. Finishing the line
-- is a real end state, so callers must handle nil rather than wrap around.
function Quests.current(state: State): QuestDef?
        local def = QUESTS[state.index]
        return def
end

-- Does this event advance the active quest? Kept separate from applying it so a
-- caller can ask without mutating, which is what the tests check.
function Quests.matches(def: QuestDef, kind: string, target: string?): boolean
        if def.kind ~= kind then
                return false
        end
        if def.target == nil then
                -- No target means "any", which is how the early quests stay open
                -- to whatever the player happens to be fighting.
                return true
        end
        return def.target == target
end

-- Feed one event to the spine. Returns the reward when a quest completes, so the
-- caller pays it in the one place that already knows how to pay things.
--
-- `count` lets one call satisfy several steps, which matters for HARVEST: a
-- single tap can harvest a plot and the caller should not have to loop.
function Quests.onEvent(state: State, kind: string, target: string?, count: number?): Reward?
        local def = Quests.current(state)
        if def == nil then
                return nil
        end
        if not Quests.matches(def, kind, target) then
                return nil
        end

        state.progress += math.max(1, math.floor(count or 1))
        if state.progress < def.count then
                return nil
        end

        state.done[def.id] = true
        state.index += 1
        state.progress = 0

        return {
                questId = def.id,
                coins = def.coins,
                xp = def.xp,
                item = def.item,
                itemCount = def.itemCount,
        }
end

-- What the HUD draws: the active quest, how far along, and whether the line is
-- finished. `target` is passed through so the client can name the place or the
-- monster without duplicating the table.
function Quests.snapshot(state: State): any
        local def = Quests.current(state)
        if def == nil then
                return {
                        complete = true,
                        total = #QUESTS,
                        index = #QUESTS,
                        done = #QUESTS,
                }
        end

        local completed = 0
        for _ in pairs(state.done) do
                completed += 1
        end

        return {
                complete = false,
                id = def.id,
                titleKey = def.titleKey,
                bodyKey = def.bodyKey,
                kind = def.kind,
                target = def.target,
                progress = math.min(state.progress, def.count),
                count = def.count,
                index = state.index,
                done = completed,
                total = #QUESTS,
        }
end

-- Restore from a save. Tolerates anything: a bad save must not lock a player out
-- of the spine, so the index is clamped and progress reset rather than trusted.
function Quests.fromSnapshot(data: any): State
        if type(data) ~= "table" then
                return Quests.new()
        end
        local index = math.floor(tonumber(data.index) or 1)
        local progress = math.floor(tonumber(data.progress) or 0)
        local done: { [string]: boolean } = {}
        if type(data.done) == "table" then
                for key, value in pairs(data.done) do
                        if type(key) == "string" and value == true then
                                done[key] = true
                        end
                end
        end
        return {
                index = math.clamp(index, 1, #QUESTS + 1),
                progress = math.max(0, progress),
                done = done,
        }
end

-- The fields the spine has sent the player to, in order. Used to check the story
-- actually visits every map rather than stopping at the Meadow.
function Quests.fieldOrder(): { string }
        local out: { string } = {}
        for _, def in ipairs(QUESTS) do
                if def.target and (def.kind == "ENTER_FIELD" or def.kind == "KILL_BOSS") then
                        table.insert(out, def.target)
                end
        end
        return out
end

return Quests

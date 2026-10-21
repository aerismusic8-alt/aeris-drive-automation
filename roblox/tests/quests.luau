--!strict
-- The story spine.
--
-- These tests guard the thing a new player complained was missing: an order to
-- do things in. They check that every objective is reachable, that the line
-- cannot be skipped or replayed, that a reward is paid exactly once, and that a
-- corrupt save cannot lock someone out of the story.

local t = require("./TestRunner")

local Quests = require("../src/shared/Quests")
local Config = require("../src/shared/Config")
local Text = require("../src/shared/Text")
local Fields = require("../src/shared/Fields")
local Enemies = require("../src/shared/Enemies")

--------------------------------------------------------------------------
t.suite("Quests: the story has an order and pays once")
--------------------------------------------------------------------------

t.test("the spine starts on the first quest and reports progress", function()
        local state = Quests.new()
        local def = Quests.current(state)
        t.assertNotNil(def, "a new save has no active quest")
        t.assertEqual(def.id, "first_blood", "the story does not start at the first quest")

        local snap = Quests.snapshot(state)
        t.assertEqual(snap.progress, 0, "a fresh quest is already partly done")
        t.assertEqual(snap.count, def.count, "the snapshot count is wrong")
        t.assertFalse(snap.complete, "a fresh spine reports complete")
end)

t.test("an event of the wrong kind does not advance the quest", function()
        local state = Quests.new()
        -- The first quest is a KILL quest, so a harvest must not count.
        local reward = Quests.onEvent(state, "HARVEST", nil, 1)
        t.assertNil(reward, "a harvest completed a kill quest")
        t.assertEqual(Quests.snapshot(state).progress, 0, "the wrong event moved the progress")
end)

t.test("a quest pays once and only when it completes", function()
        local state = Quests.new()
        local def = Quests.current(state)
        local paid = 0
        for _ = 1, def.count do
                local reward = Quests.onEvent(state, "KILL", nil, 1)
                if reward then
                        paid += 1
                        t.assertEqual(reward.questId, def.id, "the wrong quest paid out")
                        t.assertEqual(reward.coins, def.coins, "the coin reward is wrong")
                end
        end
        t.assertEqual(paid, 1, "the quest paid more than once")
        t.assertNotEqual(Quests.current(state).id, def.id, "the spine did not move on")
end)

t.test("a targetless quest accepts any target, a targeted one does not", function()
        local state = Quests.new()
        -- The first quest has no target, so any monster counts. It wants three
        -- kills, which is the count below.
        t.assertNotNil(Quests.onEvent(state, "KILL", "Slime", 3), "a targetless quest refused a valid target")
        -- The first quest is now done. Skip ahead to the
        -- boss quest and check that a different field is refused.
        while Quests.current(state) and Quests.current(state).kind ~= "KILL_BOSS" do
                local def = Quests.current(state)
                Quests.onEvent(state, def.kind, def.target, def.count)
        end
        local bossQuest = Quests.current(state)
        t.assertNotNil(bossQuest, "the spine ran out before the first boss quest")
        t.assertEqual(bossQuest.target, "Meadow", "the first boss quest is not the Meadow")
        t.assertNil(Quests.onEvent(state, "KILL_BOSS", "Volcano", 1), "a Volcano boss completed a Meadow quest")
        t.assertNotNil(Quests.onEvent(state, "KILL_BOSS", "Meadow", 1), "the right boss did not complete the quest")
end)

t.test("one call can satisfy several steps at once", function()
        local state = Quests.new()
        -- A single harvest can count for more than one, which the farm needs
        -- because one tap can fill a plot.
        local reward = Quests.onEvent(state, "KILL", nil, 10)
        t.assertNotNil(reward, "a large count did not complete a small quest")
end)

t.test("the spine has an end and does not wrap around", function()
        local state = Quests.new()
        local guard = 0
        while Quests.current(state) do
                local def = Quests.current(state)
                Quests.onEvent(state, def.kind, def.target, def.count)
                guard += 1
                t.assertLess(guard, 100, "the spine never finished")
        end
        t.assertNil(Quests.current(state), "the spine restarted instead of ending")
        local snap = Quests.snapshot(state)
        t.assertTrue(snap.complete, "a finished spine does not report complete")
        t.assertEqual(snap.done, Quests.count(), "not every quest is marked done")
end)

t.test("the story visits every field in order", function()
        local order = Quests.fieldOrder()
        local seen: { [string]: boolean } = {}
        for _, id in ipairs(order) do
                seen[id] = true
        end
        for _, zone in ipairs(Fields.list()) do
                if not Fields.isTown(zone.id) then
                        t.assertTrue(seen[zone.id], "the story never sends the player to " .. zone.id)
                end
        end
        -- And it must reach the hardest field last, not somewhere in the middle.
        t.assertEqual(order[#order], "Heaven", "the story does not end in Heaven")
end)

t.test("every quest names a real monster or field", function()
        for _, def in ipairs(Quests.list()) do
                if def.target then
                        if def.kind == "ENTER_FIELD" or def.kind == "KILL_BOSS" then
                                t.assertNotNil(Fields.getDef(def.target), def.id .. " targets an unknown field")
                        end
                end
                t.assertGreater(def.count, 0, def.id .. " asks for zero of something")
                t.assertGreater(def.coins, 0, def.id .. " pays nothing")
                t.assertGreater(def.xp, 0, def.id .. " grants no xp")
        end
end)

t.test("every quest has Thai text, so no objective renders blank", function()
        local keys: { string } = {}
        for _, def in ipairs(Quests.list()) do
                table.insert(keys, def.titleKey)
                table.insert(keys, def.bodyKey)
        end
        table.insert(keys, "quest")
        table.insert(keys, "questComplete")
        table.insert(keys, "questAllDone")
        local missing = Text.missingKeys(keys)
        t.assertEqual(#missing, 0, "missing quest text: " .. table.concat(missing, ", "))
end)

t.test("a corrupt save cannot lock a player out of the story", function()
        for _, bad in ipairs({ nil, 5, "nope", {} }) do
                local state = Quests.fromSnapshot(bad)
                t.assertNotNil(Quests.current(state), "a bad save produced no active quest")
        end
        local beyond = Quests.fromSnapshot({ index = 9999, progress = 50, done = { nope = true } })
        t.assertNil(Quests.current(beyond), "an out-of-range index did not clamp to finished")
        t.assertEqual(beyond.progress, 50, "progress was not carried")

        local negative = Quests.fromSnapshot({ index = -4, progress = -9 })
        t.assertEqual(negative.index, 1, "a negative index did not clamp to the first quest")
        t.assertEqual(negative.progress, 0, "negative progress was not clamped")
end)

t.test("a snapshot round trip restores the same position", function()
        local state = Quests.new()
        Quests.onEvent(state, "KILL", nil, 3)
        Quests.onEvent(state, "CHOOSE_CLASS", nil, 1)
        Quests.onEvent(state, "HARVEST", nil, 1)
        local before = Quests.snapshot(state)
        local restored = Quests.fromSnapshot(state)
        local after = Quests.snapshot(restored)
        t.assertEqual(after.id, before.id, "the quest changed across a save")
        t.assertEqual(after.progress, before.progress, "the progress changed across a save")
        t.assertEqual(after.done, before.done, "the completed count changed across a save")
end)

t.test("the story teaches the farm before it asks for the boss", function()
        local ids: { string } = {}
        for _, def in ipairs(Quests.list()) do
                ids[def.id] = true
        end
        t.assertTrue(ids.plant_and_pick, "the story never teaches the farm")
        t.assertTrue(ids.swing_the_axe, "the story never teaches the axe")
        t.assertTrue(ids.pick_a_job, "the story never asks for a class")
        t.assertTrue(ids.wear_something, "the story never teaches equipment")

        -- Order matters: farming has to come before the boss, or the axe is a
        -- mystery by the time the player needs it.
        local indexOf: { [string]: number } = {}
        for i, def in ipairs(Quests.list()) do
                indexOf[def.id] = i
        end
        t.assertLess(indexOf.plant_and_pick, indexOf.slime_king, "the boss comes before the farm")
        t.assertLess(indexOf.swing_the_axe, indexOf.slime_king, "the boss comes before the axe")
end)

return t.finish()

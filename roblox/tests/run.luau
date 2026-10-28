--!strict
-- Shared game logic test suite. Runs under the standalone Luau CLI:
--   luau roblox/tests/run.luau

local t = require("./TestRunner")

local Config = require("../src/shared/Config")
local Random = require("../src/shared/Random")
local Stats = require("../src/shared/Stats")
local Inventory = require("../src/shared/Inventory")
local Combat = require("../src/shared/Combat")
local WaveDirector = require("../src/shared/WaveDirector")
local SaveSchema = require("../src/shared/SaveSchema")
local RateLimiter = require("../src/shared/RateLimiter")
local Leveling = require("../src/shared/Leveling")
local Pets = require("../src/shared/Pets")
local Rebirth = require("../src/shared/Rebirth")
local Zones = require("../src/shared/Zones")
local Monetization = require("../src/shared/Monetization")
local DailyRewards = require("../src/shared/DailyRewards")
local Codes = require("../src/shared/Codes")
local Farm = require("../src/shared/Farm")
local Enemies = require("../src/shared/Enemies")
local Fields = require("../src/shared/Fields")
local Axe = require("../src/shared/Axe")
local Text = require("../src/shared/Text")
local Attributes = require("../src/shared/Attributes")
local Classes = require("../src/shared/Classes")
local Skills = require("../src/shared/Skills")
local Items = require("../src/shared/Items")
local Villagers = require("../src/shared/Villagers")
local Death = require("../src/shared/Death")

--------------------------------------------------------------------------
t.suite("Random")
--------------------------------------------------------------------------

t.test("is deterministic for a fixed seed", function()
	local a = Random.new(12345)
	local b = Random.new(12345)
	for i = 1, 50 do
		t.assertEqual(a:nextInt(), b:nextInt(), "draw " .. i)
	end
end)

t.test("different seeds diverge", function()
	local a = Random.new(1)
	local b = Random.new(2)
	local same = 0
	for _ = 1, 20 do
		if a:nextInt() == b:nextInt() then
			same += 1
		end
	end
	t.assertLess(same, 5, "unexpectedly many collisions")
end)

t.test("nextInt stays inside 32 bits", function()
	local rng = Random.new(99)
	for _ = 1, 500 do
		local v = rng:nextInt()
		t.assertTrue(v >= 0 and v < 4294967296, "out of range: " .. tostring(v))
		t.assertEqual(v, math.floor(v), "must be integral")
	end
end)

t.test("nextNumber is in [0, 1)", function()
	local rng = Random.new(7)
	for _ = 1, 500 do
		local v = rng:nextNumber()
		t.assertTrue(v >= 0 and v < 1, "out of range: " .. tostring(v))
	end
end)

t.test("nextInteger respects inclusive bounds", function()
	local rng = Random.new(3)
	local seenMin, seenMax = false, false
	for _ = 1, 1000 do
		local v = rng:nextInteger(1, 6)
		t.assertTrue(v >= 1 and v <= 6, "out of range: " .. tostring(v))
		t.assertEqual(v, math.floor(v), "must be integral")
		seenMin = seenMin or v == 1
		seenMax = seenMax or v == 6
	end
	t.assertTrue(seenMin, "never produced the minimum")
	t.assertTrue(seenMax, "never produced the maximum")
end)

t.test("nextInteger with a single-value range", function()
	local rng = Random.new(4)
	for _ = 1, 10 do
		t.assertEqual(rng:nextInteger(5, 5), 5)
	end
end)

t.test("nextInteger rejects inverted bounds", function()
	local rng = Random.new(5)
	t.assertThrows(function()
		rng:nextInteger(10, 1)
	end)
end)

t.test("pickWeighted ignores non-positive weights", function()
	local rng = Random.new(11)
	local picked = rng:pickWeighted({
		{ id = "zero", weight = 0 },
		{ id = "only", weight = 5 },
	})
	t.assertNotNil(picked)
	t.assertEqual(picked.id, "only")
end)

t.test("pickWeighted returns nil when nothing is positive", function()
	local rng = Random.new(12)
	t.assertNil(rng:pickWeighted({ { id = "a", weight = 0 } }))
	t.assertNil(rng:pickWeighted({}))
end)

t.test("pickWeighted distribution roughly matches weights", function()
	local rng = Random.new(2024)
	local counts = { rare = 0, common = 0 }
	for _ = 1, 10000 do
		local picked = rng:pickWeighted({
			{ id = "rare", weight = 10 },
			{ id = "common", weight = 90 },
		})
		counts[picked.id] += 1
	end
	-- Expect ~10% rare; allow a wide band so the test is not flaky.
	t.assertTrue(counts.rare > 700 and counts.rare < 1300, "rare=" .. tostring(counts.rare))
end)

--------------------------------------------------------------------------
t.suite("Stats")
--------------------------------------------------------------------------

t.test("upgrade cost grows with level", function()
	local first = Stats.upgradeCost("Damage", 0)
	local second = Stats.upgradeCost("Damage", 1)
	local third = Stats.upgradeCost("Damage", 2)
	t.assertEqual(first, Config.Upgrades.Damage.BaseCost)
	t.assertTrue(second > first, "cost must increase")
	t.assertTrue(third > second, "cost must keep increasing")
end)

t.test("upgrade cost at max level is infinite", function()
	local max = Config.Upgrades.Health.MaxLevel
	t.assertEqual(Stats.upgradeCost("Health", max), math.huge)
end)

t.test("unknown upgrade is rejected", function()
	t.assertThrows(function()
		Stats.upgradeCost("Nope", 0)
	end)
end)

t.test("newUpgrades starts every upgrade at zero", function()
	local upgrades = Stats.newUpgrades()
	for _, id in ipairs(Config.UpgradeOrder) do
		t.assertEqual(upgrades[id], 0, id)
	end
end)

t.test("applyUpgrade deducts coins and raises the level", function()
	local upgrades = Stats.newUpgrades()
	local cost = Stats.upgradeCost("Damage", 0)
	local ok, result, remaining = Stats.applyUpgrade(upgrades, "Damage", cost + 50)
	t.assertTrue(ok, "upgrade should succeed")
	local next = result
	t.assertEqual(next.Damage, 1)
	t.assertEqual(remaining, 50)
	t.assertEqual(upgrades.Damage, 0, "original table must be untouched")
end)

t.test("applyUpgrade fails without enough coins", function()
	local upgrades = Stats.newUpgrades()
	local ok, reason, remaining = Stats.applyUpgrade(upgrades, "Damage", 1)
	t.assertFalse(ok)
	t.assertEqual(reason, "INSUFFICIENT_COINS")
	t.assertNil(remaining)
end)

t.test("applyUpgrade fails at max level", function()
	local upgrades = Stats.newUpgrades()
	upgrades.Damage = Config.Upgrades.Damage.MaxLevel
	local ok, reason = Stats.applyUpgrade(upgrades, "Damage", 1e9)
	t.assertFalse(ok)
	t.assertEqual(reason, "MAX_LEVEL")
end)

t.test("derive applies per-level bonuses", function()
	local base = Stats.derive(Stats.newUpgrades())
	local upgraded = Stats.derive({ Damage = 5, Health = 2, Speed = 3, CritChance = 4 })
	t.assertEqual(base.damage, Config.Player.BaseDamage)
	t.assertEqual(upgraded.damage, Config.Player.BaseDamage + Config.Upgrades.Damage.PerLevel * 5)
	t.assertEqual(upgraded.maxHealth, Config.Player.BaseHealth + Config.Upgrades.Health.PerLevel * 2)
	t.assertNear(upgraded.walkSpeed, Config.Player.BaseWalkSpeed + Config.Upgrades.Speed.PerLevel * 3)
	t.assertNear(upgraded.critChance, Config.Player.BaseCritChance + Config.Upgrades.CritChance.PerLevel * 4)
end)

t.test("derive clamps over-max levels and caps", function()
	local extreme = Stats.derive({
		Damage = 9999,
		Health = 9999,
		Speed = 9999,
		CritChance = 9999,
	})
	t.assertEqual(
		extreme.critChance,
		math.min(Config.Player.BaseCritChance + Config.Upgrades.CritChance.PerLevel * Config.Upgrades.CritChance.MaxLevel, 1),
		"crit chance is clamped to the max level"
	)
	t.assertTrue(extreme.critChance <= 1, "crit chance must never exceed 1")
	t.assertTrue(extreme.maxHealth <= Config.Player.MaxHealth, "health must respect the cap")

	-- Maxing Health stays below the cap, so it should reach exactly that value.
	local maxedHealth = Config.Player.BaseHealth + Config.Upgrades.Health.PerLevel * Config.Upgrades.Health.MaxLevel
	local single = Stats.derive({ Health = Config.Upgrades.Health.MaxLevel, Damage = 0, Speed = 0, CritChance = 0 })
	t.assertEqual(single.maxHealth, math.min(maxedHealth, Config.Player.MaxHealth))
	t.assertTrue(single.maxHealth <= Config.Player.MaxHealth, "health must respect the cap")
end)

t.test("rollDamage crits deterministically", function()
	local alwaysCrit = { damage = 10, critChance = 1, critMultiplier = 2 }
	local amount, isCrit = Stats.rollDamage(alwaysCrit, Random.new(1))
	t.assertTrue(isCrit)
	t.assertEqual(amount, 20)

	local neverCrit = { damage = 10, critChance = 0, critMultiplier = 2 }
	local plain, plainCrit = Stats.rollDamage(neverCrit, Random.new(1))
	t.assertFalse(plainCrit)
	t.assertEqual(plain, 10)
end)

--------------------------------------------------------------------------
t.suite("Combat")
--------------------------------------------------------------------------

t.test("damage reduces health without killing", function()
	Combat._resetIds()
	local enemy = Combat.createEnemy({ wave = 1, enemyHealth = 100, enemyDamage = 5, reward = 10 }, 0)
	local killed, reward = Combat.damageEnemy(enemy, 30)
	t.assertFalse(killed)
	t.assertEqual(reward, 0)
	t.assertEqual(enemy.health, 70)
	t.assertTrue(enemy.alive)
end)

t.test("lethal damage kills and pays out once", function()
	Combat._resetIds()
	local enemy = Combat.createEnemy({ wave = 1, enemyHealth = 50, enemyDamage = 5, rewardPerKill = 33 }, 0)
	local killed, reward, overkill = Combat.damageEnemy(enemy, 80)
	t.assertTrue(killed)
	t.assertEqual(reward, 33)
	t.assertEqual(overkill, 30)
	t.assertEqual(enemy.health, 0)
	t.assertFalse(enemy.alive)

	local again, secondReward = Combat.damageEnemy(enemy, 10)
	t.assertFalse(again, "a dead enemy must not die twice")
	t.assertEqual(secondReward, 0, "no double payout")
end)

t.test("non-positive damage is a no-op", function()
	Combat._resetIds()
	local enemy = Combat.createEnemy({ wave = 1, enemyHealth = 10, enemyDamage = 1, reward = 1 }, 0)
	local killed = Combat.damageEnemy(enemy, 0)
	t.assertFalse(killed)
	t.assertEqual(enemy.health, 10)
end)

t.test("player damage floors at zero and reports death", function()
	local player = Combat.createCombatant(100)
	local died, health = Combat.damageCombatant(player, 40)
	t.assertFalse(died)
	t.assertEqual(health, 60)

	died, health = Combat.damageCombatant(player, 999)
	t.assertTrue(died)
	t.assertEqual(health, 0)
	t.assertFalse(player.alive)
end)

t.test("a non-lethal hit floors at 1 HP instead of killing", function()
        -- The first field is the practice map: a monster there can hurt the
        -- player but never finish them, so a new character can grind forever.
        local player = Combat.createCombatant(100)
        local died, health = Combat.damageCombatant(player, 999, true)
        t.assertFalse(died, "the first field killed the player")
        t.assertEqual(health, 1)
        t.assertTrue(player.alive, "the player died in the safe field")

        -- Another hit must not sneak through the floor either.
        died, health = Combat.damageCombatant(player, 999, true)
        t.assertFalse(died, "a second hit killed the player")
        t.assertEqual(health, 1)
end)

t.test("a lethal hit in a later field still kills", function()
        local player = Combat.createCombatant(100)
        local died, health = Combat.damageCombatant(player, 999, false)
        t.assertTrue(died)
        t.assertEqual(health, 0)
        t.assertFalse(player.alive)

        -- And the default is lethal, so a caller that forgets the flag cannot
        -- accidentally make the whole game safe.
        local other = Combat.createCombatant(100)
        died = Combat.damageCombatant(other, 999)
        t.assertTrue(died)
end)

t.test("healing cannot exceed max health or revive the dead", function()
	local player = Combat.createCombatant(100)
	Combat.damageCombatant(player, 30)
	t.assertEqual(Combat.healCombatant(player, 500), 100)
	t.assertEqual(Combat.healCombatant(player, 10), 100)

	local dead = Combat.createCombatant(50)
	Combat.damageCombatant(dead, 50)
	Combat.healCombatant(dead, 10)
	t.assertFalse(dead.alive, "healing must not resurrect")
end)

t.test("createCombatant rejects invalid health", function()
	t.assertThrows(function()
		Combat.createCombatant(0)
	end)
end)

t.test("attacksDue batches missed attack windows", function()
	Combat._resetIds()
	local interval = Config.Wave.EnemyAttackInterval
	local enemy = Combat.createEnemy({ wave = 1, enemyHealth = 10, enemyDamage = 1, reward = 1 }, 0)
	local count, nextAt = Combat.attacksDue(enemy, interval - 0.1)
	t.assertEqual(count, 0)
	t.assertEqual(nextAt, interval)

	count, nextAt = Combat.attacksDue(enemy, interval * 3 + 0.01)
	t.assertEqual(count, 3)
	t.assertNear(nextAt, interval * 4)
end)

--------------------------------------------------------------------------
t.suite("WaveDirector")
--------------------------------------------------------------------------

t.test("starts in intermission at wave zero", function()
	local director = WaveDirector.new(Random.new(1))
	local snap = director:snapshot()
	t.assertEqual(snap.phase, "INTERMISSION")
	t.assertEqual(snap.wave, 0)
	t.assertEqual(snap.timeRemaining, Config.Wave.IntermissionSeconds)
end)

t.test("first update after intermission begins wave one", function()
	local director = WaveDirector.new(Random.new(1))
	local events = director:advance(Config.Wave.IntermissionSeconds + 0.01)
	t.assertEqual(#events, 1, "wave start emits the opening plan")
	t.assertEqual(director:snapshot().wave, 1)
	t.assertEqual(director:snapshot().phase, "ACTIVE")
end)

t.test("enemy count and health scale with the wave", function()
	local director = WaveDirector.new(Random.new(1))
	local w1 = director:planFor(1)
	local w5 = director:planFor(5)
	t.assertEqual(w1.enemyCount, Config.Wave.BaseEnemyCount)
	t.assertEqual(w5.enemyCount, Config.Wave.BaseEnemyCount + Config.Wave.EnemiesPerWave * 4)
	t.assertTrue(w5.enemyHealth > w1.enemyHealth, "health must scale")
	t.assertTrue(w5.rewardPerKill > w1.rewardPerKill, "rewards must scale")
end)

t.test("enemy count is capped", function()
	local director = WaveDirector.new(Random.new(1))
	t.assertEqual(director:planFor(10000).enemyCount, Config.Wave.MaxEnemiesPerWave)
end)

t.test("spawns are throttled by the spawn interval", function()
	local director = WaveDirector.new(Random.new(1))
	director:advance(Config.Wave.IntermissionSeconds + 0.01)
	local plan = director:planFor(1)
	-- Each spawn needs one tick of accumulation, so N enemies need N ticks.
	local events = director:advance(plan.spawnInterval * (plan.enemyCount - 1) + 0.001)
	local spawned = #events
	t.assertTrue(spawned > 0, "some enemies should spawn")
	t.assertLess(spawned, plan.enemyCount, "the wave must not spawn instantly")
end)

t.test("wave completes only after all spawns and kills", function()
	local director = WaveDirector.new(Random.new(1))
	director:advance(Config.Wave.IntermissionSeconds + 0.01)
	local plan = director:planFor(1)
	local totalSpawned = 0
	local completed = false

	for _ = 1, 400 do
		local events, done = director:advance(0.1)
		for _ = 1, #events do
			totalSpawned += 1
			director:notifyEnemySpawned()
		end
		-- Kill everything that has spawned so far.
		while director:snapshot().aliveEnemies > 0 do
			director:notifyEnemyRemoved()
		end
		if done then
			completed = true
			break
		end
	end

	t.assertTrue(completed, "wave should eventually complete")
	t.assertEqual(totalSpawned, plan.enemyCount, "every planned enemy must spawn")
	t.assertEqual(director:snapshot().phase, "INTERMISSION")
end)

t.test("reset returns the director to its initial state", function()
	local director = WaveDirector.new(Random.new(1))
	director:advance(Config.Wave.IntermissionSeconds + 0.01)
	director:reset()
	local snap = director:snapshot()
	t.assertEqual(snap.wave, 0)
	t.assertEqual(snap.phase, "INTERMISSION")
	t.assertEqual(snap.pendingSpawns, 0)
	t.assertEqual(snap.aliveEnemies, 0)
end)

t.test("large delta times are clamped", function()
	local director = WaveDirector.new(Random.new(1))
	director:advance(Config.Wave.IntermissionSeconds + 0.01)
	local before = director:snapshot().elapsed
	director:update(9999)
	local after = director:snapshot().elapsed
	t.assertLess(after, before + Config.Tick.MaxDeltaTime + 0.001, "dt must be clamped")
end)

--------------------------------------------------------------------------
t.suite("Inventory")
--------------------------------------------------------------------------

t.test("adds items and reports overflow", function()
	local inv = Inventory.new(2)
	t.assertEqual(inv:add("Wood", 10), 0)
	t.assertEqual(inv:count("Wood"), 10)
	t.assertEqual(inv:usedSlots(), 1)
end)

t.test("stacks up to maxStack then opens a new slot", function()
	local inv = Inventory.new(5)
	local def = Inventory.getItemDef("Wood")
	t.assertEqual(inv:add("Wood", def.maxStack + 5), 0)
	t.assertEqual(inv:count("Wood"), def.maxStack + 5)
	t.assertEqual(inv:usedSlots(), 2, "should occupy two slots")
end)

t.test("returns the amount that does not fit", function()
	local inv = Inventory.new(1)
	local def = Inventory.getItemDef("Wood")
	local leftover = inv:add("Wood", def.maxStack + 25)
	t.assertEqual(leftover, 25)
	t.assertEqual(inv:count("Wood"), def.maxStack)
end)

t.test("rejects unknown items", function()
	local inv = Inventory.new(2)
	t.assertEqual(inv:add("Unobtainium", 5), 5, "unknown items are refused")
	t.assertEqual(inv:count("Unobtainium"), 0)
end)

t.test("remove takes from partial stacks and frees empty slots", function()
	local inv = Inventory.new(3)
	inv:add("Stone", 150)
	t.assertEqual(inv:count("Stone"), 150)
	t.assertEqual(inv:remove("Stone", 120), 120)
	t.assertEqual(inv:count("Stone"), 30)
	t.assertEqual(inv:remove("Stone", 30), 30)
	t.assertEqual(inv:usedSlots(), 0, "emptied slots must be released")
end)

t.test("remove never returns more than it holds", function()
	local inv = Inventory.new(2)
	inv:add("Iron", 5)
	t.assertEqual(inv:remove("Iron", 100), 5)
	t.assertEqual(inv:count("Iron"), 0)
end)

t.test("snapshot round-trips through fromSnapshot", function()
	local inv = Inventory.new(5)
	inv:add("Wood", 120)
	inv:add("Relic", 3)
	local restored = Inventory.fromSnapshot(inv:snapshot(), 5)
	t.assertEqual(restored:count("Wood"), 120)
	t.assertEqual(restored:count("Relic"), 3)
end)

t.test("fromSnapshot drops unknown items", function()
	local restored = Inventory.fromSnapshot({
		{ itemId = "Wood", count = 5 },
		{ itemId = "Bogus", count = 99 },
	}, 5)
	t.assertEqual(restored:count("Wood"), 5)
	t.assertEqual(restored:usedSlots(), 1)
end)

t.test("invalid capacity is rejected", function()
	t.assertThrows(function()
		Inventory.new(0)
	end)
	t.assertThrows(function()
		Inventory.new(Config.Inventory.MaxCapacity + 1)
	end)
end)

t.test("rollLoot always returns a known item", function()
	local rng = Random.new(42)
	for _ = 1, 200 do
		local def = Inventory.rollLoot(rng, 1)
		t.assertNotNil(def)
		t.assertNotNil(Inventory.getItemDef(def.id))
	end
end)

--------------------------------------------------------------------------
t.suite("SaveSchema")
--------------------------------------------------------------------------

t.test("new save is valid", function()
	local save = SaveSchema.new()
	local ok, problems = SaveSchema.validate(save)
	t.assertTrue(ok, table.concat(problems, ","))
end)

t.test("rejects a non-table root", function()
	local ok, problems = SaveSchema.validate("nope")
	t.assertFalse(ok)
	t.assertEqual(problems[1], "ROOT_NOT_TABLE")
end)

t.test("rejects negative coins", function()
	local save = SaveSchema.new()
	save.coins = -5
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "INVALID_COINS")
end)

t.test("rejects out-of-range upgrade levels", function()
	local save = SaveSchema.new()
	save.upgrades.Damage = Config.Upgrades.Damage.MaxLevel + 1
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "INVALID_UPGRADE:Damage")
end)

t.test("rejects unknown inventory items", function()
	local save = SaveSchema.new()
	save.inventory = { { itemId = "Fake", count = 1 } }
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "UNKNOWN_ITEM:Fake")
end)

t.test("rejects a future schema version", function()
	local save = SaveSchema.new()
	save.version = Config.Persistence.SchemaVersion + 1
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "FUTURE_VERSION")
end)

t.test("rejects a pre-minimum schema version", function()
	local save = SaveSchema.new()
	save.version = Config.Persistence.MinSupportedVersion - 1
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "UNSUPPORTED_VERSION")
end)

t.test("migrates a v1 save by adding new upgrade keys", function()
	local legacy = {
		version = 1,
		coins = 500,
		upgrades = { Damage = 3 },
		inventory = { { itemId = "Wood", count = 7 } },
		stats = { kills = 4, wavesCleared = 1, deaths = 0 },
		updatedAt = 100,
	}
	local migrated = SaveSchema.migrate(legacy)
	t.assertNotNil(migrated)
	local data = migrated
	t.assertEqual(data.version, Config.Persistence.SchemaVersion)
	t.assertEqual(data.coins, 500)
	t.assertEqual(data.upgrades.Damage, 3)
	for _, id in ipairs(Config.UpgradeOrder) do
		t.assertNotNil(data.upgrades[id], "missing upgrade after migration: " .. id)
	end
	local ok = SaveSchema.validate(data)
	t.assertTrue(ok)
end)

t.test("migrate refuses data beyond the supported range", function()
	t.assertNil(SaveSchema.migrate(nil))
	t.assertNil(SaveSchema.migrate({ version = 99 }))
	t.assertNil(SaveSchema.migrate({ version = 0 }))
end)

t.test("load validates migrated output", function()
	local data, problems = SaveSchema.load({
		version = 1,
		coins = 10,
		upgrades = {},
		inventory = {},
		stats = { kills = 0, wavesCleared = 0, deaths = 0 },
	})
	t.assertNotNil(data)
	t.assertEqual(#problems, 0)

	local bad, badProblems = SaveSchema.load({
		version = 1,
		coins = 10,
		upgrades = {},
		inventory = { { itemId = "NotARealItem", count = 1 } },
		stats = { kills = 0, wavesCleared = 0, deaths = 0 },
	})
	t.assertNil(bad)
	t.assertTrue(#badProblems > 0, "bad saves must report problems")
end)

t.test("serialize emits deterministic ordered JSON", function()
	local save = SaveSchema.new()
	save.coins = 321
	save.upgrades.Damage = 2
	save.inventory = { { itemId = "Iron", count = 4 } }
	save.stats.kills = 9

	local first = SaveSchema.serialize(save, 1000)
	local second = SaveSchema.serialize(save, 1000)
	t.assertEqual(first, second, "serialization must be stable")
	t.assertContains(first, '"coins":321')
	t.assertContains(first, '"Damage":2')
	t.assertContains(first, '"kills":9')
	t.assertContains(first, '"updatedAt":1000')

	local keys = { "Damage", "Health", "Speed", "CritChance" }
	local lastPos = 0
	for _, key in ipairs(keys) do
		local pos = string.find(first, '"' .. key .. '":', 1, true)
		t.assertNotNil(pos, "missing key " .. key)
		t.assertTrue((pos) > lastPos, "keys must be in canonical order")
		lastPos = pos
	end
end)

t.test("serialize floors fractional numbers", function()
	local save = SaveSchema.new()
	save.coins = 10.9
	local text = SaveSchema.serialize(save, 5.7)
	t.assertContains(text, '"coins":10')
	t.assertContains(text, '"updatedAt":5')
end)

--------------------------------------------------------------------------
t.suite("RateLimiter")
--------------------------------------------------------------------------

t.test("allows a burst then throttles", function()
	local limiter = RateLimiter.new(3, 1)
	local allowed = 0
	for _ = 1, 10 do
		local ok = limiter:consume("player1", 0)
		if ok then
			allowed += 1
		end
	end
	t.assertEqual(allowed, 3, "burst size must be respected")
end)

t.test("reports a sensible retry delay", function()
	local limiter = RateLimiter.new(1, 2)
	t.assertTrue(limiter:consume("p", 0))
	local ok, retryAfter = limiter:consume("p", 0)
	t.assertFalse(ok)
	t.assertNear(retryAfter, 0.5, 1e-6)
end)

t.test("refills over time", function()
	local limiter = RateLimiter.new(2, 10)
	limiter:consume("p", 0)
	limiter:consume("p", 0)
	local ok = limiter:consume("p", 0)
	t.assertFalse(ok, "bucket should be empty")
	ok = limiter:consume("p", 0.1)
	t.assertTrue(ok, "one token should have refilled")
end)

t.test("refill never exceeds the burst ceiling", function()
	local limiter = RateLimiter.new(2, 100)
	limiter:consume("p", 0)
	limiter:consume("p", 0)
	local allowed = 0
	for _ = 1, 50 do
		if limiter:consume("p", 1000) then
			allowed += 1
		end
	end
	t.assertEqual(allowed, 2, "long idle time must not bank extra tokens")
end)

t.test("tracks players independently", function()
	local limiter = RateLimiter.new(1, 1)
	t.assertTrue(limiter:consume("a", 0))
	t.assertFalse(limiter:consume("a", 0))
	t.assertTrue(limiter:consume("b", 0), "other players must be unaffected")
	t.assertEqual(limiter:tracked(), 2)
end)

t.test("forget drops a player's bucket", function()
	local limiter = RateLimiter.new(1, 1)
	limiter:consume("a", 0)
	limiter:forget("a")
	t.assertEqual(limiter:tracked(), 0)
	t.assertTrue(limiter:consume("a", 0), "a forgotten player starts fresh")
end)

--------------------------------------------------------------------------
t.suite("Config")
--------------------------------------------------------------------------

t.test("upgrade order matches the upgrade table", function()
	for _, id in ipairs(Config.UpgradeOrder) do
		t.assertNotNil(Config.Upgrades[id], "missing upgrade def: " .. id)
	end
	local seen = {}
	for id in pairs(Config.Upgrades) do
		t.assertFalse(seen[id], "duplicate upgrade: " .. id)
		seen[id] = true
	end
	local count = 0
	for _ in pairs(Config.Upgrades) do
		count += 1
	end
	t.assertEqual(count, #Config.UpgradeOrder, "order list must cover every upgrade")
end)

t.test("economy and capacity limits are sane", function()
	t.assertTrue(Config.Economy.StartingCoins > 0)
	t.assertTrue(Config.Economy.MaxCoins > Config.Economy.StartingCoins)
	t.assertTrue(Config.Inventory.DefaultCapacity > 0)
	t.assertTrue(Config.Inventory.MaxCapacity >= Config.Inventory.DefaultCapacity)
end)

--------------------------------------------------------------------------
t.suite("Leveling")
--------------------------------------------------------------------------

t.test("first level requires the base XP", function()
	t.assertEqual(Leveling.xpForNext(1), Config.Leveling.BaseXp)
end)

t.test("XP requirement grows with level", function()
	local prev = Leveling.xpForNext(1)
	for level = 2, 12 do
		local cur = Leveling.xpForNext(level)
		t.assertGreater(cur, prev, "level " .. level)
		prev = cur
	end
end)

t.test("cap returns infinity so callers stop levelling", function()
	t.assertEqual(Leveling.xpForNext(Config.Leveling.MaxLevel), math.huge)
	t.assertEqual(Leveling.xpForNext(Config.Leveling.MaxLevel + 5), math.huge)
end)

t.test("awarding XP below the threshold does not level up", function()
	local progress, gained = Leveling.addXp(Leveling.new(), Config.Leveling.BaseXp - 1)
	t.assertEqual(progress.level, 1)
	t.assertEqual(gained, 0)
	t.assertEqual(progress.xp, Config.Leveling.BaseXp - 1)
end)

t.test("awarding exactly the threshold levels up once", function()
	local progress, gained = Leveling.addXp(Leveling.new(), Config.Leveling.BaseXp)
	t.assertEqual(progress.level, 2)
	t.assertEqual(gained, 1)
	t.assertEqual(progress.xp, 0)
end)

t.test("a large award carries across multiple levels", function()
	local huge = Leveling.totalXpToReach(6)
	local progress, gained = Leveling.addXp(Leveling.new(), huge)
	t.assertEqual(progress.level, 6)
	t.assertEqual(gained, 5)
end)

t.test("XP never exceeds the cap", function()
	local progress = Leveling.addXp(Leveling.new(), 1e15)
	t.assertEqual(progress.level, Config.Leveling.MaxLevel)
	t.assertEqual(progress.xp, 0)
end)

t.test("negative XP is rejected", function()
	t.assertThrows(function()
		Leveling.addXp(Leveling.new(), -1)
	end)
end)

t.test("kill XP increases with wave", function()
	t.assertGreater(Leveling.xpFromKill(2), Leveling.xpFromKill(1))
	t.assertEqual(Leveling.xpFromKill(1), Config.Leveling.BaseXpPerKill)
end)

t.test("coin multiplier grows with level and is 1 at level 1", function()
	t.assertEqual(Leveling.coinMultiplier(1), 1)
	t.assertGreater(Leveling.coinMultiplier(50), Leveling.coinMultiplier(10))
end)

t.test("progress ratio stays within 0 and 1", function()
	t.assertEqual(Leveling.progressRatio(Leveling.new()), 0)
	local half = { level = 1, xp = Config.Leveling.BaseXp / 2 }
	t.assertNear(Leveling.progressRatio(half), 0.5, 1e-9)
	local capped = { level = Config.Leveling.MaxLevel, xp = 0 }
	t.assertEqual(Leveling.progressRatio(capped), 1)
end)

t.test("total XP to reach level 1 is zero", function()
	t.assertEqual(Leveling.totalXpToReach(1), 0)
end)

--------------------------------------------------------------------------
t.suite("Pets")
--------------------------------------------------------------------------

t.test("every egg references a real pet", function()
	for _, egg in ipairs(Pets.listEggs()) do
		t.assertTrue(#egg.weights > 0, egg.id .. " has weights")
		for _, entry in ipairs(egg.weights) do
			t.assertNotNil(Pets.getDef(entry.petId), egg.id .. " -> " .. entry.petId)
		end
	end
end)

t.test("every pet has a rarity listed in config", function()
	local known = {}
	for _, r in ipairs(Config.Pets.RarityOrder) do
		known[r] = true
	end
	for _, def in ipairs(Pets.listDefs()) do
		t.assertTrue(known[def.rarity] == true, def.id .. " rarity " .. def.rarity)
	end
end)

t.test("rolling an egg only ever yields pets from that egg", function()
	local rng = Random.new(7)
	local allowed = {}
	for _, entry in ipairs(Pets.getEgg("Basic").weights) do
		allowed[entry.petId] = true
	end
	for _ = 1, 300 do
		local def = Pets.roll(rng, "Basic")
		t.assertNotNil(def)
		t.assertTrue(allowed[def.id] == true, "unexpected " .. tostring(def and def.id))
	end
end)

t.test("rolling an unknown egg returns nil", function()
	t.assertNil(Pets.roll(Random.new(1), "Nope"))
end)

t.test("hatching spends coins and adds a pet", function()
	local inv = Pets.new()
	local def, remaining, err = Pets.hatch(inv, Random.new(3), "Basic", 1000, 1)
	t.assertNotNil(def)
	t.assertNil(err)
	t.assertEqual(remaining, 1000 - Pets.getEgg("Basic").cost)
	t.assertEqual(#inv.pets, 1)
	t.assertEqual(inv.hatches, 1)
end)

t.test("hatching without enough coins is refused", function()
	local inv = Pets.new()
	local def, remaining, err = Pets.hatch(inv, Random.new(3), "Basic", 0, 1)
	t.assertNil(def)
	t.assertNil(remaining)
	t.assertEqual(err, "INSUFFICIENT_COINS")
	t.assertEqual(#inv.pets, 0)
end)

t.test("hatching below the level requirement is refused", function()
	local inv = Pets.new()
	local _, _, err = Pets.hatch(inv, Random.new(3), "Mythic", 1e9, 1)
	t.assertEqual(err, "LEVEL_TOO_LOW")
end)

t.test("unknown egg is refused", function()
	local _, _, err = Pets.hatch(Pets.new(), Random.new(3), "Ghost", 1e9, 99)
	t.assertEqual(err, "UNKNOWN_EGG")
end)

t.test("pet uid never repeats", function()
	local inv = Pets.new()
	for _ = 1, 30 do
		Pets.hatch(inv, Random.new(11), "Basic", 1e6, 1)
	end
	local seen = {}
	for _, pet in ipairs(inv.pets) do
		t.assertNil(seen[pet.uid], "duplicate uid " .. pet.uid)
		seen[pet.uid] = true
	end
end)

t.test("equipping respects the slot limit", function()
	local inv = Pets.new()
	for _ = 1, 20 do
		Pets.hatch(inv, Random.new(5), "Basic", 1e6, 1)
	end
	for i = 1, Config.Pets.MaxEquipped do
		local ok = Pets.equip(inv, inv.pets[i].uid, false)
		t.assertTrue(ok, "slot " .. i)
	end
	local ok, reason = Pets.equip(inv, inv.pets[Config.Pets.MaxEquipped + 1].uid, false)
	t.assertFalse(ok)
	t.assertEqual(reason, "NO_SLOTS")
end)

t.test("VIP grants extra pet slots", function()
	local inv = Pets.new()
	for _ = 1, 20 do
		Pets.hatch(inv, Random.new(5), "Basic", 1e6, 1)
	end
	for i = 1, Pets.maxEquipped(true) do
		local ok = Pets.equip(inv, inv.pets[i].uid, true)
		t.assertTrue(ok, "vip slot " .. i)
	end
	t.assertGreater(Pets.maxEquipped(true), Pets.maxEquipped(false))
end)

t.test("equipping a pet you do not own is refused", function()
	local ok, reason = Pets.equip(Pets.new(), 999, false)
	t.assertFalse(ok)
	t.assertEqual(reason, "NOT_OWNED")
end)

t.test("equipping twice is idempotent", function()
	local inv = Pets.new()
	Pets.hatch(inv, Random.new(5), "Basic", 1e6, 1)
	local uid = inv.pets[1].uid
	t.assertTrue(Pets.equip(inv, uid, false))
	t.assertTrue(Pets.equip(inv, uid, false))
	t.assertEqual(#inv.equipped, 1)
end)

t.test("unequip removes the pet from the active list", function()
	local inv = Pets.new()
	Pets.hatch(inv, Random.new(5), "Basic", 1e6, 1)
	local uid = inv.pets[1].uid
	Pets.equip(inv, uid, false)
	t.assertTrue(Pets.unequip(inv, uid))
	t.assertEqual(#inv.equipped, 0)
	t.assertFalse(Pets.unequip(inv, uid))
end)

t.test("no equipped pets means no bonus", function()
	local coin, damage = Pets.equippedMultipliers(Pets.new())
	t.assertEqual(coin, 1)
	t.assertEqual(damage, 1)
end)

t.test("equipped multipliers compound", function()
	local inv = Pets.new()
	Pets.hatch(inv, Random.new(5), "Basic", 1e6, 1)
	Pets.equip(inv, inv.pets[1].uid, false)
	local coin, damage = Pets.equippedMultipliers(inv)
	local def = Pets.getDef(inv.pets[1].petId)
	t.assertNear(coin, def.coinMultiplier, 1e-9)
	t.assertNear(damage, def.damageMultiplier, 1e-9)
end)

t.test("snapshot round trip preserves pets and equips", function()
	local inv = Pets.new()
	for _ = 1, 5 do
		Pets.hatch(inv, Random.new(9), "Basic", 1e6, 1)
	end
	Pets.equip(inv, inv.pets[1].uid, false)
	Pets.equip(inv, inv.pets[2].uid, false)

	local restored = Pets.fromSnapshot(Pets.snapshot(inv))
	t.assertEqual(#restored.pets, #inv.pets)
	t.assertEqual(#restored.equipped, 2)
	t.assertEqual(restored.nextUid, inv.nextUid)
end)

t.test("fromSnapshot drops unknown pets and stale equips", function()
	local restored = Pets.fromSnapshot({
		pets = {
			{ uid = 1, petId = "Pup", level = 1 },
			{ uid = 2, petId = "NotAPet", level = 1 },
		},
		equipped = { 1, 2, 99 },
		nextUid = 3,
	})
	t.assertEqual(#restored.pets, 1)
	t.assertEqual(#restored.equipped, 1)
	t.assertEqual(restored.pets[1].petId, "Pup")
end)

t.test("fromSnapshot repairs duplicate and missing uids", function()
	local restored = Pets.fromSnapshot({
		pets = {
			{ petId = "Pup" },
			{ uid = 1, petId = "Kitten" },
		},
		equipped = {},
	})
	t.assertEqual(#restored.pets, 2)
	t.assertNotEqual(restored.pets[1].uid, restored.pets[2].uid)
	t.assertGreater(restored.nextUid, restored.pets[2].uid)
end)

t.test("fromSnapshot tolerates garbage", function()
	t.assertEqual(#Pets.fromSnapshot(nil).pets, 0)
	t.assertEqual(#Pets.fromSnapshot("nope").pets, 0)
end)

t.test("pet inventory capacity is enforced", function()
	local inv = Pets.new()
	inv.pets = {}
	for i = 1, Config.Pets.MaxInventory do
		table.insert(inv.pets, { uid = i, petId = "Pup", level = 1 })
	end
	local _, _, err = Pets.hatch(inv, Random.new(1), "Basic", 1e9, 1)
	t.assertEqual(err, "PET_INVENTORY_FULL")
end)

--------------------------------------------------------------------------
t.suite("Rebirth")
--------------------------------------------------------------------------

t.test("first rebirth requirement matches config", function()
	t.assertEqual(Rebirth.levelRequirement(0), Config.Rebirth.BaseLevelRequirement)
end)

t.test("requirement grows with each rebirth", function()
	local prev = Rebirth.levelRequirement(0)
	for c = 1, 6 do
		local cur = Rebirth.levelRequirement(c)
		t.assertGreater(cur, prev, "rebirth " .. c)
		prev = cur
	end
end)

t.test("requirement is infinite at the cap", function()
	t.assertEqual(Rebirth.levelRequirement(Config.Rebirth.MaxRebirths), math.huge)
end)

t.test("rebirth is refused below the level requirement", function()
	local ok, reason = Rebirth.canRebirth(Rebirth.new(), 1)
	t.assertFalse(ok)
	t.assertEqual(reason, "LEVEL_TOO_LOW")
end)

t.test("rebirth is refused at the cap", function()
	local state = { count = Config.Rebirth.MaxRebirths }
	local ok, reason = Rebirth.canRebirth(state, 1e6)
	t.assertFalse(ok)
	t.assertEqual(reason, "MAX_REBIRTHS")
end)

t.test("performing a rebirth increments the count and resets progress", function()
	local outcome, err = Rebirth.perform(Rebirth.new(), Config.Rebirth.BaseLevelRequirement)
	t.assertNil(err)
	t.assertNotNil(outcome)
	t.assertEqual(outcome.state.count, 1)
	t.assertEqual(outcome.level, 1)
	t.assertEqual(outcome.xp, 0)
	t.assertEqual(outcome.coins, Config.Rebirth.StartingCoinsAfterRebirth)
end)

t.test("performing a rebirth without the level fails", function()
	local outcome, reason = Rebirth.perform(Rebirth.new(), 1)
	t.assertNil(outcome)
	t.assertEqual(reason, "LEVEL_TOO_LOW")
end)

t.test("multipliers start at 1 and grow", function()
	local coin0, damage0 = Rebirth.multipliers(0)
	t.assertEqual(coin0, 1)
	t.assertEqual(damage0, 1)

	local coin1, damage1 = Rebirth.multipliers(1)
	t.assertGreater(coin1, coin0)
	t.assertGreater(damage1, damage0)
end)

t.test("multipliers are clamped at the cap", function()
	local coinCap = Rebirth.multipliers(Config.Rebirth.MaxRebirths)
	local coinOver = Rebirth.multipliers(Config.Rebirth.MaxRebirths + 50)
	t.assertEqual(coinCap, coinOver)
end)

t.test("rebirth keeps upgrades unless configured otherwise", function()
	local outcome = Rebirth.perform(Rebirth.new(), 1e6)
	t.assertEqual(outcome.resetUpgrades, Config.Rebirth.ResetUpgrades)
end)

t.test("fromSnapshot clamps a corrupt count", function()
	t.assertEqual(Rebirth.fromSnapshot({ count = -5 }).count, 0)
	t.assertEqual(Rebirth.fromSnapshot({ count = 1e9 }).count, Config.Rebirth.MaxRebirths)
	t.assertEqual(Rebirth.fromSnapshot(nil).count, 0)
end)

--------------------------------------------------------------------------
t.suite("Zones")
--------------------------------------------------------------------------

t.test("the default zone exists and is first", function()
	t.assertNotNil(Zones.getDef(Zones.defaultZone()))
	t.assertEqual(Zones.list()[1].id, Zones.defaultZone())
end)

t.test("zone order is strictly ascending by requirement", function()
	local prev = 0
	for _, def in ipairs(Zones.list()) do
		t.assertGreater(def.levelRequirement, prev, def.id)
		prev = def.levelRequirement
	end
end)

t.test("zone rewards increase with difficulty", function()
	local prev = 0
	for _, def in ipairs(Zones.list()) do
		t.assertGreater(def.coinMultiplier, prev, def.id)
		prev = def.coinMultiplier
	end
end)

t.test("the first zone is unlocked at level 1", function()
	t.assertTrue(Zones.isUnlocked(Zones.defaultZone(), 1))
end)

t.test("a high zone is locked at low level", function()
	t.assertFalse(Zones.isUnlocked("Heaven", 1))
end)

t.test("a zone pass unlocks everything", function()
	for _, def in ipairs(Zones.list()) do
		t.assertTrue(Zones.isUnlocked(def.id, 1, true), def.id)
	end
end)

t.test("travel to a locked zone is denied", function()
	local zone, reason = Zones.resolveTravel("Void", 1)
	t.assertNil(zone)
	t.assertEqual(reason, "ZONE_LOCKED")
end)

t.test("travel to an unknown zone is denied", function()
	local zone, reason = Zones.resolveTravel("Atlantis", 100)
	t.assertNil(zone)
	t.assertEqual(reason, "UNKNOWN_ZONE")
end)

t.test("travel to an unlocked zone succeeds", function()
	local zone, reason = Zones.resolveTravel("Cavern", 10)
	t.assertEqual(zone, "Cavern")
	t.assertNil(reason)
end)

t.test("multipliers fall back to 1 for unknown zones", function()
	t.assertEqual(Zones.coinMultiplier("Nowhere"), 1)
	t.assertEqual(Zones.difficultyMultiplier("Nowhere"), 1)
end)

--------------------------------------------------------------------------
t.suite("Monetization")
--------------------------------------------------------------------------

t.test("every product has a positive price and description", function()
	for _, product in ipairs(Monetization.list()) do
		t.assertTrue(product.robux > 0, product.id)
		t.assertTrue(#product.description > 0, product.id)
	end
end)

t.test("every product carries the Roblox asset id it is sold under", function()
	-- A product without an assetId is advertised but cannot be prompted, and a
	-- receipt for it can never be resolved. Both leave a buyer unpaid.
	local seen = {}
	for _, product in ipairs(Monetization.list()) do
		t.assertTrue(type(product.assetId) == "number", product.id)
		t.assertFalse(seen[product.assetId] == true, product.id)
		seen[product.assetId] = true
	end
end)

t.test("the catalogue is pinned to the ids the products are really sold under", function()
        -- The ids below were read back from the live Creator Hub and the
        -- catalogue API. Editing one here or in Monetization.luau without
        -- updating the other silently breaks the money path: the client
        -- prompts for an id that is not this product, or the receipt resolves
        -- to nothing. A mismatch is a typo, not a design choice.
        local LIVE = {
                Vip = 2058971598,
                AutoHatch = 2058839555,
                FastWalk = 2058521556,
                ZonePass = 2059001519,
                DoubleCoins1h = 3723348935,
                LuckyBoost = 3723349634,
        }
        for id, assetId in pairs(LIVE) do
                local product = Monetization.get(id)
                t.assertTrue(product ~= nil, id .. " is missing from the catalogue")
                t.assertEqual(product.assetId, assetId, id .. " is sold under a different asset id")
        end
end)

t.test("a receipt resolves back to its product by asset id", function()
	-- ProcessReceipt hands us the numeric asset id, never the catalogue key.
	for _, product in ipairs(Monetization.list()) do
		local found = Monetization.forAsset(product.assetId)
		t.assertTrue(found ~= nil, product.id)
		t.assertEqual(found.id, product.id)
	end
end)

t.test("an unknown asset id resolves to nothing", function()
	t.assertNil(Monetization.forAsset(1))
	t.assertNil(Monetization.forAsset(nil))
end)

t.test("restoring ownership grants a gamepass the platform reports", function()
	local ent = Monetization.newEntitlements()
	local vip = Monetization.get("Vip")
	local next, changed = Monetization.restoreGamepasses(ent, { [vip.assetId] = true })
	t.assertTrue(changed)
	t.assertTrue(Monetization.owns(next, "Vip"))
	-- The input must not be mutated, or a failed reconcile would still stick.
	t.assertFalse(Monetization.owns(ent, "Vip"))
end)

t.test("restoring ownership changes nothing when the pass is not owned", function()
	local ent = Monetization.newEntitlements()
	local next, changed = Monetization.restoreGamepasses(ent, {})
	t.assertFalse(changed)
	t.assertFalse(Monetization.owns(next, "Vip"))
end)

t.test("a dev product is never restored from ownership", function()
	-- A dev product is consumable. Restoring it from ownership would pay it out
	-- on every single join, so it must be excluded.
	local ent = Monetization.newEntitlements()
	local boost = Monetization.get("DoubleCoins1h")
	local next = Monetization.restoreGamepasses(ent, { [boost.assetId] = true })
	t.assertFalse(Monetization.owns(next, "DoubleCoins1h"))
	local lucky = Monetization.get("LuckyBoost")
	local next2 = Monetization.restoreGamepasses(ent, { [lucky.assetId] = true })
	t.assertEqual(next2.luckyCharges, 0)
end)

t.test("restoring ownership keeps boosts and charges already held", function()
	local ent = Monetization.newEntitlements()
	local bought = Monetization.grant(ent, "DoubleCoins1h", 1000)
	local next = Monetization.restoreGamepasses(bought.entitlements, {})
	t.assertEqual(next.boosts["DoubleCoins1h"], 1000 + 3600)
	local lucky = Monetization.grant(next, "LuckyBoost", 1000)
	local after = Monetization.restoreGamepasses(lucky.entitlements, {})
	t.assertEqual(after.luckyCharges, 10)
end)

t.test("gamepasses are listed separately from dev products", function()
	for _, product in ipairs(Monetization.gamepasses()) do
		t.assertEqual(product.kind, "gamepass")
		t.assertFalse(product.repeatable)
	end
	t.assertTrue(#Monetization.gamepasses() >= 4)
end)

t.test("unknown products cannot be granted", function()
	local result, reason = Monetization.grant(Monetization.newEntitlements(), "FreeRobux", 0)
	t.assertNil(result)
	t.assertEqual(reason, "UNKNOWN_PRODUCT")
end)

t.test("granting a gamepass marks it owned", function()
	local result, err = Monetization.grant(Monetization.newEntitlements(), "Vip", 1000)
	t.assertNil(err)
	t.assertTrue(Monetization.owns(result.entitlements, "Vip"))
	t.assertEqual(result.effect, "GRANTED_PERMANENT")
end)

t.test("a gamepass cannot be granted twice", function()
	local first = Monetization.grant(Monetization.newEntitlements(), "Vip", 0)
	local second, reason = Monetization.grant(first.entitlements, "Vip", 0)
	t.assertNil(second)
	t.assertEqual(reason, "ALREADY_OWNED")
end)

t.test("granting does not mutate the input entitlements", function()
	local ent = Monetization.newEntitlements()
	Monetization.grant(ent, "Vip", 0)
	t.assertFalse(Monetization.owns(ent, "Vip"))
end)

t.test("VIP multiplies coins and XP", function()
	local ent = Monetization.newEntitlements()
	t.assertEqual(Monetization.coinMultiplier(ent, 0), 1)
	t.assertEqual(Monetization.xpMultiplier(ent), 1)

	local result = Monetization.grant(ent, "Vip", 0)
	t.assertNear(
		Monetization.coinMultiplier(result.entitlements, 0),
		Config.Monetization.VipCoinMultiplier,
		1e-9
	)
	t.assertNear(
		Monetization.xpMultiplier(result.entitlements),
		Config.Monetization.VipXpMultiplier,
		1e-9
	)
end)

t.test("the coin boost expires", function()
	local result = Monetization.grant(Monetization.newEntitlements(), "DoubleCoins1h", 1000)
	local ent = result.entitlements
	t.assertEqual(Monetization.coinMultiplier(ent, 1000), 2)
	t.assertEqual(Monetization.coinMultiplier(ent, 1000 + 3599), 2)
	t.assertEqual(Monetization.coinMultiplier(ent, 1000 + 3600), 1)
end)

t.test("buying the coin boost again extends it", function()
	local first = Monetization.grant(Monetization.newEntitlements(), "DoubleCoins1h", 1000)
	-- The first purchase expires at 1000 + 3600.
	t.assertEqual(first.entitlements.boosts["DoubleCoins1h"], 1000 + 3600)

	-- Buying again mid-boost stacks onto the remaining time rather than
	-- resetting it, so the player never loses paid time.
	local second = Monetization.grant(first.entitlements, "DoubleCoins1h", 1200)
	t.assertEqual(second.entitlements.boosts["DoubleCoins1h"], 1000 + 3600 + 3600)
end)

t.test("the coin boost stacks with VIP", function()
	local vip = Monetization.grant(Monetization.newEntitlements(), "Vip", 0)
	local both = Monetization.grant(vip.entitlements, "DoubleCoins1h", 0)
	t.assertNear(
		Monetization.coinMultiplier(both.entitlements, 0),
		Config.Monetization.VipCoinMultiplier * 2,
		1e-9
	)
end)

t.test("a lucky boost grants charges that are consumed one at a time", function()
	local result = Monetization.grant(Monetization.newEntitlements(), "LuckyBoost", 0)
	local ent = result.entitlements
	t.assertEqual(ent.luckyCharges, 10)

	local luck = Monetization.takeLuck(ent)
	t.assertEqual(luck, 2)
	t.assertEqual(ent.luckyCharges, 9)

	for _ = 1, 9 do
		Monetization.takeLuck(ent)
	end
	t.assertEqual(ent.luckyCharges, 0)
	t.assertEqual(Monetization.takeLuck(ent), 1)
end)

t.test("walk speed bonus only applies with the gamepass", function()
	local ent = Monetization.newEntitlements()
	t.assertEqual(Monetization.walkSpeedBonus(ent), 0)
	local result = Monetization.grant(ent, "FastWalk", 0)
	t.assertGreater(Monetization.walkSpeedBonus(result.entitlements), 0)
end)

t.test("zone pass and auto hatch flags follow ownership", function()
	local ent = Monetization.newEntitlements()
	t.assertFalse(Monetization.hasZonePass(ent))
	t.assertFalse(Monetization.hasAutoHatch(ent))

	local zoned = Monetization.grant(ent, "ZonePass", 0).entitlements
	t.assertTrue(Monetization.hasZonePass(zoned))
	t.assertFalse(Monetization.hasAutoHatch(zoned))
end)

t.test("snapshot round trip keeps entitlements and boosts", function()
	local vip = Monetization.grant(Monetization.newEntitlements(), "Vip", 0).entitlements
	local withBoost = Monetization.grant(vip, "LuckyBoost", 0).entitlements
	withBoost.boosts["DoubleCoins1h"] = 5000

	local restored = Monetization.fromSnapshot(withBoost)
	t.assertTrue(Monetization.owns(restored, "Vip"))
	t.assertEqual(restored.luckyCharges, 10)
	t.assertEqual(restored.boosts["DoubleCoins1h"], 5000)
end)

t.test("fromSnapshot ignores unknown products and bad values", function()
	local restored = Monetization.fromSnapshot({
		owned = { Vip = true, FreeRobux = true },
		boosts = { Nope = 999, DoubleCoins1h = -5 },
		luckyCharges = -3,
	})
	t.assertTrue(Monetization.owns(restored, "Vip"))
	t.assertFalse(Monetization.owns(restored, "FreeRobux"))
	t.assertNil(restored.boosts["Nope"])
	t.assertNil(restored.boosts["DoubleCoins1h"])
	t.assertEqual(restored.luckyCharges, 0)
end)

t.test("fromSnapshot tolerates garbage", function()
	t.assertEqual(#Monetization.list(), 6)
	t.assertFalse(Monetization.owns(Monetization.fromSnapshot(nil), "Vip"))
end)

--------------------------------------------------------------------------
t.suite("SaveSchema v3")
--------------------------------------------------------------------------

t.test("a new save carries every progression field", function()
	local save = SaveSchema.new()
	t.assertEqual(save.level, 1)
	t.assertEqual(save.xp, 0)
	t.assertEqual(save.rebirths, 0)
	t.assertEqual(save.zone, Zones.defaultZone())
	t.assertNotNil(save.pets)
	t.assertNotNil(save.entitlements)
end)

t.test("a new save validates", function()
	local ok, problems = SaveSchema.validate(SaveSchema.new())
	t.assertTrue(ok, table.concat(problems, ","))
end)

t.test("rejects an out-of-range level", function()
	local save = SaveSchema.new()
	save.level = Config.Leveling.MaxLevel + 1
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "INVALID_LEVEL")
end)

t.test("rejects negative XP", function()
	local save = SaveSchema.new()
	save.xp = -1
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "INVALID_XP")
end)

t.test("rejects an impossible rebirth count", function()
	local save = SaveSchema.new()
	save.rebirths = Config.Rebirth.MaxRebirths + 1
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "INVALID_REBIRTHS")
end)

t.test("rejects an unknown zone", function()
	local save = SaveSchema.new()
	save.zone = "Atlantis"
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "INVALID_ZONE")
end)

t.test("rejects a pet blob over capacity", function()
	local save = SaveSchema.new()
	local pets = {}
	for i = 1, Config.Pets.MaxInventory + 1 do
		table.insert(pets, { uid = i, petId = "Pup", level = 1 })
	end
	save.pets = { pets = pets, equipped = {}, nextUid = #pets + 1 }
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertContains(table.concat(problems, ","), "PET_INVENTORY_OVER_CAPACITY")
end)

t.test("migrating a v2 save fills progression with defaults", function()
	local legacy = {
		version = 2,
		coins = 900,
		upgrades = { Damage = 2 },
		inventory = {},
		stats = { kills = 9, wavesCleared = 3, deaths = 1 },
		updatedAt = 50,
	}
	local migrated = SaveSchema.migrate(legacy)
	t.assertNotNil(migrated)
	local data = migrated
	t.assertEqual(data.version, Config.Persistence.SchemaVersion)
	t.assertEqual(data.coins, 900)
	t.assertEqual(data.upgrades.Damage, 2)
	t.assertEqual(data.level, 1)
	t.assertEqual(data.rebirths, 0)
	t.assertEqual(data.zone, Zones.defaultZone())
	t.assertEqual(#data.pets.pets, 0)

	local ok, problems = SaveSchema.validate(data)
	t.assertTrue(ok, table.concat(problems, ","))
end)

t.test("migration clamps a corrupt level and rebirth count", function()
	local migrated = SaveSchema.migrate({
		version = 3,
		coins = 10,
		upgrades = {},
		inventory = {},
		stats = { kills = 0, wavesCleared = 0, deaths = 0 },
		level = 9999,
		rebirths = -4,
		zone = "Nowhere",
	})
	t.assertEqual(migrated.level, Config.Leveling.MaxLevel)
	t.assertEqual(migrated.rebirths, 0)
	t.assertEqual(migrated.zone, Zones.defaultZone())
end)

t.test("migration keeps a valid zone", function()
	local migrated = SaveSchema.migrate({
		version = 3,
		coins = 10,
		upgrades = {},
		inventory = {},
		stats = { kills = 0, wavesCleared = 0, deaths = 0 },
		level = 40,
		zone = "Volcano",
	})
	t.assertEqual(migrated.zone, "Volcano")
end)

t.test("serialize includes the progression fields", function()
	local save = SaveSchema.new()
	save.level = 7
	save.xp = 42
	save.rebirths = 2
	save.zone = "Cavern"
	local json = SaveSchema.serialize(save, 1234)
	t.assertContains(json, '"level":7')
	t.assertContains(json, '"xp":42')
	t.assertContains(json, '"rebirths":2')
	t.assertContains(json, '"zone":"Cavern"')
	t.assertContains(json, '"updatedAt":1234')
end)

--------------------------------------------------------------------------
t.suite("DailyRewards")
--------------------------------------------------------------------------

t.test("a fresh state has no streak and can claim immediately", function()
	local state = DailyRewards.new()
	t.assertEqual(state.streak, 0)
	t.assertEqual(state.lastClaimAt, 0)
	local ok, reason = DailyRewards.canClaim(state, 1000)
	t.assertTrue(ok)
	t.assertEqual(reason, "FIRST_CLAIM")
end)

t.test("the first claim starts the streak at day one", function()
	local state, reward, err = DailyRewards.claim(DailyRewards.new(), 1000)
	t.assertNil(err)
	t.assertNotNil(state)
	t.assertEqual(state.streak, 1)
	t.assertEqual(state.totalClaims, 1)
	t.assertEqual(reward.day, 1)
	t.assertEqual(reward.coins, Config.Daily.Rewards[1].coins)
end)

t.test("claiming twice in a row is refused", function()
	local state = select(1, DailyRewards.claim(DailyRewards.new(), 1000))
	local ok, reason = DailyRewards.canClaim(state, 1000 + 60)
	t.assertFalse(ok)
	t.assertEqual(reason, "TOO_SOON")
end)

t.test("the cooldown must pass before the next claim", function()
	local cfg = Config.Daily
	local state = select(1, DailyRewards.claim(DailyRewards.new(), 1000))
	local ok = DailyRewards.canClaim(state, 1000 + cfg.CooldownSeconds)
	t.assertTrue(ok)
end)

t.test("a claim inside the grace window advances the streak", function()
	local cfg = Config.Daily
	local state = select(1, DailyRewards.claim(DailyRewards.new(), 1000))
	local second = select(1, DailyRewards.claim(state, 1000 + cfg.CooldownSeconds + 60))
	t.assertEqual(second.streak, 2)
end)

t.test("missing the grace window resets the streak", function()
	local cfg = Config.Daily
	local state = select(1, DailyRewards.claim(DailyRewards.new(), 1000))
	local late = 1000 + cfg.StreakGraceSeconds + 1
	local second = select(1, DailyRewards.claim(state, late))
	t.assertEqual(second.streak, 1)
end)

t.test("a later cycle pays more than the first cycle", function()
	local cfg = Config.Daily
	local day1 = DailyRewards.rewardForDay(1)
	local day8 = DailyRewards.rewardForDay(cfg.CycleLength + 1)
	t.assertTrue(day8.coins > day1.coins, "day 8 must beat day 1")
end)

t.test("a full cycle of rewards is strictly increasing", function()
	local cfg = Config.Daily
	local prev = 0
	for day = 1, cfg.CycleLength do
		local reward = DailyRewards.rewardForDay(day)
		t.assertTrue(reward.coins > prev, "day " .. day .. " did not increase")
		prev = reward.coins
	end
end)

t.test("the streak is capped at MaxStreak", function()
	local cfg = Config.Daily
	local state = { streak = cfg.MaxStreak, lastClaimAt = 1000, totalClaims = 1 }
	local next = select(1, DailyRewards.claim(state, 1000 + cfg.CooldownSeconds + 10))
	t.assertEqual(next.streak, cfg.MaxStreak)
end)

t.test("timeUntilClaim counts down to zero", function()
	local cfg = Config.Daily
	local state = select(1, DailyRewards.claim(DailyRewards.new(), 1000))
	t.assertEqual(DailyRewards.timeUntilClaim(state, 1000), cfg.CooldownSeconds)
	t.assertEqual(DailyRewards.timeUntilClaim(state, 1000 + cfg.CooldownSeconds), 0)
end)

t.test("snapshot survives a round trip", function()
	local state = select(1, DailyRewards.claim(DailyRewards.new(), 1000))
	local restored = DailyRewards.fromSnapshot(DailyRewards.snapshot(state))
	t.assertEqual(restored.streak, state.streak)
	t.assertEqual(restored.lastClaimAt, state.lastClaimAt)
	t.assertEqual(restored.totalClaims, state.totalClaims)
end)

t.test("fromSnapshot tolerates garbage", function()
	local empty = DailyRewards.fromSnapshot(nil)
	t.assertEqual(empty.streak, 0)
	local junk = DailyRewards.fromSnapshot({ streak = "lots", lastClaimAt = {}, totalClaims = -9 })
	t.assertEqual(junk.streak, 0)
	t.assertEqual(junk.lastClaimAt, 0)
	t.assertEqual(junk.totalClaims, 0)
end)

t.test("fromSnapshot clamps an impossible streak", function()
	local state = DailyRewards.fromSnapshot({ streak = 99999, lastClaimAt = 1, totalClaims = 1 })
	t.assertEqual(state.streak, Config.Daily.MaxStreak)
end)

--------------------------------------------------------------------------
t.suite("Codes")
--------------------------------------------------------------------------

t.test("a known code is found regardless of case and spacing", function()
	t.assertNotNil(Codes.get("release"))
	t.assertNotNil(Codes.get("ReLeAsE"))
	t.assertNotNil(Codes.get(" RELEASE "))
end)

t.test("an unknown code is rejected", function()
	t.assertNil(Codes.get("NOPE"))
	local _, _, reason = Codes.redeem({}, "NOPE", 1000)
	t.assertEqual(reason, "UNKNOWN_CODE")
end)

t.test("redeeming a code grants it and records the use", function()
	local map, def, err = Codes.redeem({}, "RELEASE", 1000)
	t.assertNil(err)
	t.assertNotNil(def)
	t.assertEqual(def.code, "RELEASE")
	t.assertNotNil(map.RELEASE)
	t.assertEqual(map.RELEASE.at, 1000)
end)

t.test("the same code cannot be redeemed twice", function()
	local map = select(1, Codes.redeem({}, "RELEASE", 1000))
	local _, _, reason = Codes.redeem(map, "RELEASE", 2000)
	t.assertEqual(reason, "ALREADY_REDEEMED")
end)

t.test("case does not let a player redeem twice", function()
	local map = select(1, Codes.redeem({}, "RELEASE", 1000))
	local _, _, reason = Codes.redeem(map, "release", 2000)
	t.assertEqual(reason, "ALREADY_REDEEMED")
end)

t.test("an expired code is refused", function()
	local def = Codes.get("RELEASE")
	local savedExpiry = def.expiresAt
	def.expiresAt = 500
	local _, _, reason = Codes.redeem({}, "RELEASE", 1000)
	def.expiresAt = savedExpiry
	t.assertEqual(reason, "CODE_EXPIRED")
end)

t.test("every listed code is redeemable", function()
	local all = Codes.list()
	t.assertTrue(#all >= 5)
	for _, def in ipairs(all) do
		local map, got, err = Codes.redeem({}, def.code, 1000)
		t.assertNil(err, def.code .. " failed to redeem")
		t.assertNotNil(map)
		t.assertEqual(got.code, def.code)
	end
end)

t.test("hasRedeemed reports the truth", function()
	local map = select(1, Codes.redeem({}, "AXARENA", 1000))
	t.assertTrue(Codes.hasRedeemed(map, "AXARENA"))
	t.assertFalse(Codes.hasRedeemed(map, "TRENDING"))
end)

t.test("snapshot drops codes that no longer exist", function()
	local dirty = { RELEASE = { code = "RELEASE", at = 5 }, GONE = { code = "GONE", at = 9 } }
	local clean = Codes.snapshot(dirty)
	t.assertNotNil(clean.RELEASE)
	t.assertNil(clean.GONE)
end)

t.test("snapshot and fromSnapshot round trip", function()
	local map = select(1, Codes.redeem({}, "FARM2026", 1234))
	local restored = Codes.fromSnapshot(Codes.snapshot(map))
	t.assertEqual(restored.FARM2026.at, 1234)
end)

t.test("fromSnapshot tolerates garbage", function()
	t.assertEqual(next(Codes.fromSnapshot(nil)), nil)
	t.assertEqual(next(Codes.fromSnapshot("nope")), nil)
	t.assertEqual(next(Codes.fromSnapshot({ BAD = 5 })), nil)
end)

--------------------------------------------------------------------------
t.suite("SaveSchema v4: daily streak and redeemed codes")
--------------------------------------------------------------------------

t.test("a new save carries an empty streak and no redemptions", function()
	local save = SaveSchema.new()
	t.assertEqual(save.daily.streak, 0)
	t.assertEqual(save.daily.totalClaims, 0)
	t.assertEqual(next(save.redeemed), nil)
end)

t.test("a v3 save with no daily or redeemed migrates to defaults", function()
	local v3 = {
		version = 3,
		coins = 500,
		upgrades = { Damage = 3, Health = 2, Speed = 1, CritChance = 0 },
		inventory = {},
		stats = { kills = 10, wavesCleared = 2, deaths = 1 },
		level = 5,
		xp = 120,
		rebirths = 1,
		zone = "Cavern",
		updatedAt = 1000,
	}
	local data = SaveSchema.migrate(v3)
	t.assertNotNil(data)
	t.assertEqual(data.version, Config.Persistence.SchemaVersion)
	t.assertEqual(data.daily.streak, 0)
	t.assertEqual(next(data.redeemed), nil)
	-- The v3 fields must survive the v4 migration untouched.
	t.assertEqual(data.level, 5)
	t.assertEqual(data.rebirths, 1)
	t.assertEqual(data.zone, "Cavern")
end)

t.test("a daily streak above the cap is rejected by validation", function()
	local save = SaveSchema.new()
	save.daily.streak = Config.Daily.MaxStreak + 1
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertEqual(problems[1], "INVALID_DAILY_STREAK")
end)

t.test("a negative claim time is rejected by validation", function()
	local save = SaveSchema.new()
	save.daily.lastClaimAt = -5
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertEqual(problems[1], "INVALID_DAILY_CLAIM_TIME")
end)

t.test("a non-table daily block is rejected by validation", function()
	local save = SaveSchema.new()
	save.daily = "tomorrow"
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertEqual(problems[1], "INVALID_DAILY")
end)

t.test("a non-table redeemed map is rejected by validation", function()
	local save = SaveSchema.new()
	save.redeemed = 42
	local ok, problems = SaveSchema.validate(save)
	t.assertFalse(ok)
	t.assertEqual(problems[1], "INVALID_REDEEMED")
end)

t.test("serialization carries the daily streak and redeemed codes", function()
	local save = SaveSchema.new()
	save.daily = { streak = 3, lastClaimAt = 999, totalClaims = 3 }
	save.redeemed = { RELEASE = { code = "RELEASE", at = 555 } }
	local text = SaveSchema.serialize(save, 1234)
	t.assertNotNil(string.find(text, '"daily"', 1, true))
	t.assertNotNil(string.find(text, '"streak":3', 1, true))
	t.assertNotNil(string.find(text, '"redeemed"', 1, true))
	t.assertNotNil(string.find(text, '"RELEASE":555', 1, true))
end)

t.test("serialize carries the story spine", function()
        -- Quests are part of SaveData, so a serialize that drops them would lose a
        -- player's story on any JSON path while the table path kept it. The two
        -- paths disagreeing is exactly the kind of bug that ships.
        local save = SaveSchema.new()
        save.quests = { index = 4, progress = 2, done = { talkToElder = true, firstBlood = true } }
        local json = SaveSchema.serialize(save, 1234)
        t.assertContains(json, '"quests":')
        t.assertContains(json, '"index":4')
        t.assertContains(json, '"progress":2')
        t.assertContains(json, '"talkToElder":true')

        -- A fresh save must still emit a usable object rather than "nil".
        local fresh = SaveSchema.serialize(SaveSchema.new(), 1)
        t.assertContains(fresh, '"quests":{"index":1,"progress":0,"done":{}}')
end)

t.test("the migrated save is a valid v4 save", function()
	local v2 = {
		version = 2,
		coins = 100,
		upgrades = { Damage = 1, Health = 1, Speed = 0, CritChance = 0 },
		inventory = {},
		stats = { kills = 0, wavesCleared = 0, deaths = 0 },
		updatedAt = 50,
	}
	local data, problems = SaveSchema.load(v2)
	t.assertNotNil(data, problems and table.concat(problems, ","))
	t.assertEqual(data.version, Config.Persistence.SchemaVersion)
	t.assertEqual(data.daily.streak, 0)
end)

--------------------------------------------------------------------------
t.suite("Farm")
--------------------------------------------------------------------------

t.test("a new farm has the configured number of empty plots", function()
	local farm = Farm.new()
	t.assertEqual(#farm.plots, Config.Farm.PlotCount)
	t.assertEqual(Farm.plantedCount(farm), 0)
	t.assertEqual(Farm.readyCount(farm, 0), 0)
end)

t.test("planting fills a plot and starts a timer", function()
	local farm = Farm.new()
	local ok, reason = Farm.plant(farm, 1, "Wheat", 100)
	t.assertTrue(ok, reason)
	local plot = Farm.getPlot(farm, 1)
	t.assertNotNil(plot)
	t.assertEqual(plot.cropId, "Wheat")
	t.assertEqual(plot.readyAt, 100 + Config.Farm.Crops[1].growSeconds)
end)

t.test("a crop is not ready before its grow time", function()
	local farm = Farm.new()
	Farm.plant(farm, 1, "Wheat", 0)
	local grow = Config.Farm.Crops[1].growSeconds
	t.assertFalse(Farm.isReady(Farm.getPlot(farm, 1), grow - 1))
	t.assertTrue(Farm.isReady(Farm.getPlot(farm, 1), grow))
end)

t.test("harvesting early is refused and leaves the crop in place", function()
	local farm = Farm.new()
	Farm.plant(farm, 1, "Wheat", 0)
	local reward, reason = Farm.harvest(farm, 1, 0)
	t.assertNil(reward)
	t.assertEqual(reason, "NOT_READY")
	-- A mistap must not cost the player their crop.
	t.assertEqual(Farm.getPlot(farm, 1).cropId, "Wheat")
end)

t.test("harvesting a ripe crop pays out and clears the plot", function()
	local farm = Farm.new()
	Farm.plant(farm, 2, "Carrot", 0)
	local grow = Config.Farm.Crops[2].growSeconds
	local reward, reason = Farm.harvest(farm, 2, grow + 1)
	t.assertNotNil(reward, reason)
	t.assertEqual(reward.cropId, "Carrot")
	t.assertEqual(reward.coins, Config.Farm.Crops[2].coins)
	t.assertEqual(Farm.getPlot(farm, 2).cropId, nil)
	t.assertEqual(Farm.readyCount(farm, grow + 1), 0)
end)

t.test("an occupied plot refuses a second planting", function()
	local farm = Farm.new()
	Farm.plant(farm, 1, "Wheat", 0)
	local ok, reason = Farm.plant(farm, 1, "Star", 0)
	t.assertFalse(ok)
	t.assertEqual(reason, "PLOT_OCCUPIED")
end)

t.test("an unknown crop and a bad plot index are rejected", function()
	local farm = Farm.new()
	local ok, reason = Farm.plant(farm, 1, "Banana", 0)
	t.assertFalse(ok)
	t.assertEqual(reason, "UNKNOWN_CROP")
	ok, reason = Farm.plant(farm, 999, "Wheat", 0)
	t.assertFalse(ok)
	t.assertEqual(reason, "BAD_PLOT")
end)

t.test("the snapshot reports the countdown for each plot", function()
	local farm = Farm.new()
	Farm.plant(farm, 1, "Wheat", 0)
	local snap = Farm.snapshot(farm, 0)
	t.assertEqual(#snap, Config.Farm.PlotCount)
	t.assertEqual(snap[1].cropId, "Wheat")
	t.assertEqual(snap[1].secondsLeft, Config.Farm.Crops[1].growSeconds)
	t.assertFalse(snap[1].ready)
	t.assertEqual(snap[2].cropId, nil)
end)

t.test("crops are listed in config order", function()
	local list = Farm.list()
	t.assertEqual(#list, #Config.Farm.Crops)
	t.assertEqual(list[1].id, Config.Farm.Crops[1].id)
end)

--------------------------------------------------------------------------
t.suite("Axe")
--------------------------------------------------------------------------

t.test("a new axe has no charges", function()
	local axe = Axe.new()
	t.assertEqual(axe.charges, 0)
	t.assertFalse(Axe.isReady(axe))
end)

t.test("charges accumulate up to the cap", function()
	local axe = Axe.new()
	for _ = 1, Axe.maxCharges() + 3 do
		Axe.addCharges(axe, 1)
	end
	t.assertEqual(axe.charges, Axe.maxCharges())
end)

t.test("an empty swing does nothing", function()
	local axe = Axe.new()
	local charges, damage = Axe.swing(axe, 12)
	t.assertEqual(charges, 0)
	t.assertEqual(damage, 0)
end)

t.test("a swing spends every charge at once and hits harder", function()
	local axe = Axe.new()
	Axe.addCharges(axe, 3)
	local charges, damage = Axe.swing(axe, 10)
	t.assertEqual(charges, 3)
	t.assertEqual(damage, math.floor(10 * (1 + 3 * Config.Farm.AxeDamagePerCharge) + 0.5))
	-- The burst is the whole point, so the stack is emptied.
	t.assertEqual(axe.charges, 0)
end)

t.test("swing damage grows with charges", function()
	local one = Axe.swingDamage(1, 10)
	local five = Axe.swingDamage(5, 10)
	t.assertGreater(five, one)
	t.assertEqual(Axe.swingDamage(0, 10), 0)
end)

--------------------------------------------------------------------------
t.suite("Broadcast cadence")

-- The HUD snapshots used to be sent from the top level of the Heartbeat
-- connection, which meant once per frame. On a phone that is a flood of events
-- for a bar that moves a few times a second. The source-level guard lives in
-- scripts/check-hud-wiring.py; the cadence itself belongs here.

t.test("the HUD cadence is slower than the frame rate", function()
        t.assertTrue(Config.Tick.BroadcastInterval > 0)
        t.assertTrue(Config.Tick.BroadcastInterval >= 1 / 30)
        t.assertTrue(Config.Tick.BroadcastInterval <= 1 / 4)
        t.assertTrue(Config.Tick.BroadcastInterval > 1 / Config.Tick.Rate)
end)

t.test("the farm broadcast is no faster than the HUD", function()
        t.assertTrue(Config.Tick.FarmBroadcastInterval >= Config.Tick.BroadcastInterval)
end)

t.suite("Fields")
--------------------------------------------------------------------------

t.test("there are five fields, matching the five zones", function()
	t.assertEqual(#Fields.list(), 5)
	t.assertEqual(#Fields.list(), #Zones.list())
end)

t.test("every field lines up with a zone of the same id", function()
	for _, field in ipairs(Fields.list()) do
		local zone = Zones.getDef(field.id)
		t.assertNotNil(zone, field.id)
		t.assertEqual(field.name, zone.name)
		t.assertEqual(field.levelRequirement, zone.levelRequirement)
		t.assertEqual(field.coinMultiplier, zone.coinMultiplier)
	end
end)

t.test("fields are ordered by requirement and pay more as they go", function()
	local previousRequirement = 0
	local previousCoins = 0
	for _, field in ipairs(Fields.list()) do
		t.assertGreater(field.levelRequirement, previousRequirement - 1, field.id)
		t.assertGreater(field.coinMultiplier, previousCoins - 1, field.id)
		previousRequirement = field.levelRequirement
		previousCoins = field.coinMultiplier
	end
end)

t.test("the town is safe and sits at the origin", function()
	local town = Fields.town()
	t.assertTrue(town.safe)
	t.assertEqual(town.position.x, 0)
	t.assertEqual(town.position.z, 0)
	t.assertTrue(Fields.isTown("Town"))
	t.assertNil(Fields.getDef("Town"))
end)

t.test("no field sits on top of the town or another field", function()
	local seen = {}
	for _, field in ipairs(Fields.list()) do
		local key = string.format("%d:%d", field.position.x, field.position.z)
		t.assertNil(seen[key], "two fields share a position: " .. field.id)
		seen[key] = field.id
		-- The ring radius must clear the town radius plus the field arena.
		local distance = math.sqrt(field.position.x ^ 2 + field.position.z ^ 2)
		t.assertGreater(distance, Config.Town.Radius + Config.Fields.ArenaRadius)
	end
end)

t.test("entering the town is always allowed", function()
	local ok = Fields.canEnter("Town", 1)
	t.assertTrue(ok)
end)

t.test("a locked field is refused and names the reason", function()
	local ok, reason = Fields.canEnter("Void", 1)
	t.assertFalse(ok)
	t.assertEqual(reason, "FIELD_LOCKED")
end)

t.test("an unknown field is refused", function()
	local ok, reason = Fields.canEnter("Atlantis", 99)
	t.assertFalse(ok)
	t.assertEqual(reason, "UNKNOWN_FIELD")
end)

t.test("a zone pass opens every field", function()
	for _, field in ipairs(Fields.list()) do
		local ok = Fields.canEnter(field.id, 1, true)
		t.assertTrue(ok, field.id)
	end
end)

t.test("the next locked field is the first one out of reach", function()
	local next = Fields.nextLocked(1)
	t.assertNotNil(next)
	t.assertEqual(next.id, "Cavern")
	t.assertNil(Fields.nextLocked(999, true))
end)

t.test("monsters spawn inside the field and never on the arrival point", function()
	local arrival = Fields.arrivalOf("Meadow")
	for index = 1, 10 do
		local point = Fields.spawnPoint("Meadow", index, 10)
		local centre = Fields.positionOf("Meadow")
		local dx = point.x - centre.x
		local dz = point.z - centre.z
		local radius = math.sqrt(dx * dx + dz * dz)
		t.assertLess(radius, Config.Fields.SpawnRadius + 1, "spawn outside the field")
		local ax = point.x - arrival.x
		local az = point.z - arrival.z
		t.assertGreater(math.sqrt(ax * ax + az * az), 10, "spawn on the arrival point")
	end
end)

t.test("the field snapshot reports locks against the level", function()
	local snap = Fields.snapshot(1)
	t.assertEqual(#snap, 5)
	t.assertTrue(snap[1].unlocked)
	t.assertFalse(snap[5].unlocked)
end)

--------------------------------------------------------------------------
t.suite("Enemies")
--------------------------------------------------------------------------

t.test("every field has a roster and a boss", function()
	for _, field in ipairs(Fields.list()) do
		t.assertGreater(#Enemies.roster(field.id), 0, field.id)
		t.assertTrue(Enemies.boss(field.id).boss, field.id)
	end
end)

t.test("rosters are distinct between fields", function()
	local meadow = Enemies.roster("Meadow")
	local cavern = Enemies.roster("Cavern")
	t.assertNotEqual(meadow[1].id, cavern[1].id)
end)

t.test("a boss wave is every fifth wave", function()
	t.assertFalse(Enemies.isBossWave(1))
	t.assertFalse(Enemies.isBossWave(4))
	t.assertTrue(Enemies.isBossWave(5))
	t.assertTrue(Enemies.isBossWave(10))
end)

t.test("a boss wave opens with the field boss", function()
	local rng = Random.new(11)
	local picked = Enemies.pick("Cavern", 5, rng, true)
	t.assertTrue(picked.boss)
	t.assertEqual(picked.id, Enemies.boss("Cavern").id)
end)

t.test("a normal wave never opens with a boss", function()
	local rng = Random.new(3)
	for _ = 1, 20 do
		local picked = Enemies.pick("Meadow", 3, rng, true)
		t.assertFalse(picked.boss)
	end
end)

t.test("picked monsters always come from the field roster", function()
	local rng = Random.new(5)
	local ids = {}
	for _, archetype in ipairs(Enemies.roster("Volcano")) do
		ids[archetype.id] = true
	end
	for _ = 1, 30 do
		local picked = Enemies.pick("Volcano", 2, rng, false)
		t.assertTrue(ids[picked.id], picked.id)
	end
end)

t.test("scaling applies the archetype and the field difficulty", function()
	local plan = { enemyHealth = 100, enemyDamage = 10, rewardPerKill = 20 }
	local slime = Enemies.getDef("Slime")
	local scaled = Enemies.scale(slime, plan, 2)
	t.assertEqual(scaled.health, math.floor(100 * slime.healthMul * 2 + 0.5))
	t.assertEqual(scaled.damage, math.floor(10 * slime.damageMul * 2 + 0.5))
	t.assertEqual(scaled.name, "Slime")
	t.assertFalse(scaled.boss)
end)

t.test("a boss is worth far more than a normal monster", function()
	local plan = { enemyHealth = 100, enemyDamage = 10, rewardPerKill = 20 }
	local normal = Enemies.scale(Enemies.getDef("Slime"), plan, 1)
	local boss = Enemies.scale(Enemies.boss("Meadow"), plan, 1)
	t.assertGreater(boss.health, normal.health)
	t.assertGreater(boss.reward, normal.reward)
	t.assertGreater(boss.sizeMul, normal.sizeMul)
	t.assertTrue(boss.boss)
end)

t.test("scaled stats never round down to zero", function()
	local plan = { enemyHealth = 1, enemyDamage = 1, rewardPerKill = 1 }
	local scaled = Enemies.scale(Enemies.getDef("Hornet"), plan, 1)
	t.assertGreater(scaled.health, 0)
	t.assertGreater(scaled.damage, 0)
	t.assertGreater(scaled.reward, 0)
end)

--------------------------------------------------------------------------
t.suite("Streak")
--------------------------------------------------------------------------

t.test("the streak bonus is capped", function()
	t.assertGreater(Config.Streak.MaxBonus, 0)
	local capped = math.min(Config.Streak.MaxBonus, 1000 * Config.Streak.BonusPerKill)
	t.assertEqual(capped, Config.Streak.MaxBonus)
end)

t.test("a kill inside the window extends the streak", function()
	-- Mirrors the server rule in rewardKill: a kill inside the window extends
	-- the streak, a kill after a pause restarts it at one.
	local function nextStreak(current, secondsSinceLast)
		if secondsSinceLast <= Config.Streak.WindowSeconds then
			return current + 1
		end
		return 1
	end
	t.assertEqual(nextStreak(7, 1), 8)
	t.assertEqual(nextStreak(7, Config.Streak.WindowSeconds + 1), 1)
end)

--------------------------------------------------------------------------
t.suite("WaveDirector travel")
--------------------------------------------------------------------------

t.test("skipIntermission starts the wave immediately", function()
	local director = WaveDirector.new(Random.new(11))
	t.assertEqual(director:snapshot().phase, "INTERMISSION")
	local plan = director:skipIntermission()
	t.assertNotNil(plan)
	t.assertEqual(director:snapshot().wave, 1)
	t.assertEqual(director:snapshot().phase, "ACTIVE")
end)

t.test("skipIntermission does nothing during a fight", function()
	local director = WaveDirector.new(Random.new(12))
	director:skipIntermission()
	t.assertNil(director:skipIntermission())
	t.assertEqual(director:snapshot().wave, 1)
end)

t.test("two directors keep independent waves", function()
	-- One director per field is the whole point: the Volcano must not be
	-- dragged to the Meadow wave just because both are running.
	local meadow = WaveDirector.new(Random.new(21))
	local volcano = WaveDirector.new(Random.new(22))
	meadow:skipIntermission()
	volcano:skipIntermission()
	t.assertEqual(meadow:snapshot().wave, 1)
	t.assertEqual(volcano:snapshot().wave, 1)
end)

t.test("ticking one field never advances another", function()
	-- This is what a single shared director could never do. Ticking the
	-- Meadow hard must leave the Volcano exactly where it was.
	local meadow = WaveDirector.new(Random.new(31))
	local volcano = WaveDirector.new(Random.new(32))
	meadow:skipIntermission()
	for _ = 1, 20 do
		meadow:update(0.1)
	end
	t.assertEqual(meadow:snapshot().wave, 1)
	t.assertEqual(volcano:snapshot().wave, 0)
	t.assertEqual(volcano:snapshot().phase, "INTERMISSION")
	t.assertEqual(volcano:snapshot().elapsed, 0)
end)

--------------------------------------------------------------------------
t.suite("Thai text")
--------------------------------------------------------------------------

t.test("every field and the town has a Thai name", function()
        -- The travel menu and the arrival signs both go through placeName, so a
        -- missing entry would show the English id to a Thai player.
        t.assertEqual(Text.placeName("Town"), Text.get("PronteraTown"))
        for _, field in ipairs(Fields.list()) do
                local name = Text.placeName(field.id)
                t.assertNotEqual(name, field.id, field.id .. " has no Thai name")
                t.assertTrue(#name > 0, field.id .. " has an empty Thai name")
        end
end)

t.test("every field has a Thai tagline", function()
        for _, field in ipairs(Fields.list()) do
                local line = Text.tagline(field.id)
                t.assertNotEqual(line, "", field.id .. " has no Thai tagline")
        end
end)

t.test("every crop has a Thai name", function()
        for _, crop in ipairs(Farm.list()) do
                t.assertNotEqual(Text.cropName(crop.id), crop.id, crop.id .. " has no Thai name")
        end
end)

t.test("every monster archetype has a Thai name", function()
        -- The kill flash and the boss bar send the English display name, so the
        -- lookup is keyed by name rather than id.
        for _, field in ipairs(Fields.list()) do
                for _, archetype in ipairs(Enemies.roster(field.id)) do
                        local name = Text.enemyName(archetype.name)
                        t.assertNotEqual(name, archetype.name, archetype.name .. " has no Thai name")
                end
                local boss = Enemies.boss(field.id)
                t.assertNotEqual(Text.enemyName(boss.name), boss.name, boss.name .. " has no Thai name")
        end
end)

t.test("the buttons and panels all have text", function()
        local keys = {
                "coins", "level", "health", "field", "zone", "rebirth", "combo", "wave", "boss", "max",
                "rewards", "dailyReward", "dailyClaim", "dailyWait", "redeemCode", "enterCode",
                "codePlaceholder", "redeem", "cancel", "axe", "axeEmpty", "farm", "farmReady", "map",
                "chooseField", "townPickField", "waveNext", "waveFighting", "bossDown",
                "town", "here", "locked", "returnToTown", "plot", "ready",
                "rebirthDone", "returnedToTown", "entered", "dailyGain", "codeGain",
                "harvestGain", "purchaseApplied",
                "shop", "buy", "owned", "shopLoading", "shopEmpty", "shopFailed",
                "notConfigured", "shopUnavailable",
        }
        local missing = Text.missingKeys(keys)
        t.assertEqual(#missing, 0, "missing translations: " .. table.concat(missing, ", "))
end)

t.test("a format line keeps its placeholders", function()
        -- A translation that drops %d would print a literal or error at runtime.
        t.assertContains(Text.get("dailyClaim", 3), "3")
        t.assertContains(Text.get("dailyWait", 2, 5), "2")
        t.assertContains(Text.get("dailyWait", 2, 5), "5")
        t.assertContains(Text.get("waveNext", "ทุ่งหญ้าอรุณ", 4, 30), "4")
        t.assertContains(Text.get("waveFighting", "ถ้ำคริสตัล", 2, 7), "7")
        t.assertContains(Text.get("farmReady", 4), "4")
        t.assertContains(Text.get("plot", 6), "6")
        t.assertContains(Text.get("entered", "ถ้ำคริสตัล"), "ถ้ำคริสตัล")
end)

t.test("an unknown key falls back to the key, not to blank", function()
        -- A blank label is invisible in a screenshot; the key is not.
        t.assertEqual(Text.get("NoSuchKey"), "NoSuchKey")
        t.assertEqual(Text.placeName("NoSuchField"), "NoSuchField")
        t.assertEqual(Text.enemyName("NoSuchMonster"), "NoSuchMonster")
end)

t.test("the Thai lines are actually Thai", function()
        -- Guards against a copy-paste that leaves the English in place. Thai
        -- lives in U+0E00..U+0E7F, so at least one character must land there.
        local function hasThai(value: string): boolean
                for _, code in utf8.codes(value) do
                        if code >= 0x0E00 and code <= 0x0E7F then
                                return true
                        end
                end
                return false
        end

        local keys = {
                "coins", "level", "health", "field", "zone", "rebirth", "wave", "rewards", "axe",
                "farm", "map", "chooseField", "townPickField", "redeem", "cancel", "returnToTown",
                "here", "PronteraTown", "Meadow", "Cavern", "Volcano", "Void", "Heaven",
                "Wheat", "Carrot", "Star",
                "shop", "buy", "owned", "shopLoading", "shopEmpty", "shopFailed",
                "notConfigured", "shopUnavailable",
        }
        for _, key in ipairs(keys) do
                t.assertTrue(hasThai(Text.get(key)), key .. " is not Thai")
        end
end)

--------------------------------------------------------------------------
t.suite("Attributes")
--------------------------------------------------------------------------

t.test("a new sheet starts at the configured minimum", function()
	local sheet = Attributes.new()
	for _, name in ipairs(Attributes.NAMES) do
		t.assertEqual(sheet[name], Config.Attributes.BaseValue, name)
	end
end)

t.test("stat points come from the level", function()
	-- The bank is derived, not stored, so a stale save cannot hold spare points.
	t.assertEqual(Attributes.available(Attributes.new(), 1), Attributes.pointsForLevel(1))
	t.assertGreater(Attributes.available(Attributes.new(), 20), Attributes.pointsForLevel(1))
end)

t.test("raising a stat spends points and raises the stat", function()
	local sheet = Attributes.new()
	local bank = Attributes.pointsForLevel(30)
	local ok, next, left, reason = Attributes.raise(sheet, bank, "STR", 1)
	t.assertTrue(ok, reason)
	t.assertEqual(next.STR, Config.Attributes.BaseValue + 1)
	t.assertLess(left, bank, "points must be spent")
	t.assertEqual(sheet.STR, Config.Attributes.BaseValue, "the input sheet must not mutate")
end)

t.test("a raise beyond the bank is refused", function()
	local ok, _, _, reason = Attributes.raise(Attributes.new(), 0, "STR", 1)
	t.assertFalse(ok)
	t.assertEqual(reason, "NOT_ENOUGH_POINTS")
end)

t.test("an unknown stat is refused", function()
	local ok, _, _, reason = Attributes.raise(Attributes.new(), 99, "MANA", 1)
	t.assertFalse(ok)
	t.assertEqual(reason, "UNKNOWN_STAT")
end)

t.test("every raisable stat appears in NAMES", function()
	for stat, raisable in pairs(Config.Attributes.Raisable) do
		if raisable then
			local found = false
			for _, name in ipairs(Attributes.NAMES) do
				if name == stat then
					found = true
				end
			end
			t.assertTrue(found, stat .. " is raisable but not listed in NAMES")
		end
	end
end)

t.test("a point costs more as the stat climbs", function()
	t.assertLess(Attributes.pointCost(1), Attributes.pointCost(50))
	t.assertEqual(Attributes.pointCost(Config.Attributes.MaxValue), math.huge)
end)

t.test("a raise never passes the maximum", function()
	local sheet = Attributes.copy(Attributes.new())
	sheet.STR = Config.Attributes.MaxValue
	local ok, _, _, reason = Attributes.raise(sheet, 10 ^ 6, "STR", 1)
	t.assertFalse(ok)
	t.assertEqual(reason, "MAX_STAT")
end)

t.test("derived values grow with the stats that feed them", function()
	local low = Attributes.derive(Attributes.new(), 1)

	local strong = Attributes.copy(Attributes.new())
	strong.STR = 40
	t.assertGreater(Attributes.derive(strong, 1).attack, low.attack)

	local tough = Attributes.copy(Attributes.new())
	tough.VIT = 40
	t.assertGreater(Attributes.derive(tough, 1).maxHealth, low.maxHealth)

	local smart = Attributes.copy(Attributes.new())
	smart.INT = 40
	t.assertGreater(Attributes.derive(smart, 1).maxSp, low.maxSp)

	local quick = Attributes.copy(Attributes.new())
	quick.AGI = 40
	t.assertLess(Attributes.derive(quick, 1).attackInterval, low.attackInterval)
end)

t.test("a level-up raises health even with no points spent", function()
	local sheet = Attributes.new()
	t.assertGreater(Attributes.derive(sheet, 30).maxHealth, Attributes.derive(sheet, 1).maxHealth)
end)

t.test("derived values never round to zero", function()
	local derived = Attributes.derive(Attributes.new(), 1)
	t.assertGreater(derived.maxHealth, 0)
	t.assertGreater(derived.attack, 0)
	t.assertGreater(derived.hit, 0)
	t.assertGreater(derived.flee, 0)
	t.assertGreater(derived.attackInterval, 0)
end)

t.test("attack speed has a floor", function()
	local sheet = Attributes.copy(Attributes.new())
	sheet.AGI = Config.Attributes.MaxValue
	sheet.DEX = Config.Attributes.MaxValue
	t.assertNear(Attributes.derive(sheet, 1).attackInterval, Config.Attributes.MinAttackInterval, 0.0001)
end)

t.test("hit chance stays a probability", function()
	for hit = 1, 400, 37 do
		for flee = 1, 400, 53 do
			local chance = Attributes.hitChance(hit, flee)
			t.assertTrue(chance >= 0 and chance <= 1, string.format("%d vs %d gave %f", hit, flee, chance))
		end
	end
end)

t.test("a more accurate attacker lands more often", function()
	t.assertGreater(Attributes.hitChance(200, 50), Attributes.hitChance(20, 50))
end)

t.test("defense reduces damage but never below one", function()
	t.assertLess(Attributes.mitigate(100, 50), 100)
	t.assertEqual(Attributes.mitigate(10, 100000), 1)
end)

t.test("bonuses stack through one path", function()
	local base = Attributes.new()
	local withClass = Attributes.applyBonus(base, { STR = 4 })
	local withBoth = Attributes.applyBonus(withClass, { STR = 2, VIT = 3 })
	t.assertEqual(withBoth.STR, Config.Attributes.BaseValue + 6)
	t.assertEqual(withBoth.VIT, Config.Attributes.BaseValue + 3)
	t.assertEqual(base.STR, Config.Attributes.BaseValue, "the input sheet must not mutate")
end)

--------------------------------------------------------------------------
t.suite("Classes")
--------------------------------------------------------------------------

t.test("the starting class is a real class", function()
	t.assertNotNil(Classes.getDef(Classes.starting().id))
	t.assertEqual(Classes.starting().id, Config.Classes.StartingClass)
end)

t.test("the tree covers all five first jobs and their second jobs", function()
	local expected = {
		"Swordsman", "Archer", "Mage", "Thief", "Acolyte",
		"Knight", "Hunter", "Wizard", "Assassin", "Priest",
	}
	for _, id in ipairs(expected) do
		t.assertNotNil(Classes.getDef(id), id .. " is missing")
	end
end)

t.test("every class is reachable from the starting class", function()
	-- A class nobody can reach is content nobody can play.
	local seen = { [Config.Classes.StartingClass] = true }
	local changed = true
	while changed do
		changed = false
		for _, def in ipairs(Classes.list()) do
			if seen[def.id] then
				for _, next in ipairs(def.advancesTo) do
					if not seen[next] then
						seen[next] = true
						changed = true
					end
				end
			end
		end
	end
	for _, def in ipairs(Classes.list()) do
		t.assertTrue(seen[def.id], def.id .. " cannot be reached")
	end
end)

t.test("advancing needs both levels, not just one", function()
	local cfg = Config.Classes
	local ok = Classes.canAdvance("Novice", "Swordsman", cfg.FirstJobLevel, 1)
	t.assertFalse(ok)
	ok = Classes.canAdvance("Novice", "Swordsman", 1, cfg.FirstJobJobLevel)
	t.assertFalse(ok)
	ok = Classes.canAdvance("Novice", "Swordsman", cfg.FirstJobLevel, cfg.FirstJobJobLevel)
	t.assertTrue(ok)
end)

t.test("a second job needs a higher gate than a first job", function()
	local cfg = Config.Classes
	t.assertGreater(cfg.SecondJobLevel, cfg.FirstJobLevel)
	t.assertGreater(cfg.SecondJobJobLevel, cfg.FirstJobJobLevel)
end)

t.test("a class cannot be skipped", function()
	local ok, reason = Classes.canAdvance("Novice", "Knight", 99, 99)
	t.assertFalse(ok)
	t.assertEqual(reason, "NOT_A_BRANCH")
end)

t.test("advancing resets the job level", function()
	local next = Classes.advance("Knight")
	t.assertEqual(next.class, "Knight")
	t.assertEqual(next.jobLevel, 1)
	t.assertEqual(next.jobXp, 0)
end)

t.test("job XP accumulates and levels up", function()
	local jobLevel, jobXp, levels = Classes.addJobXp(1, 0, 5)
	t.assertEqual(jobLevel, 1)
	t.assertEqual(jobXp, 5)
	t.assertEqual(levels, 0)

	local need = Classes.jobXpForNext(1)
	jobLevel, jobXp, levels = Classes.addJobXp(1, 0, need)
	t.assertEqual(jobLevel, 2)
	t.assertEqual(levels, 1)
	t.assertEqual(jobXp, 0)
end)

t.test("one big award can cross several job levels", function()
	local total = 0
	for level = 1, 5 do
		total += Classes.jobXpForNext(level)
	end
	local jobLevel, _, levels = Classes.addJobXp(1, 0, total)
	t.assertEqual(jobLevel, 6)
	t.assertEqual(levels, 5)
end)

t.test("job level is capped", function()
	local jobLevel, _, _ = Classes.addJobXp(Config.Classes.MaxJobLevel, 0, 10 ^ 9)
	t.assertEqual(jobLevel, Config.Classes.MaxJobLevel)
end)

t.test("skill points grow with the job level", function()
	t.assertGreater(Classes.skillPointsForJobLevel(20), Classes.skillPointsForJobLevel(1))
end)

t.test("every class but the starting one has a bonus", function()
	for _, def in ipairs(Classes.list()) do
		if def.id ~= Config.Classes.StartingClass then
			local total = 0
			for _, value in pairs(def.bonus) do
				total += value
			end
			t.assertGreater(total, 0, def.id .. " has no class bonus")
		end
	end
end)

t.test("class bonuses only use real attribute names", function()
	for _, def in ipairs(Classes.list()) do
		for stat, _ in pairs(def.bonus) do
			local found = false
			for _, name in ipairs(Attributes.NAMES) do
				if name == stat then
					found = true
				end
			end
			t.assertTrue(found, def.id .. " bonuses unknown stat " .. stat)
		end
	end
end)

t.test("a class bonus reaches the sheet through the shared path", function()
	local base = Attributes.new()
	local bonus = Classes.bonus("Swordsman")
	local effective = Attributes.applyBonus(base, bonus)
	t.assertGreater(effective.STR, base.STR)
	t.assertGreater(effective.VIT, base.VIT)
end)

t.test("the branch shows the whole path, not just the next step", function()
	local branch = Classes.branch("Novice")
	t.assertGreater(#branch, 5, "the Novice branch should list every reachable class")
end)

--------------------------------------------------------------------------
t.suite("Skills")
--------------------------------------------------------------------------

t.test("every skill id resolves to a definition", function()
	for _, def in ipairs(Skills.list()) do
		t.assertEqual(Skills.getDef(def.id).id, def.id)
	end
end)

t.test("a skill can be learned and then levelled", function()
	local learned = {}
	local ok, next, left, reason = Skills.learn(learned, "Novice", "FirstAid", 3)
	t.assertTrue(ok, reason)
	t.assertEqual(next.FirstAid, 1)
	t.assertEqual(left, 2)

	ok, next, left = Skills.learn(next, "Novice", "FirstAid", left)
	t.assertTrue(ok)
	t.assertEqual(next.FirstAid, 2)
end)

t.test("learning without points is refused", function()
	local ok, _, _, reason = Skills.learn({}, "Novice", "FirstAid", 0)
	t.assertFalse(ok)
	t.assertEqual(reason, "NO_SKILL_POINTS")
end)

t.test("a skill from another class is refused", function()
	local ok, _, _, reason = Skills.learn({}, "Novice", "SonicBlow", 50)
	t.assertFalse(ok)
	t.assertEqual(reason, "WRONG_CLASS")
end)

t.test("a universal Novice skill is learnable by any class", function()
	local ok, _, _, reason = Skills.learn({}, "Knight", "FirstAid", 50)
	t.assertTrue(ok, reason)
end)

t.test("a skill cannot pass its max level", function()
	local def = Skills.getDef("FirstAid")
	local learned = { FirstAid = def.maxLevel }
	local ok, _, _, reason = Skills.learn(learned, "Novice", "FirstAid", 50)
	t.assertFalse(ok)
	t.assertEqual(reason, "MAX_LEVEL")
end)

t.test("a prerequisite must be learned first", function()
	-- Find a skill that gates another, then try to skip the gate.
	local gated, prerequisite = nil, nil
	for _, def in ipairs(Skills.list()) do
		if def.requires then
			gated, prerequisite = def, def.requires
			break
		end
	end
	t.assertNotNil(gated, "no gated skill found to test")

	local ok, _, _, reason = Skills.learn({}, gated.class, gated.id, 50)
	t.assertFalse(ok)
	t.assertEqual(reason, "PREREQUISITE")

	-- With the gate learned past its required level it passes.
	local learned = { [prerequisite] = gated.requiresLevel }
	local ok2, _, _, reason2 = Skills.learn(learned, gated.class, gated.id, 50)
	t.assertTrue(ok2, reason2)
end)

t.test("every class has at least one skill", function()
	for _, def in ipairs(Classes.list()) do
		t.assertGreater(#Skills.forClass(def.id), 0, def.id .. " has no skills")
	end
end)

t.test("every prerequisite names a real skill", function()
	for _, def in ipairs(Skills.list()) do
		if def.requires then
			t.assertNotNil(Skills.getDef(def.requires), def.id .. " requires unknown skill " .. def.requires)
		end
	end
end)

t.test("a passive has no SP cost and nothing to cast", function()
	local passives = 0
	for _, def in ipairs(Skills.list()) do
		if def.kind == "passive" then
			passives += 1
			t.assertEqual(Skills.spCost(def, 1), 0)
		end
	end
	t.assertGreater(passives, 0, "no passive skills exist")
end)

t.test("an attack skill scales with its stat", function()
	local def = Skills.getDef("FireBolt")
	local weak = Skills.resolve(def, 1, { magicAttack = 10, attack = 10, maxHealth = 100 })
	local strong = Skills.resolve(def, 1, { magicAttack = 200, attack = 200, maxHealth = 100 })
	t.assertGreater(strong.damage, weak.damage)
end)

t.test("a higher skill level hits harder and costs more", function()
	local def = Skills.getDef("FireBolt")
	local sheet = { magicAttack = 100, attack = 100, maxHealth = 100 }
	local low = Skills.resolve(def, 1, sheet)
	local high = Skills.resolve(def, def.maxLevel, sheet)
	t.assertGreater(high.damage, low.damage)
	t.assertGreater(high.spCost, low.spCost)
end)

t.test("a heal skill scales with max health", function()
	local def = Skills.getDef("Heal")
	local small = Skills.resolve(def, 1, { magicAttack = 10, attack = 10, maxHealth = 100 })
	local big = Skills.resolve(def, 1, { magicAttack = 10, attack = 10, maxHealth = 10000 })
	t.assertGreater(big.heal, small.heal)
end)

t.test("a buff raises attack and defense", function()
	local def = Skills.getDef("Blessing")
	local cast = Skills.resolve(def, 1, { magicAttack = 10, attack = 10, maxHealth = 100 })
	t.assertGreater(cast.buff.attackMul, 1)
	t.assertGreater(cast.buff.defenseMul, 1)
	t.assertGreater(cast.duration, 0)
end)

t.test("cooldown is positive and falls with level", function()
	local def = Skills.getDef("FireBolt")
	t.assertGreater(Skills.cooldown(def, 1), 0)
	t.assertLess(Skills.cooldown(def, def.maxLevel), Skills.cooldown(def, 1))
end)

t.test("a passive adds its bonus when learned", function()
	t.assertEqual(Skills.passiveBonus({}).damageMul, 1)

	local owl = Skills.getDef("OwlEyes")
	local bonus = Skills.passiveBonus({ [owl.id] = owl.maxLevel })
	t.assertGreater(bonus.damageMul, 1, "Owl's Eye should raise damage")
	t.assertGreater(bonus.hitBonus, 0, "Owl's Eye should raise accuracy")
end)

t.test("the hotbar only holds learned, non-passive skills", function()
	local learned = { FirstAid = 2, Bash = 1, Endure = 3 }
	local hotbar = Skills.hotbar(learned, "Swordsman", { attack = 10, magicAttack = 10, maxHealth = 100 })
	t.assertEqual(#hotbar, 3, "all three learned, castable skills should be on the hotbar")
	for _, entry in ipairs(hotbar) do
		t.assertNotNil(learned[entry.id], entry.id .. " is not learned")
		t.assertNotEqual(Skills.getDef(entry.id).kind, "passive", entry.id .. " is passive")
		t.assertGreater(entry.level, 0)
	end
end)

t.test("the hotbar skips passives", function()
	local owl = Skills.getDef("OwlEyes")
	t.assertEqual(owl.kind, "passive")
	local hotbar = Skills.hotbar({ [owl.id] = 1 }, "Archer", { attack = 10, magicAttack = 10, maxHealth = 100 })
	t.assertEqual(#hotbar, 0, "a passive must not be castable")
end)

t.test("every skill has a Thai name", function()
	for _, def in ipairs(Skills.list()) do
		t.assertNotEqual(Text.skillName(def.id), def.id, def.id .. " has no Thai name")
	end
end)

--------------------------------------------------------------------------
t.suite("Items and equipment")
--------------------------------------------------------------------------

t.test("every item has a definition", function()
	for _, def in ipairs(Items.list()) do
		t.assertEqual(Items.getDef(def.id).id, def.id)
	end
end)

t.test("every droppable item has a Thai name", function()
	-- An item the player can only ever see in a drop or a bag needs a Thai name;
	-- the reference-only ones may pass through.
	for _, field in ipairs(Fields.list()) do
		for _, archetype in ipairs(Enemies.roster(field.id)) do
			for _, entry in ipairs(Items.dropsFor(archetype.id)) do
				t.assertNotEqual(Text.itemName(entry.itemId), entry.itemId, entry.itemId .. " has no Thai name")
			end
		end
	end
end)

t.test("equipment fits a real slot", function()
	local slots = {}
	for _, slot in ipairs(Items.slots()) do
		slots[slot] = true
	end
	for _, def in ipairs(Items.list()) do
		if def.kind == "equipment" then
			t.assertTrue(slots[def.slot], def.id .. " uses unknown slot " .. tostring(def.slot))
		end
	end
end)

t.test("every class can arm itself at level 1", function()
	-- A class with no usable weapon is unplayable, so there must be a weapon
	-- with no level requirement.
	local found = false
	for _, item in ipairs(Items.list()) do
		if item.kind == "equipment" and item.slot == "Weapon" and item.levelRequirement <= 1 then
			found = true
		end
	end
	t.assertTrue(found, "no level-1 weapon exists")
end)

t.test("an item above the level is refused", function()
	local gated = nil
	for _, def in ipairs(Items.list()) do
		if def.kind == "equipment" and def.levelRequirement > 1 then
			gated = def
			break
		end
	end
	t.assertNotNil(gated, "no gated equipment exists")
	local ok, reason = Items.canEquip(gated.id, 1, {})
	t.assertFalse(ok)
	t.assertEqual(reason, "LEVEL_TOO_LOW")
end)

t.test("a consumable cannot be worn", function()
	local ok, reason = Items.canEquip("RedPotion", 99, {})
	t.assertFalse(ok)
	t.assertEqual(reason, "NOT_EQUIPMENT")
end)

t.test("equipping fills the slot and unequipping clears it", function()
	local worn = Items.equipTo({}, "ShortSword")
	t.assertEqual(worn.Weapon, "ShortSword")
	worn = Items.unequipFrom(worn, "Weapon")
	t.assertNil(worn.Weapon)
end)

t.test("a two-handed weapon fills the shield slot too", function()
	local twoHanded = nil
	for _, def in ipairs(Items.list()) do
		if def.kind == "equipment" and def.twoHanded then
			twoHanded = def
			break
		end
	end
	t.assertNotNil(twoHanded, "no two-handed weapon exists")

	local worn = Items.equipTo({ Shield = "WoodenShield" }, twoHanded.id)
	t.assertEqual(worn.Weapon, twoHanded.id)
	t.assertEqual(worn.Shield, twoHanded.id, "a two-handed weapon occupies both slots")
end)

t.test("removing a two-handed weapon clears both slots", function()
	local twoHanded = nil
	for _, def in ipairs(Items.list()) do
		if def.kind == "equipment" and def.twoHanded then
			twoHanded = def
			break
		end
	end
	local worn = Items.equipTo({}, twoHanded.id)
	worn = Items.unequipFrom(worn, "Weapon")
	t.assertNil(worn.Weapon)
	t.assertNil(worn.Shield, "the ghost shield slot must go too")
end)

t.test("a shield is refused while a two-handed weapon is worn", function()
	local twoHanded = nil
	for _, def in ipairs(Items.list()) do
		if def.kind == "equipment" and def.twoHanded then
			twoHanded = def
			break
		end
	end
	local ok, reason = Items.canEquip("WoodenShield", 99, { Weapon = twoHanded.id })
	t.assertFalse(ok)
	t.assertEqual(reason, "WEAPON_IS_TWO_HANDED")
end)

t.test("equipment raises the sheet it feeds", function()
	local bare = Items.equipmentCombat({})
	local armed = Items.equipmentCombat({ Weapon = "Claymore" })
	t.assertGreater(armed.attack, bare.attack)

	local bonus = Items.equipmentBonus({ Body = "PlateArmor" })
	local total = 0
	for _, value in pairs(bonus) do
		total += value
	end
	t.assertGreater(total, 0, "PlateArmor gives no attribute bonus")
end)

t.test("every monster has a drop table of its own", function()
        -- A monster with no table still rolls the two generic potions, so it looks
        -- fine in every other check while dropping nothing that identifies it. Ten
        -- of sixteen monsters were in that state: you could farm the whole game and
        -- never see Chitin, Stone or a Celestial Feather come off the monster that
        -- is supposed to carry it. This guards the gap rather than the loot.
        local generic = 0
        for _, entry in ipairs(Items.dropsFor("NoSuchMonster")) do
                generic += 1
        end
        t.assertGreater(generic, 0, "the generic table is empty, so this test proves nothing")

        local bare: { string } = {}
        for _, field in ipairs(Fields.list()) do
                for _, archetype in ipairs(Enemies.roster(field.id)) do
                        if #Items.dropsFor(archetype.id) <= generic then
                                table.insert(bare, field.id .. ":" .. archetype.id)
                        end
                end
                local boss = Enemies.boss(field.id)
                if #Items.dropsFor(boss.id) <= generic then
                        table.insert(bare, field.id .. ":BOSS:" .. boss.id)
                end
        end
        t.assertEqual(#bare, 0, "monsters with only the generic drops: " .. table.concat(bare, ", "))
end)

t.test("a field's monsters drop that field's material", function()
        -- The material names the field: Chitin is what Volcano and Meadow beasts
        -- carry, Rift Shard is what the Void drops. If a monster in a field cannot
        -- produce the field's material, that material is unobtainable in practice.
        local materialFor: { [string]: string } = {
                Cavern = "Stone",
                Volcano = "Ember",
                Void = "RiftShard",
                Heaven = "CelestialFeather",
        }
        for field, material in pairs(materialFor) do
                local found = false
                for _, archetype in ipairs(Enemies.roster(field)) do
                        for _, entry in ipairs(Items.dropsFor(archetype.id)) do
                                if entry.itemId == material then
                                        found = true
                                end
                        end
                end
                t.assertTrue(found, field .. " monsters never drop " .. material)
        end
end)

t.test("every monster's drop table names real items", function()
	for _, field in ipairs(Fields.list()) do
		for _, archetype in ipairs(Enemies.roster(field.id)) do
			for _, entry in ipairs(Items.dropsFor(archetype.id)) do
				t.assertNotNil(Items.getDef(entry.itemId), archetype.id .. " drops unknown " .. entry.itemId)
				t.assertTrue(entry.chance > 0 and entry.chance <= 1, entry.itemId .. " has a bad chance")
			end
		end
		local boss = Enemies.boss(field.id)
		for _, entry in ipairs(Items.dropsFor(boss.id)) do
			t.assertNotNil(Items.getDef(entry.itemId), boss.id .. " drops unknown " .. entry.itemId)
		end
	end
end)

t.test("a roll only ever returns real items and sensible counts", function()
	local rng = Random.new(4242)
	local rolls = 0
	for _, field in ipairs(Fields.list()) do
		for _, archetype in ipairs(Enemies.roster(field.id)) do
			for _ = 1, 40 do
				for _, drop in ipairs(Items.rollDrops(archetype.id, rng, 1)) do
					rolls += 1
					t.assertNotNil(Items.getDef(drop.itemId), "rolled unknown " .. drop.itemId)
					t.assertGreater(drop.count, 0)
				end
			end
		end
	end
	t.assertGreater(rolls, 0, "no drop ever rolled in 40 attempts per monster")
end)

t.test("luck raises the drop rate without breaking it", function()
	-- Two runs with the same seed: the lucky run must collect at least as much,
	-- and must never roll an invalid item.
	local plainRng = Random.new(31337)
	local luckyRng = Random.new(31337)
	local plain, lucky = 0, 0
	for _, archetype in ipairs(Enemies.roster("Cavern")) do
		for _ = 1, 200 do
			local drops = Items.rollDrops(archetype.id, plainRng, 1)
			plain += #drops
			local luckyDrops = Items.rollDrops(archetype.id, luckyRng, 8)
			lucky += #luckyDrops
			for _, drop in ipairs(luckyDrops) do
				t.assertNotNil(Items.getDef(drop.itemId), "luck rolled unknown " .. drop.itemId)
				t.assertGreater(drop.count, 0)
			end
		end
	end
	t.assertGreater(lucky, plain, "luck made no difference")
end)

t.test("a multi-word monster keeps its own drop table", function()
	-- The drop tables are keyed by archetype id, but the display name of many
	-- monsters contains a space ("Rock Golem"). Keying loot off the name silently
	-- falls back to the generic potions, so this guards the keying.
	local rock = Enemies.getDef("RockGolem")
	t.assertNotNil(rock)
	t.assertContains(rock.name, " ", "this test needs a multi-word name")
	t.assertNotEqual(rock.name, rock.id)

	local ids = {}
	for _, entry in ipairs(Items.dropsFor(rock.id)) do
		ids[entry.itemId] = true
	end
	t.assertTrue(ids.Stone, "Rock Golem should drop Stone")

	-- The name-keyed lookup is the bug: it must not see the same table.
	local byName = {}
	for _, entry in ipairs(Items.dropsFor(rock.name)) do
		byName[entry.itemId] = true
	end
	t.assertNil(byName.Stone, "the name lookup unexpectedly found the id table")
end)

t.test("a boss drops more than a common monster", function()
	local rng = Random.new(7)
	local function average(name: string): number
		local total = 0
		for _ = 1, 300 do
			total += #Items.rollDrops(name, rng, 1)
		end
		return total / 300
	end
	local boss = Enemies.boss("Meadow")
	t.assertGreater(average(boss.id), average("Poring"))
end)

--------------------------------------------------------------------------
t.suite("Monsters")
--------------------------------------------------------------------------

t.test("every field has a varied roster", function()
	for _, field in ipairs(Fields.list()) do
		local roster = Enemies.roster(field.id)
		t.assertGreater(#roster, 2, field.id .. " has too few monsters")
	end
end)

t.test("the first field is gentle on a level-1 character", function()
	-- A level-1 Novice deals about ten damage a swing. A first monster that
	-- survives a dozen hits, or one-shots the player, is a bad first fight.
	local first = Fields.list()[1]
	local plan = { enemyHealth = Config.Wave.BaseEnemyHealth, enemyDamage = Config.Wave.BaseEnemyDamage, rewardPerKill = Config.Wave.BaseReward }
	local derived = Attributes.derive(Attributes.new(), 1)
	for _, archetype in ipairs(Enemies.roster(first.id)) do
		local scaled = Enemies.scale(archetype, plan, Zones.difficultyMultiplier(first.id))
		t.assertGreater(scaled.health, 0)
		t.assertGreater(scaled.damage, 0)
		t.assertLess(scaled.health, derived.maxHealth, archetype.name .. " survives longer than the player")
		t.assertLess(scaled.damage, derived.maxHealth, archetype.name .. " can one-shot a new player")
	end
end)

t.test("later fields are harder than the first", function()
	local fields = Fields.list()
	local first = fields[1]
	local last = fields[#fields]
	local plan = { enemyHealth = Config.Wave.BaseEnemyHealth, enemyDamage = Config.Wave.BaseEnemyDamage, rewardPerKill = Config.Wave.BaseReward }
	local function power(field: any): number
		local total = 0
		for _, archetype in ipairs(Enemies.roster(field.id)) do
			total += Enemies.scale(archetype, plan, Zones.difficultyMultiplier(field.id)).health
		end
		return total
	end
	t.assertGreater(power(last), power(first), "the last field is not harder than the first")
end)

t.test("a boss is much tougher than its field's monsters", function()
	local plan = { enemyHealth = Config.Wave.BaseEnemyHealth, enemyDamage = Config.Wave.BaseEnemyDamage, rewardPerKill = Config.Wave.BaseReward }
	for _, field in ipairs(Fields.list()) do
		local mul = Zones.difficultyMultiplier(field.id)
		local boss = Enemies.scale(Enemies.boss(field.id), plan, mul)
		local toughest = 0
		for _, archetype in ipairs(Enemies.roster(field.id)) do
			local scaled = Enemies.scale(archetype, plan, mul)
			if scaled.health > toughest then
				toughest = scaled.health
			end
		end
		t.assertGreater(boss.health, toughest, field.id .. " boss is not tougher than its monsters")
	end
end)

t.test("scaling never produces a zero or negative stat", function()
	local plan = { enemyHealth = 1, enemyDamage = 1, rewardPerKill = 1 }
	for _, field in ipairs(Fields.list()) do
		for _, archetype in ipairs(Enemies.roster(field.id)) do
			local scaled = Enemies.scale(archetype, plan, Zones.difficultyMultiplier(field.id))
			t.assertGreater(scaled.health, 0, archetype.name)
			t.assertGreater(scaled.damage, 0, archetype.name)
			t.assertGreater(scaled.reward, 0, archetype.name)
			t.assertGreater(scaled.speed, 0, archetype.name)
		end
	end
end)

t.test("a harder wave makes a monster tougher", function()
	local director = WaveDirector.new(Random.new(5))
	local easy = director:planFor(1)
	local hard = director:planFor(20)
	for _, field in ipairs(Fields.list()) do
		for _, archetype in ipairs(Enemies.roster(field.id)) do
			local mul = Zones.difficultyMultiplier(field.id)
			t.assertGreater(Enemies.scale(archetype, hard, mul).health,
				Enemies.scale(archetype, easy, mul).health, archetype.name)
		end
	end
end)

--------------------------------------------------------------------------
t.suite("MonsterShapes")
--------------------------------------------------------------------------

local MonsterShapes = require("../src/shared/MonsterShapes")

-- How far below a part's own centre its lowest point sits, in studs.
--
-- A Roblox Cylinder runs along its X axis, so a cylinder rotated 90 degrees
-- about Z stands upright and its height is size[1], not size[2]. Reading
-- size[2] regardless would report a hem disc as a tall column sunk into the
-- ground. Every other shape is axis aligned in these recipes.
local function halfHeight(part): number
        if part.shape == "Cylinder" and part.rot and math.abs(part.rot[3] % 180) == 90 then
                return part.size[1] / 2
        end
        return part.size[2] / 2
end

local function lowestPoint(recipe): number
        local lowest = math.huge
        for _, part in ipairs(recipe.parts) do
                lowest = math.min(lowest, part.at[2] - halfHeight(part))
        end
        return lowest
end

t.test("every monster in the game has its own silhouette", function()
        for _, field in ipairs(Fields.list()) do
                local roster = Enemies.roster(field.id)
                table.insert(roster, Enemies.boss(field.id))
                for _, archetype in ipairs(roster) do
                        t.assertTrue(MonsterShapes.PLANS[archetype.id] ~= nil,
                                archetype.id .. " falls back to the generic shape")
                end
        end
end)

t.test("an unknown monster still gets a usable shape", function()
        local recipe = MonsterShapes.get("NoSuchMonster")
        t.assertGreater(#recipe.parts, 0, "no fallback parts")
        t.assertNotNil(recipe.parts[1].name, "a part has no name")
end)

t.test("every recipe part is well formed", function()
        for _, id in ipairs(MonsterShapes.knownIds()) do
                local recipe = MonsterShapes.get(id)
                t.assertGreater(#recipe.parts, 0, id .. " has no parts")
                for _, part in ipairs(recipe.parts) do
                        t.assertEqual(#part.size, 3, id .. "/" .. part.name .. " size is not a 3-vector")
                        t.assertEqual(#part.at, 3, id .. "/" .. part.name .. " position is not a 3-vector")
                        for axis = 1, 3 do
                                t.assertGreater(part.size[axis], 0, id .. "/" .. part.name .. " has a zero dimension")
                        end
                        t.assertGreater(part.at[2], -0.01, id .. "/" .. part.name .. " starts below the ground")
                end
        end
end)

t.test("the recipe's primary part exists", function()
        for _, id in ipairs(MonsterShapes.knownIds()) do
                local recipe = MonsterShapes.get(id)
                local found = false
                for _, part in ipairs(recipe.parts) do
                        if part.name == recipe.primary then
                                found = true
                        end
                end
                t.assertTrue(found, id .. " primary part " .. recipe.primary .. " is missing")
        end
end)

t.test("a monster is built from more than a body and two eyes", function()
        -- The complaint that started this work was that a monster was a box
        -- with dots. A creature needs a silhouette to read at a distance, so
        -- every recipe has to carry real detail parts.
        local function detail(id: string): number
                local recipe = MonsterShapes.get(id)
                local core: { [string]: boolean } = { Body = true, Torso = true }
                local count = 0
                for _, part in ipairs(recipe.parts) do
                        if not core[part.name] then
                                count += 1
                        end
                end
                return count
        end
        for _, id in ipairs(MonsterShapes.knownIds()) do
                t.assertGreater(detail(id), 5, id .. " has only " .. detail(id) .. " detail parts")
        end
end)

t.test("a monster is more than one shape", function()
        -- A pile of blocks is still a pile of blocks. Each creature has to mix
        -- its primitives so it is not a single extruded rectangle.
        for _, id in ipairs(MonsterShapes.knownIds()) do
                local recipe = MonsterShapes.get(id)
                local shapes: { [string]: boolean } = {}
                for _, part in ipairs(recipe.parts) do
                        shapes[part.shape] = true
                end
                local distinct = 0
                for _ in pairs(shapes) do
                        distinct += 1
                end
                t.assertGreater(distinct, 1, id .. " is built from a single shape type")
        end
end)

t.test("a monster stands on the ground and faces forward", function()
        -- Every recipe is drawn in creature space, so a recipe that starts high
        -- off the ground would float and one that reaches back would fight the
        -- way it is turned to face the player. A hovering monster is the one
        -- exception, and it has to say so in the data.
        for _, id in ipairs(MonsterShapes.knownIds()) do
                local recipe = MonsterShapes.get(id)
                local lowest = lowestPoint(recipe)
                local hasForward = false
                for _, part in ipairs(recipe.parts) do
                        if part.at[3] < 0 then
                                hasForward = true
                        end
                end
                t.assertTrue(hasForward, id .. " has nothing on its front")
                if MonsterShapes.hovers(id) then
                        t.assertGreater(lowest, 0.5, id .. " hovers but is drawn on the ground")
                else
                        t.assertLess(lowest, 1.5, id .. " floats " .. lowest .. " studs off the ground")
                end
        end
end)

t.test("every hovering monster is a real monster", function()
        for _, id in ipairs(MonsterShapes.hoveringIds()) do
                t.assertNotNil(MonsterShapes.PLANS[id], id .. " hovers but has no silhouette")
        end
end)

t.test("the hovering set and the recipes agree", function()
        -- The set is hand-kept, so this is what stops it drifting: a recipe
        -- drawn in the air must be listed, and a listed monster must be drawn
        -- in the air.
        for _, id in ipairs(MonsterShapes.knownIds()) do
                local recipe = MonsterShapes.get(id)
                local drawnInAir = lowestPoint(recipe) > 1.0
                t.assertEqual(MonsterShapes.hovers(id), drawnInAir,
                        id .. (drawnInAir and " is drawn in the air but is not listed as hovering"
                                or " is listed as hovering but is drawn on the ground"))
        end
end)

t.test("no two monsters look the same", function()
        -- A shared body plan is fine, but two monsters must never be the same
        -- drawing in the same colour: the whole point of the shapes is that a
        -- player reads which monster is in front of them at a glance.
        local ids: { string } = {}
        for _, field in ipairs(Fields.list()) do
                for _, archetype in ipairs(Enemies.roster(field.id)) do
                        table.insert(ids, archetype.id)
                end
                table.insert(ids, Enemies.boss(field.id).id)
        end

        local function signature(id: string): string
                local recipe = MonsterShapes.get(id)
                local def = Enemies.getDef(id)
                local colour = def and def.color or { 0, 0, 0 }
                local out = string.format("%d,%d,%d|", colour[1], colour[2], colour[3])
                for _, part in ipairs(recipe.parts) do
                        out = out .. part.name .. tostring(part.size[1]) .. tostring(part.size[2]) .. ","
                end
                return out
        end

        local seen: { [string]: string } = {}
        for _, id in ipairs(ids) do
                local key = signature(id)
                t.assertNil(seen[key], id .. " looks identical to " .. tostring(seen[key]))
                seen[key] = id
        end
end)

--------------------------------------------------------------------------
t.suite("ClassLook")
--------------------------------------------------------------------------

local ClassLook = require("../src/shared/ClassLook")

t.test("every class in the game has a look", function()
        for _, def in ipairs(Classes.list()) do
                local look = ClassLook.get(def.id)
                t.assertNotNil(look, def.id .. " has no look")
                t.assertEqual(#look.bodyScale, 3, def.id .. " bodyScale is not a 3-vector")
                t.assertNotNil(look.swing, def.id .. " has no swing style")
        end
end)

t.test("a class look never falls back to the default silently", function()
        local named: { [string]: boolean } = {}
        for _, id in ipairs(ClassLook.knownIds()) do
                named[id] = true
        end
        for _, def in ipairs(Classes.list()) do
                t.assertTrue(named[def.id] == true, def.id .. " is missing from ClassLook.knownIds")
        end
end)

t.test("every accent is well formed", function()
        for _, id in ipairs(ClassLook.knownIds()) do
                local look = ClassLook.get(id)
                for _, accent in ipairs(look.accents) do
                        t.assertEqual(#accent.size, 3, id .. "/" .. accent.name .. " size is not a 3-vector")
                        t.assertEqual(#accent.at, 3, id .. "/" .. accent.name .. " position is not a 3-vector")
                        t.assertEqual(#accent.color, 3, id .. "/" .. accent.name .. " colour is not a 3-vector")
                        for axis = 1, 3 do
                                t.assertGreater(accent.size[axis], 0, id .. "/" .. accent.name .. " has a zero dimension")
                        end
                end
        end
end)

t.test("each job looks different from the one it came from", function()
        for _, def in ipairs(Classes.list()) do
                if def.parent then
                        local mine = ClassLook.get(def.id)
                        local parent = ClassLook.get(def.parent)
                        local sameShirt = mine.shirt[1] == parent.shirt[1]
                                and mine.shirt[2] == parent.shirt[2]
                                and mine.shirt[3] == parent.shirt[3]
                        local sameAccents = #mine.accents == #parent.accents
                        t.assertFalse(sameShirt and sameAccents, def.id .. " looks identical to " .. def.parent)
                end
        end
end)

t.test("a swing style is one the animation module can draw", function()
        local known = { slash = true, thrust = true, cast = true, stab = true, smite = true }
        for _, id in ipairs(ClassLook.knownIds()) do
                local look = ClassLook.get(id)
                t.assertTrue(known[look.swing] == true, id .. " uses unknown swing " .. tostring(look.swing))
        end
end)

--------------------------------------------------------------------------
t.suite("ItemIcons")
--------------------------------------------------------------------------

local ItemIcons = require("../src/shared/ItemIcons")

t.test("every item in the catalogue has an icon", function()
        for _, def in ipairs(Items.list()) do
                local icon = ItemIcons.get(def.id, def)
                t.assertGreater(#icon.parts, 0, def.id .. " has no icon parts")
                t.assertEqual(#icon.tilt, 3, def.id .. " tilt is not a 3-vector")
        end
end)

t.test("every icon part is well formed", function()
        for _, def in ipairs(Items.list()) do
                local icon = ItemIcons.get(def.id, def)
                for _, part in ipairs(icon.parts) do
                        t.assertEqual(#part.size, 3, def.id .. "/" .. part.name .. " size is not a 3-vector")
                        t.assertEqual(#part.at, 3, def.id .. "/" .. part.name .. " position is not a 3-vector")
                        t.assertEqual(#part.color, 3, def.id .. "/" .. part.name .. " colour is not a 3-vector")
                        for axis = 1, 3 do
                                t.assertGreater(part.size[axis], 0, def.id .. "/" .. part.name .. " has a zero dimension")
                        end
                end
        end
end)

t.test("a weapon is not drawn with an armour icon", function()
        for _, def in ipairs(Items.list()) do
                if def.kind == "equipment" and def.slot == "Weapon" then
                        local icon = ItemIcons.get(def.id, def)
                        local names: { [string]: boolean } = {}
                        for _, part in ipairs(icon.parts) do
                                names[part.name] = true
                        end
                        t.assertTrue(names.Blade or names.Orb or names.Head or names.Bow,
                                def.id .. " has no weapon-shaped part")
                end
        end
end)

t.test("a bigger weapon draws a longer blade", function()
        local function bladeLength(id: string): number
                local def = Items.getDef(id)
                local icon = ItemIcons.get(id, def)
                for _, part in ipairs(icon.parts) do
                        if part.name == "Blade" then
                                return part.size[2]
                        end
                end
                return 0
        end
        t.assertGreater(bladeLength("DragonSlayer"), bladeLength("ShortSword"),
                "the Dragon Slayer is not longer than a Short Sword")
end)

t.test("a potion and a material do not share a silhouette", function()
        local function names(id: string): { [string]: boolean }
                local def = Items.getDef(id)
                local icon = ItemIcons.get(id, def)
                local out: { [string]: boolean } = {}
                for _, part in ipairs(icon.parts) do
                        out[part.name] = true
                end
                return out
        end
        local potion = names("RedPotion")
        local shard = names("Crystal")
        local shared = 0
        for name in pairs(shard) do
                if potion[name] then
                        shared += 1
                end
        end
        t.assertEqual(shared, 0, "a potion and a shard share part names")
end)

--------------------------------------------------------------------------
t.suite("Scenery")
--------------------------------------------------------------------------

local Scenery = require("../src/shared/Scenery")

t.test("every place in the game has a scenery plan", function()
        t.assertNotNil(Scenery.plan("Town"), "Town has no plan")
        for _, field in ipairs(Fields.list()) do
                t.assertNotNil(Scenery.plan(field.id), field.id .. " has no scenery plan")
        end
end)

t.test("every plan names only props that exist", function()
        local places: { string } = { "Town" }
        for _, field in ipairs(Fields.list()) do
                table.insert(places, field.id)
        end
        for _, place in ipairs(places) do
                local plan = Scenery.plan(place)
                t.assertGreater(plan.count, 0, place .. " asks for no scenery")
                t.assertGreater(#plan.kinds, 0, place .. " names no prop kinds")
                for _, id in ipairs(plan.kinds) do
                        t.assertNotNil(Scenery.kindDef(id), place .. " names unknown prop " .. id)
                end
        end
end)

t.test("every prop recipe is well formed", function()
        for _, id in ipairs(Scenery.kindIds()) do
                local def = Scenery.kindDef(id)
                t.assertNotNil(def, id .. " has no definition")
                t.assertGreater(def.base, 0, id .. " has a non-positive base size")
                local prop = Scenery.build(id)
                t.assertNotNil(prop, id .. " builds nothing")
                t.assertGreater(#prop.parts, 0, id .. " has no parts")
                t.assertGreater(prop.footprint, 0, id .. " has a zero footprint")
                t.assertGreater(prop.height, 0, id .. " has zero height")
                for _, part in ipairs(prop.parts) do
                        t.assertEqual(#part.size, 3, id .. "/" .. part.name .. " size is not a 3-vector")
                        t.assertEqual(#part.at, 3, id .. "/" .. part.name .. " position is not a 3-vector")
                        for axis = 1, 3 do
                                t.assertGreater(part.size[axis], 0, id .. "/" .. part.name .. " has a zero dimension")
                        end
                        t.assertGreater(part.at[2], -0.01, id .. "/" .. part.name .. " starts below the ground")
                end
        end
end)

t.test("every colour role has a material", function()
        -- A role with no material would draw as default plastic, which is what
        -- made the old maps look like untextured blocks.
        local roles = {
                "wood", "bark", "leaf", "leafDark", "stone", "stoneDark",
                "metal", "cloth", "roof", "glow", "pale", "soil",
        }
        for _, role in ipairs(roles) do
                t.assertNotEqual(Scenery.materialFor(role), "SmoothPlastic", role .. " has no material")
        end
end)

t.test("every place has a full palette", function()
        local roles = {
                "wood", "bark", "leaf", "leafDark", "stone", "stoneDark",
                "metal", "cloth", "roof", "glow", "pale", "soil",
        }
        local places: { string } = { "Town" }
        for _, field in ipairs(Fields.list()) do
                table.insert(places, field.id)
        end
        for _, place in ipairs(places) do
                local palette = Scenery.palette(place)
                for _, role in ipairs(roles) do
                        local colour = palette[role]
                        t.assertNotNil(colour, place .. " has no " .. role .. " colour")
                        t.assertEqual(#colour, 3, place .. "/" .. role .. " is not a 3-vector")
                end
        end
end)

t.test("the same place scatters the same scenery every time", function()
        -- A map that reshuffles between servers would put a tree through a
        -- player who logged in on the next one.
        for _, field in ipairs(Fields.list()) do
                local seed = Scenery.seedFor(field.id)
                local first = Scenery.scatter(field.id, { x = 0, y = 0, z = 0 }, 110, seed, {})
                local second = Scenery.scatter(field.id, { x = 0, y = 0, z = 0 }, 110, seed, {})
                t.assertEqual(#first, #second, field.id .. " scattered a different count")
                for i = 1, #first do
                        t.assertEqual(first[i].kind, second[i].kind, field.id .. " prop " .. i .. " changed kind")
                        t.assertNear(first[i].x, second[i].x, 0.0001, field.id .. " prop " .. i .. " moved in x")
                        t.assertNear(first[i].z, second[i].z, 0.0001, field.id .. " prop " .. i .. " moved in z")
                end
        end
end)

t.test("two places never scatter the same layout", function()
        local seeds: { [number]: string } = {}
        for _, field in ipairs(Fields.list()) do
                local seed = Scenery.seedFor(field.id)
                t.assertNil(seeds[seed], field.id .. " shares a seed with " .. tostring(seeds[seed]))
                seeds[seed] = field.id
        end
end)

t.test("every place gets a real amount of scenery", function()
        -- A plan that is almost entirely rejected would leave the map empty,
        -- which is the bug this whole module exists to fix.
        for _, field in ipairs(Fields.list()) do
                local placed = Scenery.scatter(field.id, { x = 0, y = 0, z = 0 }, 110, Scenery.seedFor(field.id), {})
                t.assertGreater(#placed, 20, field.id .. " scattered only " .. #placed .. " props")
        end
        local town = Scenery.scatter("Town", { x = 0, y = 0, z = 0 }, 70, Scenery.seedFor("Town"), {})
        t.assertGreater(#town, 15, "the town scattered only " .. #town .. " props")
end)

t.test("scenery never stands inside a keep-out circle", function()
        -- This is the contract the world build relies on: the spawn pad, the
        -- portals and the farm plots stay clear.
        local keepOut = {
                { x = 0, z = 0, radius = 30 },
                { x = 60, z = 0, radius = 20 },
                { x = -60, z = 0, radius = 20 },
        }
        for _, field in ipairs(Fields.list()) do
                local placed = Scenery.scatter(field.id, { x = 0, y = 0, z = 0 }, 110, Scenery.seedFor(field.id), keepOut)
                for _, spot in ipairs(placed) do
                        for _, circle in ipairs(keepOut) do
                                local dx, dz = spot.x - circle.x, spot.z - circle.z
                                t.assertGreater(math.sqrt(dx * dx + dz * dz), circle.radius - 0.01,
                                        field.id .. " put " .. spot.kind .. " inside a protected circle")
                        end
                end
        end
end)

t.test("scenery never grows through itself", function()
        for _, field in ipairs(Fields.list()) do
                local placed = Scenery.scatter(field.id, { x = 0, y = 0, z = 0 }, 110, Scenery.seedFor(field.id), {})
                for i = 1, #placed do
                        for j = i + 1, #placed do
                                local a, b = placed[i], placed[j]
                                local dx, dz = a.x - b.x, a.z - b.z
                                t.assertGreater(math.sqrt(dx * dx + dz * dz), 0.001,
                                        field.id .. " stacked " .. a.kind .. " on " .. b.kind)
                        end
                end
        end
end)

t.test("every place scatters its own families, not one shared set", function()
        -- Each map must read as its own place. A shared prop set would make
        -- the five fields the same forest in five colours.
        local function kindsOf(place: string): { [string]: boolean }
                local out: { [string]: boolean } = {}
                for _, spot in ipairs(Scenery.scatter(place, { x = 0, y = 0, z = 0 }, 110, Scenery.seedFor(place), {})) do
                        out[spot.kind] = true
                end
                return out
        end
        local fieldKinds: { [string]: { [string]: boolean } } = {}
        for _, field in ipairs(Fields.list()) do
                fieldKinds[field.id] = kindsOf(field.id)
        end
        for _, a in ipairs(Fields.list()) do
                for _, b in ipairs(Fields.list()) do
                        if a.id ~= b.id then
                                local shared = 0
                                for kind in pairs(fieldKinds[a.id]) do
                                        if fieldKinds[b.id][kind] then
                                                shared += 1
                                        end
                                end
                                t.assertEqual(shared, 0, a.id .. " and " .. b.id .. " share " .. shared .. " prop kinds")
                        end
                end
        end
end)

t.test("the town is furnished, not forested", function()
        local kinds: { [string]: number } = {}
        for _, spot in ipairs(Scenery.scatter("Town", { x = 0, y = 0, z = 0 }, 70, Scenery.seedFor("Town"), {})) do
                kinds[spot.kind] = (kinds[spot.kind] or 0) + 1
        end
        t.assertGreater(kinds.House or 0, 0, "the town has no houses")
        t.assertGreater(kinds.Lamp or 0, 0, "the town has no lamps")
end)

t.test("a floating prop hangs above the ground", function()
        local placed = Scenery.scatter("Void", { x = 0, y = 0, z = 0 }, 110, Scenery.seedFor("Void"), {})
        local floating = 0
        for _, spot in ipairs(placed) do
                if spot.kind == "VoidShard" then
                        floating += 1
                        t.assertGreater(spot.y, 5, "a Void shard sits on the ground")
                end
        end
        t.assertGreater(floating, 0, "the Void has no floating shards")
end)

t.test("a solid prop collides and a small one does not", function()
        t.assertTrue(Scenery.kindDef("Pine").solid, "a pine is walk-through")
        t.assertFalse(Scenery.kindDef("Flowers").solid, "flowers block the player")
end)

t.test("the town is a walled city with a square, not just houses", function()
        -- Ragnarok's Prontera is walled, built around a market square with a
        -- fountain at its heart. These are the props that say so.
        local gates: { number } = {}
        for _, field in ipairs(Fields.list()) do
                table.insert(gates, math.atan2(field.position.z, field.position.x))
        end
        local marks = Scenery.landmarks("Town", { x = 0, y = 0, z = 0 }, Config.Town.Radius, { gates = gates })

        local seen: { [string]: number } = {}
        for _, spot in ipairs(marks) do
                seen[spot.kind] = (seen[spot.kind] or 0) + 1
        end

        t.assertGreater(seen.Fountain or 0, 0, "the square has no fountain")
        t.assertGreater(seen.Church or 0, 0, "the city has no church")
        t.assertGreater(seen.Wall or 0, 4, "the city has no wall")
        t.assertGreater(seen.GateArch or 0, 0, "the wall has no gate")
        t.assertGreater(seen.GateTower or 0, 1, "the gates have no towers")
end)

t.test("a town gate lines up with the portal behind it", function()
        -- A gate the player cannot walk through is worse than no gate: the
        -- road out of the square has to lead to the portal, not to a wall.
        local gates: { number } = {}
        for _, field in ipairs(Fields.list()) do
                table.insert(gates, math.atan2(field.position.z, field.position.x))
        end
        local marks = Scenery.landmarks("Town", { x = 0, y = 0, z = 0 }, Config.Town.Radius, { gates = gates })

        local arches: { any } = {}
        for _, spot in ipairs(marks) do
                if spot.kind == "GateArch" then
                        table.insert(arches, spot)
                end
        end
        t.assertEqual(#arches, #gates, "one gate per road, no more")

        for _, gate in ipairs(gates) do
                local edge = Config.Town.Radius - 8
                local px, pz = math.cos(gate) * edge, math.sin(gate) * edge
                local best = math.huge
                for _, arch in ipairs(arches) do
                        local dx, dz = arch.x - px, arch.z - pz
                        best = math.min(best, math.sqrt(dx * dx + dz * dz))
                end
                -- The arch stands on the wall ring, the portal just inside it,
                -- so the two are a few studs apart rather than coincident.
                t.assertLess(best, 12, "a gate is not on the road to its portal")
        end
end)

t.test("no landmark is built on a farm plot or the arrival pad", function()
        -- The plots are gameplay and the pad is where the player lands. A
        -- church on a plot would hide the crop and block the harvest.
        local gates: { number } = {}
        for _, field in ipairs(Fields.list()) do
                table.insert(gates, math.atan2(field.position.z, field.position.x))
        end
        local marks = Scenery.landmarks("Town", { x = 0, y = 0, z = 0 }, Config.Town.Radius, { gates = gates })
        local arrival = Fields.arrivalOf("Town")

        for _, spot in ipairs(marks) do
                local prop = Scenery.build(spot.kind, spot.size)
                local half = prop.footprint / 2
                for i = 1, Config.Farm.PlotCount do
                        local angle = ((i - 1) / Config.Farm.PlotCount) * math.pi * 2
                        local px = math.cos(angle) * Config.Farm.PlotRingRadius
                        local pz = math.sin(angle) * Config.Farm.PlotRingRadius
                        local dx, dz = spot.x - px, spot.z - pz
                        t.assertGreater(math.sqrt(dx * dx + dz * dz), half,
                                spot.kind .. " is built on farm plot " .. i)
                end
                local ax, az = spot.x - arrival.x, spot.z - arrival.z
                t.assertGreater(math.sqrt(ax * ax + az * az), half,
                        spot.kind .. " is built on the arrival pad")
        end
end)

t.test("every monster field gets a gate and a landmark", function()
        for _, field in ipairs(Fields.list()) do
                local centre = Fields.positionOf(field.id)
                local arrival = Fields.arrivalOf(field.id)
                local marks = Scenery.landmarks(field.id, centre, Config.Fields.ArenaRadius, { arrival = arrival })

                local seen: { [string]: boolean } = {}
                for _, spot in ipairs(marks) do
                        seen[spot.kind] = true
                end

                local hasGate = false
                local hasLandmark = false
                for kind in pairs(seen) do
                        if string.find(kind, "Gate") then
                                hasGate = true
                        end
                        if string.find(kind, "Shrine") or kind == "VoidMonolith" or kind == "HeavenStatue" then
                                hasLandmark = true
                        end
                end
                t.assertTrue(hasGate, field.id .. " has no gate")
                t.assertTrue(hasLandmark, field.id .. " has no landmark")
        end
end)

t.test("a wall panel runs along the wall, not through it", function()
        -- A panel laid radially would stand on end and leave a gap between
        -- neighbours. The panel's long axis is its X, so its yaw must put X
        -- along the ring's tangent.
        local gates: { number } = {}
        local marks = Scenery.landmarks("Town", { x = 0, y = 0, z = 0 }, Config.Town.Radius, { gates = gates })
        local walls = 0
        for _, spot in ipairs(marks) do
                if spot.kind ~= "Wall" then
                        continue
                end
                walls += 1
                local radial = math.atan2(spot.z, spot.x)
                local yaw = math.rad(spot.yaw)
                -- The panel's local X axis after a yaw of t is (cos t, -sin t).
                local x1, x2 = math.cos(yaw), -math.sin(yaw)
                local dotRadial = x1 * math.cos(radial) + x2 * math.sin(radial)
                t.assertNear(dotRadial, 0, 0.001, "a wall panel is turned across the wall")
        end
        t.assertGreater(walls, 4, "the town has almost no wall")
end)

t.test("landmarks are placed on purpose, so they never move", function()
        -- The scatter is seeded; the landmarks are not random at all. Two
        -- builds must agree, or a returning player finds the church moved.
        local gates: { number } = {}
        for _, field in ipairs(Fields.list()) do
                table.insert(gates, math.atan2(field.position.z, field.position.x))
        end
        local first = Scenery.landmarks("Town", { x = 0, y = 0, z = 0 }, Config.Town.Radius, { gates = gates })
        local second = Scenery.landmarks("Town", { x = 0, y = 0, z = 0 }, Config.Town.Radius, { gates = gates })
        t.assertEqual(#first, #second, "the town grew a landmark")
        for i = 1, #first do
                t.assertEqual(first[i].kind, second[i].kind, "landmark " .. i .. " changed kind")
                t.assertNear(first[i].x, second[i].x, 0.0001, "landmark " .. i .. " moved")
        end
end)

t.test("water is drawn as water, not as stone", function()
        local palette = Scenery.palette("Town")
        t.assertNotNil(palette.water, "the town has no water colour")
        t.assertEqual(Scenery.materialFor("water"), "Glass", "water is not see-through")
end)

t.test("every place has landmarks and they name real props", function()
        local places: { string } = { "Town" }
        for _, field in ipairs(Fields.list()) do
                table.insert(places, field.id)
        end
        for _, place in ipairs(places) do
                local radius = (place == "Town") and Config.Town.Radius or Config.Fields.ArenaRadius
                local marks = Scenery.landmarks(place, { x = 0, y = 0, z = 0 }, radius, { arrival = { x = 0, y = 0, z = 18 } })
                t.assertGreater(#marks, 0, place .. " has no landmarks")
                for _, spot in ipairs(marks) do
                        t.assertNotNil(Scenery.kindDef(spot.kind), place .. " builds unknown landmark " .. spot.kind)
                end
        end
end)

t.test("only the first field is safe and each later field is deadlier", function()
        local zones = Zones.list()
        t.assertGreater(#zones, 1, "there is only one field")

        -- The first field is the tutorial, so it must not kill.
        t.assertFalse(Zones.isLethal(zones[1].id), "the first field can kill the player")
        t.assertEqual(zones[1].id, "Meadow")

        -- Every later field must be lethal and must hit harder than the one
        -- before it, so moving on is always a real step up.
        for i = 2, #zones do
                t.assertTrue(Zones.isLethal(zones[i].id), zones[i].id .. " cannot kill the player")
                t.assertGreater(zones[i].difficultyMultiplier, zones[i - 1].difficultyMultiplier,
                        zones[i].id .. " is not harder than " .. zones[i - 1].id)
                t.assertGreater(zones[i].coinMultiplier, zones[i - 1].coinMultiplier,
                        zones[i].id .. " does not pay better than " .. zones[i - 1].id)
                t.assertGreater(zones[i].levelRequirement, zones[i - 1].levelRequirement,
                        zones[i].id .. " does not need a higher level than " .. zones[i - 1].id)
        end

        -- An unknown zone is treated as lethal, so a typo cannot make the game
        -- safe by accident.
        t.assertTrue(Zones.isLethal("NoSuchField"), "an unknown field was treated as safe")
end)

t.test("the safe field still deals damage, it just cannot finish the player", function()
        -- A safe field that deals nothing would be a broken field. The rule is
        -- about the killing blow, not about immunity.
        local player = Combat.createCombatant(100)
        local died, health = Combat.damageCombatant(player, 30, true)
        t.assertFalse(died)
        t.assertEqual(health, 70, "the safe field dealt no damage")
end)

--------------------------------------------------------------------------
t.suite("Atmosphere")
--------------------------------------------------------------------------

local Atmosphere = require("../src/shared/Atmosphere")

t.test("every place in the game has an atmosphere profile", function()
        t.assertNotNil(Atmosphere.profileFor("Town"), "Town has no atmosphere")
        for _, field in ipairs(Fields.list()) do
                t.assertNotNil(Atmosphere.profileFor(field.id), field.id .. " has no atmosphere")
        end
end)

t.test("every profile is inside what Roblox accepts", function()
        -- An out-of-range value is silently clamped by the engine, which hides
        -- a typo instead of failing a build.
        for _, place in ipairs(Atmosphere.placeIds()) do
                local p = Atmosphere.profileFor(place)
                t.assertGreater(p.density, 0, place .. " density is not positive")
                t.assertLess(p.density, 1, place .. " density is out of range")
                t.assertGreater(p.cloudCover, 0, place .. " cloud cover is not positive")
                t.assertLess(p.cloudCover, 1, place .. " cloud cover is out of range")
                t.assertGreater(p.bloomIntensity, 0, place .. " bloom intensity is not positive")
                t.assertLess(p.bloomIntensity, 3, place .. " bloom intensity is out of range")
                t.assertGreater(p.brightness, 0.5, place .. " brightness is too dark")
                t.assertLess(p.brightness, 2, place .. " brightness is too bright")
                t.assertEqual(#p.color, 3, place .. " atmosphere colour is not a 3-vector")
                t.assertEqual(#p.tint, 3, place .. " tint is not a 3-vector")
                t.assertGreater(p.wind, 0, place .. " wind is not positive")
        end
end)

t.test("the places do not all look the same", function()
        -- If two places share a profile, the map that arrives is the map that
        -- left, and travel stops meaning anything.
        local seen: { [string]: string } = {}
        for _, place in ipairs(Atmosphere.placeIds()) do
                local p = Atmosphere.profileFor(place)
                local key = string.format("%.3f|%.3f|%.3f|%.3f|%.3f|%.3f",
                        p.density, p.cloudCover, p.bloomIntensity, p.brightness, p.contrast, p.saturation)
                t.assertNil(seen[key], place .. " has the same atmosphere as " .. tostring(seen[key]))
                seen[key] = place
        end
end)

t.test("the town is the brightest place and the Void the dimmest", function()
        local town = Atmosphere.profileFor("Town")
        local void = Atmosphere.profileFor("Void")
        t.assertGreater(town.brightness, void.brightness, "the town is not brighter than the Void")
        t.assertGreater(void.bloomIntensity, town.bloomIntensity, "the Void does not glow more than the town")
end)

t.test("an unknown place falls back instead of failing", function()
        local fallback = Atmosphere.profileFor("NoSuchPlace")
        t.assertNotNil(fallback, "an unknown place has no profile")
        t.assertNear(fallback.density, Atmosphere.profileFor("Town").density, 0.0001, "the fallback is not the town's")
end)

t.suite("Villagers")

t.test("the town has people to talk to, not only props", function()
        t.assertGreater(Villagers.Count, 0, "the town has no villagers at all")
end)

t.test("every villager names a panel the client can actually open", function()
        -- A villager whose `opens` is not in the known set is a body that does
        -- nothing when a player walks up and taps it, which is the exact bug the
        -- town started with.
        for _, def in ipairs(Villagers.List) do
                t.assertTrue(Villagers.opensKnown(def.opens),
                        def.id .. " opens an unknown panel: " .. tostring(def.opens))
        end
end)

t.test("every villager has its own name and title text", function()
        local seenName: { [string]: boolean } = {}
        for _, def in ipairs(Villagers.List) do
                t.assertNotEqual(Text.get(def.nameKey), def.nameKey, def.id .. " has no name text")
                t.assertNotEqual(Text.get(def.titleKey), def.titleKey, def.id .. " has no title text")
                t.assertNil(seenName[def.nameKey], def.id .. " shares a name with another villager")
                seenName[def.nameKey] = true
        end
end)

t.test("every villager stands inside the town and clear of the others", function()
        -- The town radius is the floor a villager stands on; outside it they would
        -- float over the world slab, and overlapping they would read as one body.
        local town = Config.Town
        local placed: { { x: number, z: number } } = {}
        for _, def in ipairs(Villagers.List) do
                local p = Villagers.positionOf(def)
                local dist = math.sqrt(p.x * p.x + p.z * p.z)
                t.assertLess(dist, town.Radius, def.id .. " stands outside the town floor")
                for _, other in ipairs(placed) do
                        local dx = p.x - other.x
                        local dz = p.z - other.z
                        t.assertGreater(math.sqrt(dx * dx + dz * dz), 6,
                                def.id .. " stands on top of another villager")
                end
                table.insert(placed, { x = p.x, z = p.z })
        end
end)

t.test("a villager is reachable by walking, not only by tapping a button", function()
        -- The prompt's reach is what makes the town walkable. If it were zero the
        -- villager would be decoration again.
        t.assertGreater(Villagers.Reach, 4, "villagers cannot be reached by walking up")
end)

t.suite("Death penalty")

t.test("the training field never charges for a death", function()
        -- The first field cannot kill, and if it could not charge either then the
        -- whole risk side of the game would be imaginary.
        local penalty = Death.penalty(10000, false)
        t.assertFalse(penalty.charged, "the safe field charged for a death")
        t.assertEqual(penalty.remaining, 10000, "the safe field took coins")
end)

t.test("a lethal field charges a fraction of the balance", function()
        local penalty = Death.penalty(1000, true)
        t.assertTrue(penalty.charged, "a lethal death cost nothing")
        t.assertEqual(penalty.coins, 100, "the charge is not the configured percent")
        t.assertEqual(penalty.remaining, 900, "the balance after the charge is wrong")
end)

t.test("one death can never wipe a session's savings", function()
        -- The cap is the whole point: without it a player carrying millions loses
        -- millions in one bad wave and has no reason to come back.
        local penalty = Death.penalty(1e9, true)
        t.assertEqual(penalty.coins, Config.Death.MaxCoinLoss, "the cap was not applied")
        t.assertEqual(penalty.remaining, 1e9 - Config.Death.MaxCoinLoss, "the capped balance is wrong")
end)

t.test("a player with almost nothing keeps what they have", function()
        -- Taking the last coins off somebody who just died is how a bad session
        -- becomes a reason to leave.
        local penalty = Death.penalty(Config.Death.MinCoinsToCharge - 1, true)
        t.assertFalse(penalty.charged, "a broke player was charged")
        t.assertEqual(penalty.remaining, Config.Death.MinCoinsToCharge - 1, "a broke player lost coins")
end)

t.test("the charge never exceeds the balance", function()
        -- The percent floor and the cap can both misbehave on a small balance; the
        -- balance must never go negative whatever the config says.
        for _, coins in ipairs({ 200, 201, 499, 1000, 999999 }) do
                local penalty = Death.penalty(coins, true)
                t.assertLess(penalty.remaining, coins + 1, "the balance grew after a death")
                t.assertTrue(penalty.remaining >= 0, "the balance went negative at " .. tostring(coins))
                t.assertTrue(penalty.coins <= coins, "the charge exceeded the balance at " .. tostring(coins))
        end
end)

t.suite("Combat defaults")

t.test("the player fights, the game does not fight for them", function()
        -- Auto-attack defaulting on is what made the game a screensaver. This test
        -- is the one that has to fail if somebody flips it back.
        t.assertFalse(Config.Combat.AutoAttack, "auto-attack is on by default again")
end)

return t.finish()

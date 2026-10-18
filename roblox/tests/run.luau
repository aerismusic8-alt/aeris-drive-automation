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

return t.finish()

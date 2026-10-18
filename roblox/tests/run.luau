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

return t.finish()

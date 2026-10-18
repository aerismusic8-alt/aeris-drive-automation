--!nocheck
-- Integration test: run the real game loop without Roblox.
--
-- The pure modules (WaveDirector, Combat, Leveling, SaveSchema, DailyRewards,
-- Codes) have no Roblox globals, so the actual reward path can be exercised
-- here. This catches the bugs that unit tests miss: a wrong multiplier, a
-- reward that never pays out, a save that loses progress on reload.
--
-- It is deliberately a *simulation* of the server tick, using the same
-- functions the server calls, rather than a copy of the server logic.

local Shared = "../src/shared/"

local Config = require(Shared .. "Config")
local Combat = require(Shared .. "Combat")
local Leveling = require(Shared .. "Leveling")
local WaveDirector = require(Shared .. "WaveDirector")
local SaveSchema = require(Shared .. "SaveSchema")
local DailyRewards = require(Shared .. "DailyRewards")
local Codes = require(Shared .. "Codes")
local Stats = require(Shared .. "Stats")
local Pets = require(Shared .. "Pets")
local Rebirth = require(Shared .. "Rebirth")
local Zones = require(Shared .. "Zones")
local Monetization = require(Shared .. "Monetization")

local failures = 0
local passed = 0

local function check(label: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failures += 1
		print(string.format("  FAIL  %s%s", label, detail and (" -> " .. detail) or ""))
	end
end

local function section(name: string)
	print("\n" .. name)
end

-- A tiny deterministic RNG, so a failure can always be reproduced.
local function makeRng(seed: number)
	local state = seed
	return {
		NextNumber = function(_, min: number, max: number)
			state = (state * 1103515245 + 12345) % 2147483648
			return min + (state / 2147483648) * (max - min)
		end,
	}
end

--------------------------------------------------------------------------
section("SIM 1: a full wave can be cleared and pays out")
--------------------------------------------------------------------------

do
	local rng = makeRng(7)
	local director = WaveDirector.new(rng)

	-- A fresh save, exactly as the server builds one.
	local save = SaveSchema.new()
	local player = {
		coins = save.coins,
		upgrades = save.upgrades,
		level = save.level,
		xp = save.xp,
		stats = save.stats,
	}

	local startCoins = player.coins
	local kills = 0
	local wave = 0

	-- Skip the intermission, then fight wave 1 to completion.
	local events = director:advance(Config.Wave.IntermissionSeconds + 1)
	wave = director:snapshot().wave

	local guard = 0
	while guard < 10000 do
		guard += 1
		local spawned, completed = director:update(1 / Config.Tick.Rate)
		for _, plan in ipairs(spawned) do
			local enemy = Combat.createEnemy(plan, 0)
			-- The server always pairs a spawn with this call; without it the
			-- director never believes the wave finished.
			director:notifyEnemySpawned()
			-- A fully upgraded player, so the kill is certain and the test is
			-- about the reward path, not about luck.
			local damage = Stats.derive({ Damage = 10, Health = 0, Speed = 0, CritChance = 0 }).damage
			local killed, reward = Combat.damageEnemy(enemy, damage * 1000)
			if killed then
				kills += 1
				director:notifyEnemyRemoved()
				player.coins += reward
				local xp = Leveling.xpFromKill(plan.wave)
				local progress = Leveling.addXp({ level = player.level, xp = player.xp }, xp)
				player.level, player.xp = progress.level, progress.xp
				player.stats.kills += 1
			end
		end
		if completed then
			break
		end
	end

	check("wave 1 completes", guard < 10000, "loop guard hit")
	check("kills were credited", kills > 0, "kills=" .. kills)
	check("coins increased", player.coins > startCoins, "coins=" .. player.coins)
	check("kills recorded", player.stats.kills == kills, "stats.kills=" .. player.stats.kills)
	check("xp was awarded", player.xp > 0 or player.level > 1, "level=" .. player.level .. " xp=" .. player.xp)
	print(string.format("  wave=%d kills=%d coins=%d level=%d xp=%d", wave, kills, player.coins, player.level, player.xp))
end

--------------------------------------------------------------------------
section("SIM 2: a later wave is harder and pays more")
--------------------------------------------------------------------------

do
	local rng = makeRng(11)
	local director = WaveDirector.new(rng)
	local early = director:planFor(1)
	local late = director:planFor(20)

	check("later waves have more enemies", late.enemyCount > early.enemyCount,
		early.enemyCount .. " -> " .. late.enemyCount)
	check("later enemies have more health", late.enemyHealth > early.enemyHealth,
		early.enemyHealth .. " -> " .. late.enemyHealth)
	check("later waves pay more", late.rewardPerKill > early.rewardPerKill,
		early.rewardPerKill .. " -> " .. late.rewardPerKill)
	print(string.format("  wave1: %d enemies, %d hp, %d coins", early.enemyCount, early.enemyHealth, early.rewardPerKill))
	print(string.format("  wave20: %d enemies, %d hp, %d coins", late.enemyCount, late.enemyHealth, late.rewardPerKill))
end

--------------------------------------------------------------------------
section("SIM 3: multipliers stack and never go negative")
--------------------------------------------------------------------------

do
	local rng = makeRng(3)
	local pets = Pets.new()
	local rebirth = Rebirth.fromSnapshot({ count = 2 })
	local entitlements = Monetization.newEntitlements()
	local zone = Zones.defaultZone()

	local petCoin = select(1, Pets.equippedMultipliers(pets))
	local rebirthCoin = select(1, Rebirth.multipliers(rebirth.count))
	local levelCoin = Leveling.coinMultiplier(1)
	local zoneCoin = Zones.coinMultiplier(zone)
	local monCoin = Monetization.coinMultiplier(entitlements, 0)

	local total = petCoin * rebirthCoin * levelCoin * zoneCoin * monCoin
	check("multiplier is positive", total > 0, "total=" .. total)
	check("multiplier is finite", total == total and total < math.huge, "total=" .. total)
	print(string.format("  pet=%.2f rebirth=%.2f level=%.2f zone=%.2f monetization=%.2f total=%.2f",
		petCoin, rebirthCoin, levelCoin, zoneCoin, monCoin, total))
end

--------------------------------------------------------------------------
section("SIM 4: progress survives a save/load cycle")
--------------------------------------------------------------------------

do
	local save = SaveSchema.new()
	save.coins = 12345
	save.level = 7
	save.xp = 321
	save.rebirths = 2
	save.zone = "Cavern"
	save.stats = { kills = 50, wavesCleared = 5, deaths = 1 }
	save.daily = { streak = 4, lastClaimAt = 1000, totalClaims = 4 }
	save.redeemed = { RELEASE = { code = "RELEASE", at = 500 } }

	-- The server serializes to a table and writes it; simulate the round trip.
	local payload = {
		version = Config.Persistence.SchemaVersion,
		coins = save.coins,
		upgrades = save.upgrades,
		inventory = {},
		stats = save.stats,
		level = save.level,
		xp = save.xp,
		rebirths = save.rebirths,
		zone = save.zone,
		pets = Pets.snapshot(save.pets),
		entitlements = save.entitlements,
		daily = DailyRewards.snapshot(save.daily),
		redeemed = Codes.snapshot(save.redeemed),
		updatedAt = 999,
	}

	local loaded = SaveSchema.load(payload)
	check("save reloads", loaded ~= nil, "load returned nil")
	if loaded then
		check("coins survive", loaded.coins == 12345, "coins=" .. loaded.coins)
		check("level survives", loaded.level == 7, "level=" .. loaded.level)
		check("xp survives", loaded.xp == 321, "xp=" .. loaded.xp)
		check("rebirths survive", loaded.rebirths == 2, "rebirths=" .. loaded.rebirths)
		check("zone survives", loaded.zone == "Cavern", "zone=" .. loaded.zone)
		check("kills survive", loaded.stats.kills == 50, "kills=" .. loaded.stats.kills)
		check("streak survives", loaded.daily.streak == 4, "streak=" .. loaded.daily.streak)
		check("redemption survives", Codes.hasRedeemed(loaded.redeemed, "RELEASE"), "RELEASE missing")
	end
end

--------------------------------------------------------------------------
section("SIM 5: a 7-day login streak pays every day")
--------------------------------------------------------------------------

do
	local state = DailyRewards.new()
	local now = 1000000
	local totalCoins = 0
	local days = 0

	for day = 1, 7 do
		local next, reward, reason = DailyRewards.claim(state, now)
		check("day " .. day .. " claims", next ~= nil and reward ~= nil, tostring(reason))
		if next and reward then
			state = next
			totalCoins += reward.coins
			days += 1
		end
		-- 24h later, which is past the cooldown and inside the grace window.
		now += 24 * 60 * 60
	end

	check("all 7 days paid", days == 7, "days=" .. days)
	check("streak reached 7", state.streak == 7, "streak=" .. state.streak)
	check("cycle total is meaningful", totalCoins > 0, "coins=" .. totalCoins)
	-- A claim at the exact same second must be refused, or the reward is
	-- infinite. (`now` has already moved a day on, so test the boundary.)
	local lastClaimAt = state.lastClaimAt
	local again, _, reason = DailyRewards.claim(state, lastClaimAt)
	check("a second claim in the same second is refused", again == nil, tostring(reason))

	-- One second before the cooldown ends is still too soon.
	local early, _, earlyReason = DailyRewards.claim(state, lastClaimAt + Config.Daily.CooldownSeconds - 1)
	check("a claim one second early is refused", early == nil, tostring(earlyReason))

	-- Exactly at the cooldown boundary it is allowed.
	local onTime = DailyRewards.claim(state, lastClaimAt + Config.Daily.CooldownSeconds)
	check("a claim at the cooldown boundary is allowed", onTime ~= nil, tostring(onTime))
	print(string.format("  7-day total=%d coins, streak=%d", totalCoins, state.streak))
end

--------------------------------------------------------------------------
section("SIM 6: a code pays exactly once")
--------------------------------------------------------------------------

do
	local redeemed = {}
	local now = 2000000

	local next, def, reason = Codes.redeem(redeemed, "RELEASE", now)
	check("first redeem works", next ~= nil and def ~= nil, tostring(reason))
	if next then
		redeemed = next
	end
	check("code is recorded", Codes.hasRedeemed(redeemed, "RELEASE"))

	local second, _, secondReason = Codes.redeem(redeemed, "RELEASE", now + 1)
	check("second redeem is refused", second == nil, tostring(secondReason))

	local bad, _, badReason = Codes.redeem(redeemed, "NOT-A-CODE", now + 1)
	check("unknown code is refused", bad == nil, tostring(badReason))
	print(string.format("  RELEASE paid %d coins once", def and def.coins or 0))
end

--------------------------------------------------------------------------
section("SIM 7: level ups and rebirth unlock the next zone")
--------------------------------------------------------------------------

do
	local progress = { level = 1, xp = 0 }
	local levels = 0
	local guard = 0
	while progress.level < Config.Leveling.MaxLevel and guard < 100000 do
		guard += 1
		local before = progress.level
		progress = Leveling.addXp(progress, Leveling.xpForNext(progress.level))
		if progress.level > before then
			levels += 1
		end
	end
	check("leveling reaches the cap", progress.level == Config.Leveling.MaxLevel,
		"level=" .. progress.level)
	check("levelling is finite", guard < 100000, "guard=" .. guard)

	local requirement = Rebirth.levelRequirement(0)
	check("rebirth requires a real level", requirement > 1, "requirement=" .. requirement)

	local locked, lockedReason = Zones.resolveTravel("VoidRift", 1, false)
	check("a high zone is locked at level 1", locked == nil, tostring(lockedReason))
	local unlocked = Zones.resolveTravel("Meadow", 1, false)
	check("the first zone is open", unlocked == "Meadow", tostring(unlocked))
end

--------------------------------------------------------------------------
print(string.format("\nINTEGRATION: %d passed, %d failed", passed, failures))
if failures > 0 then
	error(string.format("%d integration check(s) failed", failures), 0)
end

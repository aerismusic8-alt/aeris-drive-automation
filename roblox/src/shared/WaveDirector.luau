--!strict
-- Wave director: pure state machine driving enemy spawn scaling.
-- Emits a plan each tick; the Roblox layer is responsible for instantiating.

local Config = require("./Config")

local WaveDirector = {}
WaveDirector.__index = WaveDirector

export type WavePhase = "INTERMISSION" | "ACTIVE"

export type SpawnPlan = {
	wave: number,
	enemyCount: number,
	enemyHealth: number,
	enemyDamage: number,
	rewardPerKill: number,
	spawnInterval: number,
}

export type Snapshot = {
	phase: WavePhase,
	wave: number,
	elapsed: number,
	timeRemaining: number,
	aliveEnemies: number,
	pendingSpawns: number,
}

function WaveDirector.new(rng)
	local self = setmetatable({}, WaveDirector)
	self._rng = rng
	self._wave = 0
	self._phase = "INTERMISSION"
	self._elapsed = 0
	self._spawnAccumulator = 0
	self._pending = 0
	self._alive = 0
	self:reset()
	return self
end

function WaveDirector:reset()
	self._wave = 0
	self._phase = "INTERMISSION"
	self._elapsed = 0
	self._spawnAccumulator = 0
	self._pending = 0
	self._alive = 0
end

-- Scaling curve for a given wave number (1-based).
function WaveDirector:planFor(wave: number): SpawnPlan
	local cfg = Config.Wave
	local count = math.min(
		cfg.BaseEnemyCount + cfg.EnemiesPerWave * (wave - 1),
		cfg.MaxEnemiesPerWave
	)
	local growth = cfg.HealthGrowth ^ (wave - 1)
	return {
		wave = wave,
		enemyCount = count,
		enemyHealth = math.floor(cfg.BaseEnemyHealth * growth + 0.5),
		enemyDamage = math.floor(cfg.BaseEnemyDamage * (cfg.DamageGrowth ^ (wave - 1)) + 0.5),
		rewardPerKill = math.floor(cfg.BaseReward * (cfg.RewardGrowth ^ (wave - 1)) + 0.5),
		spawnInterval = math.max(0.25, 1.25 - wave * 0.03),
	}
end

function WaveDirector:startWave()
	self._wave += 1
	self._phase = "ACTIVE"
	self._elapsed = 0
	self._spawnAccumulator = 0
	local plan = self:planFor(self._wave)
	self._pending = plan.enemyCount
	return plan
end

-- Called by the combat layer when an enemy dies or is removed.
function WaveDirector:notifyEnemyRemoved()
	if self._alive > 0 then
		self._alive -= 1
	end
end

function WaveDirector:notifyEnemySpawned()
	if self._pending > 0 then
		self._pending -= 1
	end
	self._alive += 1
end

-- Advance the director. Returns a list of spawn events for this tick and
-- whether the wave just completed.
function WaveDirector:update(dt: number): ({ SpawnPlan }, boolean)
	local cfg = Config.Wave
	dt = math.min(dt, Config.Tick.MaxDeltaTime)
	self._elapsed += dt

	if self._phase == "INTERMISSION" then
		if self._elapsed >= cfg.IntermissionSeconds then
			local plan = self:startWave()
			return { plan }, false
		end
		return {}, false
	end

	local events: { SpawnPlan } = {}
	local plan = self:planFor(self._wave)
	self._spawnAccumulator += dt
	while self._spawnAccumulator >= plan.spawnInterval and self._pending > 0 do
		self._spawnAccumulator -= plan.spawnInterval
		table.insert(events, plan)
	end

	local waveComplete = self._pending == 0 and self._alive == 0 and self._elapsed >= plan.spawnInterval
	if waveComplete then
		self._phase = "INTERMISSION"
		self._elapsed = 0
		self._spawnAccumulator = 0
	end
	return events, waveComplete
end

-- Advance the director by `seconds`, stepping at the configured tick rate so
-- a large frame gap is simulated faithfully instead of being clamped away.
-- Returns every spawn plan released during the interval.
function WaveDirector:advance(seconds: number): ({ SpawnPlan }, boolean)
	local step = 1 / Config.Tick.Rate
	local events: { SpawnPlan } = {}
	local completed = false
	local remaining = seconds
	while remaining > 0 do
		local dt = math.min(step, remaining)
		local tickEvents, done = self:update(dt)
		for _, plan in ipairs(tickEvents) do
			table.insert(events, plan)
		end
		completed = completed or done
		remaining -= dt
	end
	return events, completed
end

function WaveDirector:snapshot(): Snapshot
	local cfg = Config.Wave
	local timeRemaining = 0
	if self._phase == "INTERMISSION" then
		timeRemaining = math.max(0, cfg.IntermissionSeconds - self._elapsed)
	end
	return {
		phase = self._phase,
		wave = self._wave,
		elapsed = self._elapsed,
		timeRemaining = timeRemaining,
		aliveEnemies = self._alive,
		pendingSpawns = self._pending,
	}
end

return WaveDirector

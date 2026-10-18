--!strict
-- Combat resolution. Pure Luau: damage, death, and reward accounting.

local Config = require("./Config")

local Combat = {}

export type Enemy = {
	id: number,
	wave: number,
	health: number,
	maxHealth: number,
	damage: number,
	reward: number,
	nextAttackAt: number,
	alive: boolean,
}

export type Combatant = {
	health: number,
	maxHealth: number,
	alive: boolean,
}

local nextEnemyId = 0

function Combat.createEnemy(plan, now: number): Enemy
	nextEnemyId += 1
	return {
		id = nextEnemyId,
		wave = plan.wave,
		health = plan.enemyHealth,
		maxHealth = plan.enemyHealth,
		damage = plan.enemyDamage,
		reward = plan.rewardPerKill,
		nextAttackAt = now + Config.Wave.EnemyAttackInterval,
		alive = true,
	}
end

-- Reset the id counter. Test-only helper for deterministic ids.
function Combat._resetIds()
	nextEnemyId = 0
end

-- Apply damage to an enemy. Returns (killed, reward, overkillDamage).
function Combat.damageEnemy(enemy: Enemy, amount: number): (boolean, number, number)
	if not enemy.alive or amount <= 0 then
		return false, 0, 0
	end

	enemy.health -= amount
	if enemy.health > 0 then
		return false, 0, 0
	end

	local overkill = -enemy.health
	enemy.health = 0
	enemy.alive = false
	return true, enemy.reward, overkill
end

-- Apply damage to a player combatant. Returns (died, remainingHealth).
function Combat.damageCombatant(target: Combatant, amount: number): (boolean, number)
	if not target.alive or amount <= 0 then
		return false, target.health
	end

	target.health = math.max(0, target.health - amount)
	if target.health == 0 then
		target.alive = false
		return true, 0
	end
	return false, target.health
end

function Combat.healCombatant(target: Combatant, amount: number): number
	-- Dead combatants stay dead: healing is not a revive.
	if not target.alive or amount <= 0 then
		return target.health
	end
	target.health = math.min(target.maxHealth, target.health + amount)
	return target.health
end

function Combat.createCombatant(maxHealth: number): Combatant
	assert(maxHealth > 0, "maxHealth must be positive")
	return { health = maxHealth, maxHealth = maxHealth, alive = true }
end

-- Enemy attack cadence: returns the number of attacks due by `now`.
function Combat.attacksDue(enemy: Enemy, now: number): (number, number)
	if not enemy.alive or now < enemy.nextAttackAt then
		return 0, enemy.nextAttackAt
	end
	local interval = Config.Wave.EnemyAttackInterval
	local overdue = now - enemy.nextAttackAt
	local count = 1 + math.floor(overdue / interval)
	return count, enemy.nextAttackAt + count * interval
end

return Combat

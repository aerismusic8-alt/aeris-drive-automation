--[[
	File: Common/Trajectory.luau

	Deterministic projectile-path math shared by all Gunnable SubTypes:
	Launcher (parabolic, gravity > 0), Turret + Hardpoint (straight-line
	tracers via gravity = 0). The server uses solveImpact to find the
	landing point and travel time; clients use positionAt/velocityAt to
	render the exact same path anchored to workspace:GetServerTimeNow().
]]--

local Trajectory = {}

local STEP_DISTANCE = 4

export type ImpactResult = {
	ImpactPoint: Vector3,
	TravelTime: number,
	HitInstance: BasePart?,
	Expired: boolean,
}

---Position of the projectile `t` seconds after launch. `gravity` is the
---downward acceleration magnitude (0 = no drop).
function Trajectory.positionAt(origin: Vector3, direction: Vector3, speed: number, gravity: number, t: number): Vector3
	return origin + direction * (speed * t) - Vector3.yAxis * (0.5 * gravity * t * t)
end

---Velocity of the projectile `t` seconds after launch. Used to orient the
---rendered projectile and to derive its approach direction at impact.
function Trajectory.velocityAt(direction: Vector3, speed: number, gravity: number, t: number): Vector3
	return direction * speed - Vector3.yAxis * (gravity * t)
end

---Simulates the projectile path and resolves where/when it lands. With no
---gravity this is a single raycast; with gravity the parabola is stepped in
---short segments. If the cumulative path length reaches `range` before any
---hit, the shot is `Expired` (no explosion/damage should occur).
---Performs one swept cast for `solveImpact`: a spherecast of the given `radius`
---(accounting for projectile thickness) when `radius > 0`, otherwise a thin raycast.
local function castShape(origin: Vector3, displacement: Vector3, raycastParams: RaycastParams, radius: number?): RaycastResult?
	if radius and radius > 0 then
		return workspace:Spherecast(origin, radius, displacement, raycastParams)
	end

	return workspace:Raycast(origin, displacement, raycastParams)
end

function Trajectory.solveImpact(origin: Vector3, direction: Vector3, speed: number, gravity: number, range: number, raycastParams: RaycastParams, radius: number?): ImpactResult
	if speed <= 0 or speed ~= speed then
		return {
			ImpactPoint = origin,
			TravelTime = 0,
			HitInstance = nil,
			Expired = true,
		}
	end

	if gravity <= 0 then
		local result = castShape(origin, direction * range, raycastParams, radius)
		if result then
			return {
				ImpactPoint = result.Position,
				TravelTime = result.Distance / speed,
				HitInstance = result.Instance,
				Expired = false,
			}
		end

		return {
			ImpactPoint = origin + direction * range,
			TravelTime = range / speed,
			HitInstance = nil,
			Expired = true,
		}
	end

	local dt = STEP_DISTANCE / speed
	local traveled = 0
	local prevPos = origin
	local prevT = 0

	while traveled < range do
		local nextT = prevT + dt
		local nextPos = Trajectory.positionAt(origin, direction, speed, gravity, nextT)
		local segment = nextPos - prevPos
		local segmentLength = segment.Magnitude

		local result = castShape(prevPos, segment, raycastParams, radius)
		if result then
			local fraction = if segmentLength > 0 then result.Distance / segmentLength else 0
			return {
				ImpactPoint = result.Position,
				TravelTime = prevT + fraction * dt,
				HitInstance = result.Instance,
				Expired = false,
			}
		end

		traveled += segmentLength
		prevPos = nextPos
		prevT = nextT
	end

	return {
		ImpactPoint = prevPos,
		TravelTime = prevT,
		HitInstance = nil,
		Expired = true,
	}
end

return Trajectory
|
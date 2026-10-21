--[[
	File: ReplicatedStorage/FourD/Architects/Firearm2/Common/AimAssist.luau

	Aim assist for touch, in the two forms that do not feel like cheating.

	Friction: while the crosshair is near a target, the look input is scaled
	down, so small corrections stop overshooting. It never moves the camera on
	its own, so a player who is not aiming at anyone is unaffected.

	Magnetism: a bounded pull toward the target, proportional to how far off
	it is, applied over time. The bound is what keeps it honest -- it can close
	a near miss, it cannot spin the player around.

	Both are computed from the camera's own look vector, and the shot is fired
	along that same vector, so the server's direction check sees exactly what
	the player sees. A target is only considered when it is on the other team,
	alive, inside the cone, in range, and has line of sight from the camera.

	The whole module is inert unless `params.AimAssist` is truthy, which the
	caller sets for touch only.
]]--

-- Root

local AimAssist = {}
AimAssist.__index = AimAssist

-- Roblox Services

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Constants

local DEFAULT_FOV_DEG = Constants.AIM_ASSIST_FOV_DEG
local DEFAULT_MAX_RANGE = Constants.AIM_ASSIST_RANGE
local DEFAULT_MIN_FRICTION = Constants.AIM_ASSIST_MIN_FRICTION
local DEFAULT_MAGNETISM = Constants.AIM_ASSIST_STRENGTH
local DEFAULT_MAX_PULL_DEG = Constants.AIM_ASSIST_MAX_PULL_DEG

-- Re-scanning every frame is wasted work; targets move far slower than that.
local SCAN_INTERVAL = 0.05

-- Local Functions

local function toDegrees(radians: number): number
	return math.deg(radians)
end

---The point on a character worth aiming at: the head if it has one, else the
---root, so a rig without a head part still works.
local function aimPointOf(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end

	return nil
end

local function isTargetable(localPlayer: Player, other: Player): boolean
	if other == localPlayer then return false end
	if other.Team == nil or other.Team == localPlayer.Team then return false end

	local character = other.Character
	if not character then return false end

	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end

	-- MatchManager marks the living; a player who is dead but still parented
	-- must not pull the crosshair.
	if other:GetAttribute("Alive") == false then return false end

	return true
end

-- Public Methods

---Recompute the best target. Called on its own interval, not every frame.
function AimAssist:_scan(camera: Camera)
	self._target = nil
	self._targetOffset = nil
	self._targetDirection = nil

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local cosFov = math.cos(math.rad(self._fovDeg))
	local bestOffset, bestPoint, bestDirection = nil, nil, nil

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character }
	params.IgnoreWater = true

	for _, other in ipairs(Players:GetPlayers()) do
		if isTargetable(localPlayer, other) then
			local character = other.Character
			local point = character and aimPointOf(character)
			if point then
				local toTarget = point.Position - origin
				local distance = toTarget.Magnitude
				if distance > 0.001 and distance <= self._maxRange then
					local direction = toTarget / distance
					if look:Dot(direction) >= cosFov then
						-- Only a target actually visible counts; a pull through
						-- a wall is the kind of assist players notice and hate.
						local hit = Workspace:Raycast(origin, direction * distance, params)
						local clear = (hit == nil) or (hit.Instance and hit.Instance:IsDescendantOf(character))
						if clear then
							local offset = math.acos(math.clamp(look:Dot(direction), -1, 1))
							if bestOffset == nil or offset < bestOffset then
								bestOffset, bestPoint, bestDirection = offset, point, direction
							end
						end
					end
				end
			end
		end
	end

	self._target = bestPoint
	self._targetOffset = bestOffset
	self._targetDirection = bestDirection
end

---The friction factor for the current aim, in [minFriction, 1]. Exposed so
---the crosshair can show when the assist has engaged.
function AimAssist:GetFriction(): number
	if not self._enabled or not self._targetOffset then return 1 end

	local t = 1 - (toDegrees(self._targetOffset) / self._fovDeg)
	if t <= 0 then return 1 end

	return math.lerp(self._minFriction, 1, 1 - t)
end

---Scale a look delta for friction. Direction is preserved; only magnitude
---changes, so the player stays in control of where they are pointing.
function AimAssist:ScaleLook(yaw: number, pitch: number): (number, number)
	local friction = self:GetFriction()
	if friction >= 1 then return yaw, pitch end
	return yaw * friction, pitch * friction
end

---A bounded pull toward the current target, as (yawDelta, pitchDelta) in
---radians for this frame. The sign matters: a scalar would drag the camera
---the wrong way whenever the target sits left or below. The delta is measured
---from the camera's current heading, so it stays correct while the player is
---still turning.
function AimAssist:GetPull(deltaTime: number, camera: Camera): (number, number)
	if not self._enabled or not self._targetDirection or not camera then return 0, 0 end

	local offsetDeg = toDegrees(self._targetOffset or 0)
	if offsetDeg <= 0 then return 0, 0 end

	-- Strength grows with the offset, capped, so a far miss is nudged and a
	-- near miss is closed.
	local pullRad = math.rad(math.min(offsetDeg * self._magnetism, self._maxPullDeg)) * deltaTime

	local function flatYaw(v: Vector3): number
		return math.atan2(-v.X, -v.Z)
	end

	local direction = self._targetDirection
	local look = camera.CFrame.LookVector

	-- Wrapped difference, so a target just past straight ahead reads as a
	-- small turn rather than most of a circle.
	local function wrap(a: number): number
		return (a + math.pi) % (2 * math.pi) - math.pi
	end

	local targetYaw = flatYaw(Vector3.new(direction.X, 0, direction.Z))
	local lookYaw = flatYaw(Vector3.new(look.X, 0, look.Z))

	local yawDelta = wrap(targetYaw - lookYaw)
	local pitchDelta = math.asin(math.clamp(direction.Y, -1, 1)) - math.asin(math.clamp(look.Y, -1, 1))

	return math.sign(yawDelta) * pullRad, math.sign(pitchDelta) * pullRad
end

function AimAssist:Step(deltaTime: number, camera: Camera)
	if not self._enabled or not camera then return end

	self._elapsed += deltaTime
	if self._elapsed >= SCAN_INTERVAL then
		self._elapsed = 0
		self:_scan(camera)
	end
end

function AimAssist:SetEnabled(enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._target = nil
		self._targetOffset = nil
	end
end

function AimAssist:Destroy()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function AimAssist.new(params: { [string]: any })
	local self = setmetatable({}, AimAssist)
	self._enabled = params.AimAssist == true
	self._fovDeg = params.AimAssistFov or DEFAULT_FOV_DEG
	self._maxRange = params.AimAssistRange or DEFAULT_MAX_RANGE
	self._minFriction = params.AimAssistFriction or DEFAULT_MIN_FRICTION
	self._magnetism = params.AimAssistStrength or DEFAULT_MAGNETISM
	self._maxPullDeg = params.AimAssistMaxPull or DEFAULT_MAX_PULL_DEG
	self._elapsed = 0
	self._target = nil
	self._targetOffset = nil
	return self
end

-- Return

return AimAssist

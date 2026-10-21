-- Template guard: only run when cloned into a Tool, not from ReplicatedStorage
if not script.Parent:IsA("Tool") then return end

local Workspace = game:GetService("Workspace")

local tool = script.Parent
local throwAction = tool:WaitForChild("ThrowAction") :: RemoteEvent
local throwStartAction = tool:WaitForChild("ThrowStartAction") :: RemoteEvent

local THROW_DEBOUNCE = tool:GetAttribute("ThrowDebounce") or 0
local THROW_RELEASE_FRACTION = tool:GetAttribute("ThrowReleaseFraction") or 1.0
-- When the throw animation is missing or fails to load (a bad/inaccessible asset
-- id), its track has no Length and never fires Stopped, so an animation-timed
-- release never runs -- the throw silently never fires and `throwing` stays set,
-- wedging the tool. This is the windup used to release in that case so a broken
-- animation asset can never block the throw itself.
local FALLBACK_THROW_DELAY = 0.35

local equipped = false
local throwing = false

local animationTracks: { [string]: AnimationTrack } = {}
local animationsLoaded = false

-- Animations

local function loadAnimations()
	if animationsLoaded then return end

	local char = tool.Parent
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local anim = hum:FindFirstChildOfClass("Animator")
	if not anim then return end

	local animFolder = tool:FindFirstChild("Animations")
	if not animFolder then return end

	for _, animObj in animFolder:GetChildren() do
		if not animObj:IsA("Animation") then continue end
		local track = anim:LoadAnimation(animObj)
		if animObj.Name == "Idle" then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
		else
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
		end
		animationTracks[animObj.Name] = track
	end

	animationsLoaded = true
end

local function playAnimation(name: string)
	local track = animationTracks[name]
	if not track then return end
	track:Play(0.1)
end

local function stopAnimation(name: string)
	local track = animationTracks[name]
	if not track then return end
	track:Stop(0)
end

local function stopAllAnimations()
	for _, track in animationTracks do
		track:Stop(0)
	end
end

local function unloadAnimations()
	stopAllAnimations()
	animationTracks = {}
	animationsLoaded = false
end

-- Aim

local function getAimDirection(): Vector3
	local camera = Workspace.CurrentCamera
	if not camera then return Vector3.zero end
	return camera.CFrame.LookVector
end

-- Tool Lifecycle

local function onEquipped()
	equipped = true
	throwing = false

	loadAnimations()
	playAnimation("Idle")
end

local function onUnequipped()
	equipped = false
	throwing = false

	unloadAnimations()
end

local function onActivated()
	if not equipped then return end
	if throwing then return end

	throwing = true
	throwStartAction:FireServer()
	stopAnimation("Idle")

	local released = false
	local function release()
		if released then return end
		released = true
		throwAction:FireServer(getAimDirection())
	end

	local throwTrack = animationTracks["Throw"]
	local trackLength = if throwTrack then throwTrack.Length else 0
	if throwTrack and trackLength > 0 then
		-- Animation loaded: release at the authored point of the windup, with
		-- Stopped as a backstop if it ends early.
		playAnimation("Throw")
		if THROW_RELEASE_FRACTION < 1.0 then
			task.delay(trackLength * THROW_RELEASE_FRACTION, release)
		end
		throwTrack.Stopped:Once(release)
	else
		-- No usable throw animation (absent, or a failed/still-loading asset whose
		-- Length is 0 and whose Stopped never fires): release on a fixed windup so
		-- the throw always happens. Play the track anyway in case it loads late.
		if throwTrack then
			playAnimation("Throw")
		end
		task.delay(FALLBACK_THROW_DELAY, release)
	end
end

-- Server signals throw complete (clone launched), reset state after debounce
throwAction.OnClientEvent:Connect(function()
	if THROW_DEBOUNCE > 0 then
		task.delay(THROW_DEBOUNCE, function()
			throwing = false
			if equipped then
				playAnimation("Idle")
			end
		end)
	else
		throwing = false
		if equipped then
			playAnimation("Idle")
		end
	end
end)

-- Connections

tool.Equipped:Connect(onEquipped)
tool.Unequipped:Connect(onUnequipped)
tool.Activated:Connect(onActivated)

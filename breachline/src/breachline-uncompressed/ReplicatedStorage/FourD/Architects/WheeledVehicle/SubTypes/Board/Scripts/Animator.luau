--[[
	File: Animator.luau

	Client-side rider animation driver. Loads five animations on the local
	rider's Animator and drives them from the boardRig input/state attributes
	plus the chassis velocity. Spawned/torn down by ClientController in step
	with the existing Controller + Input modules.
]]--

-- Root

local Animator = {}

-- Roblox Services

local RunService = game:GetService("RunService")

-- Dependencies

local Constants = require(script.Parent.Constants)

-- Constants

local LEAN_THRESHOLD = 0.1
local IDLE_FADE = 0.1
local LEAN_FADE = 0.2
local OLLIE_FADE = 0.05
local PUSH_FADE = 0.05
local MIN_PUSH_ACCEL = 5

local ANIMATIONS = {
	Idle = {
		Id = "rbxassetid://121957673175989",
		Priority = Enum.AnimationPriority.Action,
		Looped = true,
		FadeTime = IDLE_FADE,
	},
	LeanLeft = {
		Id = "rbxassetid://100147665867739",
		Priority = Enum.AnimationPriority.Action2,
		Looped = true,
		FadeTime = LEAN_FADE,
	},
	LeanRight = {
		Id = "rbxassetid://87043470836849",
		Priority = Enum.AnimationPriority.Action2,
		Looped = true,
		FadeTime = LEAN_FADE,
	},
	Ollie = {
		Id = "rbxassetid://113235022841987",
		Priority = Enum.AnimationPriority.Action3,
		Looped = false,
		FadeTime = OLLIE_FADE,
	},
	Push = {
		Id = "rbxassetid://108523087985542",
		Priority = Enum.AnimationPriority.Action4,
		Looped = false,
		FadeTime = PUSH_FADE,
	},
}

-- Local Functions

local function resolveAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	return humanoid:FindFirstChildOfClass("Animator")
end

local function loadTracks(animator: Animator): { [string]: AnimationTrack }
	local tracks: { [string]: AnimationTrack } = {}
	for name, def in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = def.Id
		local track = animator:LoadAnimation(animation)
		track.Priority = def.Priority
		track.Looped = def.Looped
		tracks[name] = track
	end

	return tracks
end

local function destroyTracks(tracks: { [string]: AnimationTrack })
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
end

local function setLoopedTrackPlaying(track: AnimationTrack, shouldPlay: boolean, fade: number)
	if shouldPlay and not track.IsPlaying then
		track:Play(fade)
	elseif not shouldPlay and track.IsPlaying then
		track:Stop(fade)
	end
end

-- Public Functions

function Animator.start(boardRig: Model, ownerCharacter: Model): () -> ()
	local animator = resolveAnimator(ownerCharacter)
	if not animator then
		return function() end
	end

	local chassis = boardRig:WaitForChild("Chassis")

	local tracks = loadTracks(animator)
	tracks.Idle:Play(IDLE_FADE)

	local lastForwardSpeed = 0

	local heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		if not boardRig.Parent then return end

		local steer = boardRig:GetAttribute(Constants.STEERING_INPUT_ATTRIBUTE) or 0
		local throttle = boardRig:GetAttribute(Constants.THROTTLE_INPUT_ATTRIBUTE) or 0
		local airborne = boardRig:GetAttribute(Constants.AIRBORNE_ATTRIBUTE) == true

		setLoopedTrackPlaying(tracks.LeanLeft, steer < -LEAN_THRESHOLD, LEAN_FADE)
		setLoopedTrackPlaying(tracks.LeanRight, steer > LEAN_THRESHOLD, LEAN_FADE)

		local forwardSpeed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		local forwardAccel = if dt > 0 then (forwardSpeed - lastForwardSpeed) / dt else 0
		lastForwardSpeed = forwardSpeed

		if throttle <= 0 or airborne then return end
		if forwardAccel < MIN_PUSH_ACCEL then return end
		if tracks.Push.IsPlaying then return end

		tracks.Push:Play(PUSH_FADE)
	end)

	local ollieConn = boardRig:GetAttributeChangedSignal(Constants.LAST_OLLIE_ATTRIBUTE):Connect(function()
		if tracks.Ollie.IsPlaying then
			tracks.Ollie:Stop(0)
		end

		tracks.Ollie:Play(OLLIE_FADE)
	end)

	return function()
		heartbeatConn:Disconnect()
		ollieConn:Disconnect()
		destroyTracks(tracks)
	end
end

-- Return

return Animator

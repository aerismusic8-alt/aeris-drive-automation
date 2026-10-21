-- GENERATED WRAPPER around upstream MeleeToolClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
if not script.Parent:IsA("Tool") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Common = FourD.Common
local GetCharacterFromPart = require(Common.getCharacterFromPart)
local IsDamageable = require(Common.isDamageable)

local Tool: Tool = script.Parent
local Handle: BasePart = Tool:WaitForChild("Handle") :: BasePart
local SwingAction = Tool:WaitForChild("SwingAction") :: RemoteEvent
local HitRequest = Tool:WaitForChild("HitRequest") :: RemoteEvent

local SWING_DEBOUNCE = Tool:GetAttribute("SwingDebounce") or 0.5
local CHAIN_SWING_THRESHOLD = Tool:GetAttribute("ChainSwingThreshold") or 1.0
local CHAIN_SWING_ENABLED = Tool:GetAttribute("ChainSwingEnabled") or false
local SWING_SPEED = Tool:GetAttribute("SwingSpeed") or 1
local HIT_CHECK_INTERVAL = Tool:GetAttribute("HitCheckInterval") or 1

local SWING_ACTIVE_DURATION = 0.4
local HITBOX_SCALE = 1.15
local ANIMATION_PRIORITY = Enum.AnimationPriority.Action4

local equipped = false
local debounceActive = false
local lastSwingTime = -math.huge
local chainPending = false

local swingActive = false
local frameCounter = 0
local hitThisSwing: { [Humanoid]: boolean } = {}
local hitCheckConnection: RBXScriptConnection? = nil

local animationTracks: { [string]: AnimationTrack } = {}
local animationsLoaded = false

local isLocalOwner = false

local function resolveOwnerPlayer(): Player?
	local parent = Tool.Parent
	if not parent then return nil end

	local player = Players:GetPlayerFromCharacter(parent)
	if player then return player end

	if parent:IsA("Backpack") then
		return parent.Parent :: Player
	end

	return nil
end

local function resolveHitboxSource(): BasePart
	local damagePartRef = Tool:FindFirstChild("DamagePartRef")
	if damagePartRef and damagePartRef:IsA("ObjectValue") then
		local value = damagePartRef.Value
		if value and value:IsA("BasePart") then
			return value
		end
	end

	return Handle
end

local function loadAnimations(): ()
	if animationsLoaded then return end

	local char = Tool.Parent
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local anim = hum:FindFirstChildOfClass("Animator")
	if not anim then return end

	local animFolder = Tool:FindFirstChild("Animations")
	if not animFolder then return end

	for _, animObj in animFolder:GetChildren() do
		if not animObj:IsA("Animation") then continue end
		local track = anim:LoadAnimation(animObj)
		if animObj.Name == "Equip" then
			track.Priority = Enum.AnimationPriority.Action2
			track.Looped = false
		elseif animObj.Name == "Idle" then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
		else
			track.Priority = ANIMATION_PRIORITY
			track.Looped = false
		end
		animationTracks[animObj.Name] = track
	end

	animationsLoaded = true
end

local function playAnimation(name: string, speed: number?, fadeTime: number?): ()
	local track = animationTracks[name]
	if not track then return end
	track:Play(fadeTime or 0.05)
	if speed then track:AdjustSpeed(speed) end
end

local function stopAnimation(name: string, fadeTime: number?): ()
	local track = animationTracks[name]
	if not track then return end
	track:Stop(fadeTime or 0)
end

local function stopAllAnimations(): ()
	for _, track in animationTracks do
		track:Stop(0)
	end
end

local function unloadAnimations(): ()
	stopAllAnimations()
	animationTracks = {}
	animationsLoaded = false
end

local function startDebounce(): ()
	debounceActive = true
	task.delay(SWING_DEBOUNCE, function()
		debounceActive = false
	end)
end

local function runHitCheck(): ()
	local localPlayer = Players.LocalPlayer
	local localChar = localPlayer and localPlayer.Character
	if not localChar then return end

	local source = resolveHitboxSource()
	if not source.Parent then return end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { localChar }

	local hitboxSize = source.Size * HITBOX_SCALE
	local parts = workspace:GetPartBoundsInBox(source.CFrame, hitboxSize, overlapParams)

	for _, part in parts do
		local character = GetCharacterFromPart(part)
		if not character then continue end
		if character == localChar then continue end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then continue end
		if hitThisSwing[humanoid] then continue end
		if not IsDamageable(part) then continue end

		hitThisSwing[humanoid] = true
		HitRequest:FireServer(humanoid, part)
	end
end

local function startSwingWindow(): ()
	swingActive = true
	frameCounter = 0
	hitThisSwing = {}

	if hitCheckConnection then
		hitCheckConnection:Disconnect()
		hitCheckConnection = nil
	end

	hitCheckConnection = RunService.Heartbeat:Connect(function()
		if not swingActive then return end

		local shouldCheck = (frameCounter % HIT_CHECK_INTERVAL) == 0
		frameCounter += 1
		if not shouldCheck then return end

		runHitCheck()
	end)

	task.delay(SWING_ACTIVE_DURATION / SWING_SPEED, function()
		swingActive = false
		if hitCheckConnection then
			hitCheckConnection:Disconnect()
			hitCheckConnection = nil
		end
	end)
end

local function doFirstSwing(): ()
	stopAnimation("Idle", 0.05)
	playAnimation("FirstSwing", SWING_SPEED)
	SwingAction:FireServer("first")
	startSwingWindow()

	lastSwingTime = os.clock()
	chainPending = CHAIN_SWING_ENABLED

	if not CHAIN_SWING_ENABLED then
		startDebounce()
	end

	local track = animationTracks["FirstSwing"]
	if track then
		track.Stopped:Once(function()
			if equipped then
				playAnimation("Idle")
			end
		end)
	end
end

local function doSecondSwing(): ()
	stopAnimation("Idle")
	stopAnimation("FirstSwing", 0.05)
	playAnimation("SecondSwing", SWING_SPEED)
	SwingAction:FireServer("second")
	startSwingWindow()

	chainPending = false
	startDebounce()

	local track = animationTracks["SecondSwing"]
	if track then
		track.Stopped:Once(function()
			if equipped then
				playAnimation("Idle")
			end
		end)
	end
end

local function onEquipped(): ()
	isLocalOwner = resolveOwnerPlayer() == Players.LocalPlayer
	if not isLocalOwner then return end

	equipped = true
	debounceActive = false
	lastSwingTime = -math.huge
	chainPending = false

	loadAnimations()
	playAnimation("Equip")
	playAnimation("Idle")
end

local function onUnequipped(): ()
	if not isLocalOwner then return end

	equipped = false
	debounceActive = false
	chainPending = false
	swingActive = false

	if hitCheckConnection then
		hitCheckConnection:Disconnect()
		hitCheckConnection = nil
	end

	unloadAnimations()
end

local function onActivated(): ()
	if not isLocalOwner then return end
	if not equipped then return end
	if debounceActive then return end

	if not CHAIN_SWING_ENABLED then
		doFirstSwing()
		return
	end

	local timeSinceFirst = os.clock() - lastSwingTime
	if chainPending and timeSinceFirst <= CHAIN_SWING_THRESHOLD then
		doSecondSwing()
	else
		doFirstSwing()
	end
end

Tool.Equipped:Connect(onEquipped)
Tool.Unequipped:Connect(onUnequipped)
Tool.Activated:Connect(onActivated)

end
=/
-- GENERATED WRAPPER around upstream TowableInput.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
if not script.Parent:IsA("Model") then return end

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Keybinds = require(ReplicatedStorage.FourD.Common.Keybinds)

local RECEIVER_TAG = "TowHitchReceiver"
local MAX_ATTACH_DISTANCE = 7.5
local INDICATOR_DISPLAY_RANGE = 40
local INDICATOR_COLOR_IN_RANGE = Color3.new(0, 1, 0)
local INDICATOR_COLOR_OUT_RANGE = Color3.new(1, 0, 0)
local INDICATOR_PULSE_MIN = 0.75
local INDICATOR_PULSE_MAX = 0.9
local INDICATOR_PULSE_RATE = 0.0025
local INDICATOR_PULSE_FPS = 60
local INDICATOR_SCAN_INTERVAL = 0.1
local RECEIVER_IN_USE_ATTRIBUTE = "HitchInUse"

local model = script.Parent
local player = Players.LocalPlayer

local maxAttachDistance = model:GetAttribute("HitchMaxAttachDistance") or MAX_ATTACH_DISTANCE

local toggleEvent = model:FindFirstChild("HitchToggleEvent")
if not toggleEvent or not toggleEvent:IsA("RemoteEvent") then return end

local seatRef = model:FindFirstChild("Towable_DriverSeatRef")
local seat = if seatRef and seatRef:IsA("ObjectValue") then seatRef.Value else nil
seat = seat or model:FindFirstChildWhichIsA("VehicleSeat", true)
if not seat then
	-- Dispatched from a scan, so this body can run before the rest
	-- of the model replicates. Returning here is permanent: the
	-- dispatcher starts a host once and never revisits it.
	local seatDeadline = os.clock() + 10
	repeat
		task.wait()
		seat = seat or model:FindFirstChildWhichIsA("VehicleSeat", true)
	until seat or os.clock() >= seatDeadline
end
if not seat then return end

local hitchAttachment = model:FindFirstChild("HitchAttachment", true)

local bindHandle = nil

local function onToggle(state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		toggleEvent:FireServer()
	end

	return Enum.ContextActionResult.Sink
end

local function isLocalDriver(): boolean
	local occupant = seat.Occupant
	if not occupant then return false end
	return occupant.Parent == player.Character
end

local function refresh()
	if isLocalDriver() then
		if not bindHandle then
			bindHandle = Keybinds.bindActions("Towable", { ToggleHitch = onToggle }, model, { CreateTouchButton = true })
		end
	elseif bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
	end
end

local indicatorFolder = nil
local activeBalls: { [Attachment]: BasePart } = {}
local pulseTransparency = INDICATOR_PULSE_MIN
local pulseDirection = 1
local scanAccumulator = 0

local function getIndicatorFolder(): Instance
	if not indicatorFolder or not indicatorFolder.Parent then
		indicatorFolder = Instance.new("Folder")
		indicatorFolder.Name = "Towable_ReceiverIndicators"
		indicatorFolder.Parent = workspace
	end

	return indicatorFolder
end

local function makeBall(receiverAtt: Attachment): BasePart
	local ball = Instance.new("Part")
	ball.Name = "Towable_ReceiverIndicator"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(maxAttachDistance, maxAttachDistance, maxAttachDistance)
	ball.Material = Enum.Material.Neon
	ball.Transparency = 0.75
	ball.Reflectance = 0
	ball.CastShadow = false
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.Massless = false
	ball.Anchored = true
	ball.CFrame = receiverAtt.WorldCFrame

	ball.Parent = getIndicatorFolder()
	return ball
end

local function clearIndicators()
	for att, ball in pairs(activeBalls) do
		ball:Destroy()
		activeBalls[att] = nil
	end

	if indicatorFolder then
		indicatorFolder:Destroy()
		indicatorFolder = nil
	end
end

local function updateIndicators(dt: number)
	if not hitchAttachment or not isLocalDriver() or model:GetAttribute("hitchConnected") then
		clearIndicators()
		return
	end

	local step = INDICATOR_PULSE_RATE * dt * INDICATOR_PULSE_FPS
	pulseTransparency += pulseDirection * step
	if pulseTransparency >= INDICATOR_PULSE_MAX then
		pulseTransparency = INDICATOR_PULSE_MAX
		pulseDirection = -1
	elseif pulseTransparency <= INDICATOR_PULSE_MIN then
		pulseTransparency = INDICATOR_PULSE_MIN
		pulseDirection = 1
	end

	local hitchPos = hitchAttachment.WorldCFrame.Position

	for att, ball in pairs(activeBalls) do
		if not att.Parent then
			ball:Destroy()
			activeBalls[att] = nil
			continue
		end

		local dist = (att.WorldPosition - hitchPos).Magnitude
		ball.CFrame = att.WorldCFrame
		ball.Color = if dist <= maxAttachDistance then INDICATOR_COLOR_IN_RANGE else INDICATOR_COLOR_OUT_RANGE
		ball.Transparency = pulseTransparency
	end

	scanAccumulator += dt
	if scanAccumulator < INDICATOR_SCAN_INTERVAL then return end
	scanAccumulator = 0

	local seen = {}

	for _, receiverAtt in ipairs(CollectionService:GetTagged(RECEIVER_TAG)) do
		if not receiverAtt:IsA("Attachment") then continue end
		if receiverAtt:IsDescendantOf(model) then continue end
		if not receiverAtt:IsDescendantOf(workspace) then continue end
		if receiverAtt:GetAttribute(RECEIVER_IN_USE_ATTRIBUTE) then continue end

		local host = receiverAtt.Parent
		if not host or not host:IsA("BasePart") then continue end

		local dist = (receiverAtt.WorldPosition - hitchPos).Magnitude
		if dist > INDICATOR_DISPLAY_RANGE then continue end

		seen[receiverAtt] = true
		local ball = activeBalls[receiverAtt]
		if not ball or not ball.Parent then
			ball = makeBall(receiverAtt)
			activeBalls[receiverAtt] = ball
			ball.CFrame = receiverAtt.WorldCFrame
			ball.Color = if dist <= maxAttachDistance then INDICATOR_COLOR_IN_RANGE else INDICATOR_COLOR_OUT_RANGE
			ball.Transparency = pulseTransparency
		end
	end

	for att, ball in pairs(activeBalls) do
		if not seen[att] then
			ball:Destroy()
			activeBalls[att] = nil
		end
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(refresh)
RunService.Heartbeat:Connect(updateIndicators)

model.Destroying:Connect(function()
	clearIndicators()
	if bindHandle then
		bindHandle:Destroy()
		bindHandle = nil
	end
end)

refresh()

end

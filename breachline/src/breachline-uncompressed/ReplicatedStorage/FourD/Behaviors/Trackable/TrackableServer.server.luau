if not script.Parent:IsA("Model") then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trackable = require(ReplicatedStorage:WaitForChild("FourD").Behaviors.Trackable.makeFunctional)

local SYNC_INTERVAL = 0.2
local SCAN_INTERVAL = 0.5
local COAST_FRICTION = 0.05
local IDLE_DECAY = 2
local PARK_DECAY = 4
local END_STOP_EPSILON = 0.01

local model = script.Parent
local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
if not primaryPart then return end
model.PrimaryPart = primaryPart

local trackData = nil
local position = 0
local speed = 0
local throttle = 0
local scanAccum = 0
local syncAccum = SYNC_INTERVAL
local autoWaiting = false
local autoWaitRemaining = 0
local autoDeparting = false

local trackValue = Instance.new("ObjectValue")
trackValue.Name = "Trackable_Track"
trackValue.Parent = model

local leaderValue = Instance.new("ObjectValue")
leaderValue.Name = "Trackable_Leader"
leaderValue.Parent = model

local seat = model:FindFirstChildWhichIsA("VehicleSeat", true) or model:FindFirstChildWhichIsA("Seat", true)

local carAnchors = {}
if model:GetAttribute("trackMultiCar") then
	for _, child in ipairs(model:GetChildren()) do
		local carOffset = child:GetAttribute("trackCarOffset")
		if child:IsA("Model") and typeof(carOffset) == "number" then
			local anchor = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart", true)
			if anchor then
				table.insert(carAnchors, { Anchor = anchor, Offset = carOffset })
			end
		end
	end

	table.sort(carAnchors, function(a, b)
		return a.Offset < b.Offset
	end)
end

if #carAnchors == 0 then
	carAnchors = { { Anchor = primaryPart, Offset = 0 } }
end

local function anchorCars()
	for _, car in ipairs(carAnchors) do
		car.Anchor.Anchored = true
	end
end

local function writeSnapshot()
	model:SetAttribute("trackPosition", position)
	model:SetAttribute("trackSpeed", speed)
	model:SetAttribute("trackSyncTime", workspace:GetServerTimeNow())
	if trackData then
		for _, car in ipairs(carAnchors) do
			local carPosition = Trackable.wrapPosition(trackData, position - car.Offset)
			car.Anchor.CFrame = Trackable.sampleTrack(trackData, carPosition)
		end
	end
end

local function startAutoWait()
	position = 0
	speed = 0
	autoDeparting = false
	autoWaiting = true
	autoWaitRemaining = model:GetAttribute("autoModeWaitTime") or 5
	syncAccum = 0
	writeSnapshot()
end

local function enterTrack(track: Instance, enterPosition: number)
	trackData = Trackable.buildTrackData(track, {
		Smoothing = model:GetAttribute("trackSmoothing") ~= false,
		FlipDirection = model:GetAttribute("flipDirection") == true,
	})
	if not trackData then return end

	position = Trackable.wrapPosition(trackData, enterPosition)
	speed = 0
	anchorCars()
	trackValue.Value = track
	model:SetAttribute("trackActive", true)
	syncAccum = SYNC_INTERVAL
	writeSnapshot()

	if model:GetAttribute("autoMode") == true then
		startAutoWait()
	end
end

local function tryEnterNearbyTrack()
	local enterDistance = model:GetAttribute("trackEnterDistance") or 12
	local candidate = Trackable.findNearestTrack(primaryPart.Position, math.max(enterDistance * 4, 50))
	if not candidate then return end

	local candidateData = Trackable.buildTrackData(candidate, {
		Smoothing = model:GetAttribute("trackSmoothing") ~= false,
		FlipDirection = model:GetAttribute("flipDirection") == true,
	})
	if not candidateData then return end

	local nearestPos, dist = Trackable.findNearestPosition1D(candidateData.Waypoints, primaryPart.Position)
	if dist > enterDistance then return end

	enterTrack(candidate, nearestPos)
end

local function findReceiverAttachment(): Attachment?
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Attachment") and desc.Name == "HitchReceiverAttachment" then
			return desc
		end
	end

	return nil
end

local function onTowerChanged(towerModel: Instance?)
	if not towerModel then
		if leaderValue.Value then
			local leader = leaderValue.Value
			local offset = model:GetAttribute("trackOffset") or 0
			if trackData and leader and leader:GetAttribute("trackActive") then
				position = Trackable.wrapPosition(trackData, (leader:GetAttribute("trackPosition") or 0) - offset)
				speed = leader:GetAttribute("trackSpeed") or 0
			end

			leaderValue.Value = nil
			model:SetAttribute("trackOffset", 0)
		end

		return
	end

	if not towerModel:GetAttribute("trackActive") then return end

	local towerTrackValue = towerModel:FindFirstChild("Trackable_Track")
	local towerTrack = if towerTrackValue and towerTrackValue:IsA("ObjectValue") then towerTrackValue.Value else nil
	if not towerTrack then return end

	if not trackData or trackValue.Value ~= towerTrack then
		local candidateData = Trackable.buildTrackData(towerTrack, { Smoothing = model:GetAttribute("trackSmoothing") ~= false })
		if not candidateData then return end

		local nearestPos = Trackable.findNearestPosition1D(candidateData.Waypoints, primaryPart.Position)
		enterTrack(towerTrack, nearestPos)
		if not trackData then return end
	end

	local towerPosition = towerModel:GetAttribute("trackPosition") or 0
	local offset = Trackable.deltaPosition(trackData, towerPosition, position)
	leaderValue.Value = towerModel
	model:SetAttribute("trackOffset", offset)
end

local function watchReceiver()
	local receiver = findReceiverAttachment()
	if not receiver then return end

	local existing = receiver:FindFirstChild("Towable_TowerModel")
	if existing and existing:IsA("ObjectValue") then
		onTowerChanged(existing.Value)
	end

	receiver.ChildAdded:Connect(function(child)
		if child.Name == "Towable_TowerModel" and child:IsA("ObjectValue") then
			onTowerChanged(child.Value)
		end
	end)

	receiver.ChildRemoved:Connect(function(child)
		if child.Name == "Towable_TowerModel" then
			onTowerChanged(nil)
		end
	end)
end

local function integrate(dt: number)
	if not trackData then return end

	local maxTrackSpeed = model:GetAttribute("maxTrackSpeed") or 40
	local trackAcceleration = model:GetAttribute("trackAcceleration") or 20
	local useGravity = model:GetAttribute("useGravity") == true
	local liftSpeed = model:GetAttribute("liftSpeed") or 8
	local targetSpeed = model:GetAttribute("targetTrackSpeed")
	local autoMode = model:GetAttribute("autoMode") == true
	local parked = false

	if not autoMode then
		autoWaiting = false
		autoDeparting = false
	elseif autoWaiting then
		autoWaitRemaining -= dt
		position = 0
		speed = 0
		if autoWaitRemaining <= 0 then
			autoWaiting = false
			if model:GetAttribute("autoModeStartType") == "launch" then
				speed = liftSpeed
			else
				autoDeparting = true
			end

			syncAccum = 0
			writeSnapshot()
		end

		return
	end

	if typeof(targetSpeed) == "number" then
		if speed < targetSpeed then
			speed = math.min(targetSpeed, speed + trackAcceleration * dt)
		elseif speed > targetSpeed then
			speed = math.max(targetSpeed, speed - trackAcceleration * dt)
		end
	elseif model:GetAttribute("requireDriver") == true and not autoMode and not (seat and seat.Occupant) then
		parked = true
		speed *= math.max(0, 1 - PARK_DECAY * dt)
	else
		local effectiveThrottle = if autoMode then 0 else throttle
		local accel = effectiveThrottle * trackAcceleration
		if autoDeparting then
			accel = math.max(accel, trackAcceleration)
		end

		if useGravity then
			local direction = Trackable.getTrackDirection(trackData, position)
			accel -= workspace.Gravity * direction.Y
			speed *= math.max(0, 1 - COAST_FRICTION * dt)
		elseif effectiveThrottle == 0 and not autoDeparting then
			speed *= math.max(0, 1 - IDLE_DECAY * dt)
		end

		speed += accel * dt
	end

	if not parked and Trackable.isInLift(trackData, position) and speed < liftSpeed then
		speed = liftSpeed
	end

	if autoDeparting then
		if speed >= liftSpeed or Trackable.isInLift(trackData, position) then
			autoDeparting = false
		elseif speed < 0 then
			speed = 0
		end
	end

	if model:GetAttribute("noRollback") == true and speed < 0 then
		speed = 0
	end

	if maxTrackSpeed > 0 then
		speed = math.clamp(speed, -maxTrackSpeed, maxTrackSpeed)
	end

	local previousPosition = position
	position += speed * dt

	if trackData.Looped then
		position = Trackable.wrapPosition(trackData, position)
		local crossedForward = speed > 0 and position < previousPosition
		local crossedBackward = speed < 0 and position > previousPosition
		if autoMode and (crossedForward or crossedBackward) then
			startAutoWait()
		end
	elseif position <= 0 then
		position = 0
		if speed < 0 then speed = 0 end

		if autoMode and previousPosition > 0 then
			startAutoWait()
		end
	elseif position >= trackData.Length - END_STOP_EPSILON then
		position = trackData.Length
		if speed > 0 then speed = 0 end
	end
end

local throttleEvent = model:FindFirstChild("TrackThrottleEvent")
if throttleEvent and throttleEvent:IsA("RemoteEvent") then
	throttleEvent.OnServerEvent:Connect(function(firingPlayer: Player, value)
		if typeof(value) ~= "number" then return end
		if not seat then return end

		local occupant = seat.Occupant
		local character = firingPlayer.Character
		if not occupant or not character or occupant.Parent ~= character then return end

		throttle = math.clamp(math.sign(value), -1, 1)
	end)
end

if seat then
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then throttle = 0 end
	end)
end

watchReceiver()

RunService.Heartbeat:Connect(function(dt)
	if model:GetAttribute("driveMode") ~= "track" then return end

	if not model:GetAttribute("trackActive") then
		scanAccum += dt
		if scanAccum >= SCAN_INTERVAL then
			scanAccum = 0
			tryEnterNearbyTrack()
		end

		return
	end

	local leader = leaderValue.Value
	if leader and leader:GetAttribute("trackActive") and trackData then
		local offset = model:GetAttribute("trackOffset") or 0
		position = Trackable.wrapPosition(trackData, (leader:GetAttribute("trackPosition") or 0) - offset)
		speed = leader:GetAttribute("trackSpeed") or 0
	else
		integrate(dt)
	end

	syncAccum += dt
	if syncAccum >= SYNC_INTERVAL then
		syncAccum = 0
		writeSnapshot()
	end
end)

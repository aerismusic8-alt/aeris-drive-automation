-- GENERATED WRAPPER around upstream TrackableRunner.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
if not script.Parent:IsA("Model") then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Trackable = require(ReplicatedStorage:WaitForChild("FourD").Behaviors.Trackable.makeFunctional)

local SNAP_THRESHOLD = 8
local CORRECTION_RATE = 4
local MAX_CHAIN_DEPTH = 16
local INPUT_SEND_INTERVAL = 0.1

local model = script.Parent
local player = Players.LocalPlayer

-- The server assembles this model at runtime, so the parts, seat, remote and
-- car attributes can arrive after this client script starts. Resolving them
-- only once loses that replication race and leaves the cart moving at the
-- server's 0.2-second snapshot rate. Streaming can also remove an anchor after
-- it was found, so validate and resolve these references as needed.
local carAnchors = {}
local anchorsAreMultiCar = false
local seat = nil
local throttleEvent = nil

local function findSeat()
	if seat and seat:IsDescendantOf(model) then return seat end
	seat = model:FindFirstChildWhichIsA("VehicleSeat", true) or model:FindFirstChildWhichIsA("Seat", true)
	return seat
end

local function findThrottleEvent()
	if throttleEvent and throttleEvent:IsDescendantOf(model) then return throttleEvent end
	local found = model:FindFirstChild("TrackThrottleEvent")
	throttleEvent = if found and found:IsA("RemoteEvent") then found else nil
	return throttleEvent
end

local function resolveCarAnchors(): boolean
	local multiCar = model:GetAttribute("trackMultiCar") == true
	local resolved = {}

	if multiCar then
		for _, child in ipairs(model:GetChildren()) do
			local carOffset = child:GetAttribute("trackCarOffset")
			if child:IsA("Model") and typeof(carOffset) == "number" then
				local anchor = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart", true)
				if anchor then
					table.insert(resolved, { Anchor = anchor, Offset = carOffset })
				end
			end
		end

		table.sort(resolved, function(a, b)
			return a.Offset < b.Offset
		end)
	else
		local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if primaryPart then
			resolved = { { Anchor = primaryPart, Offset = 0 } }
		end
	end

	if #resolved == 0 then return false end

	carAnchors = resolved
	anchorsAreMultiCar = multiCar
	return true
end

local function carAnchorsReady(): boolean
	if #carAnchors == 0 then return false end
	if anchorsAreMultiCar ~= (model:GetAttribute("trackMultiCar") == true) then return false end

	for _, car in ipairs(carAnchors) do
		if not car.Anchor:IsDescendantOf(model) then return false end
	end

	return true
end

local trackData = nil
local cachedTrack = nil
local localHeadPos = nil
local lastSentThrottle = 0
local lastSendTime = 0

local function refreshTrackData()
	local trackValue = model:FindFirstChild("Trackable_Track")
	local track = if trackValue and trackValue:IsA("ObjectValue") then trackValue.Value else nil
	if not track then
		trackData = nil
		cachedTrack = nil
		return
	end

	if track == cachedTrack and trackData then return end

	trackData = Trackable.buildTrackData(track, {
		Smoothing = model:GetAttribute("trackSmoothing") ~= false,
		FlipDirection = model:GetAttribute("flipDirection") == true,
	})
	cachedTrack = track
	localHeadPos = nil
end

local function resolveHead(): (Instance, number)
	local current: Instance = model
	local cumulativeOffset = 0
	local visited = {}

	for _ = 1, MAX_CHAIN_DEPTH do
		visited[current] = true
		local leaderValue = current:FindFirstChild("Trackable_Leader")
		local leader = if leaderValue and leaderValue:IsA("ObjectValue") then leaderValue.Value else nil
		if not leader or visited[leader] then break end
		if not leader:GetAttribute("trackActive") then break end

		cumulativeOffset += current:GetAttribute("trackOffset") or 0
		current = leader
	end

	return current, cumulativeOffset
end

local function isLocalOccupant(): boolean
	local currentSeat = findSeat()
	if not currentSeat then return false end
	local occupant = currentSeat.Occupant
	if not occupant then return false end
	return occupant.Parent == player.Character
end

local function sendThrottle(now: number)
	local event = findThrottleEvent()
	if not event then return end

	local desired = 0
	local currentSeat = findSeat()
	if currentSeat and currentSeat:IsA("VehicleSeat") and isLocalOccupant() then
		desired = math.sign(currentSeat.Throttle)
	end

	if desired == lastSentThrottle then return end
	if now - lastSendTime < INPUT_SEND_INTERVAL then return end

	lastSentThrottle = desired
	lastSendTime = now
	event:FireServer(desired)
end

RunService.Heartbeat:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	sendThrottle(now)

	if model:GetAttribute("trackActive") ~= true then
		localHeadPos = nil
		return
	end

	if not carAnchorsReady() and not resolveCarAnchors() then
		localHeadPos = nil
		return
	end

	refreshTrackData()
	if not trackData then return end

	local head, cumulativeOffset = resolveHead()
	local headPos = head:GetAttribute("trackPosition") or 0
	local headSpeed = head:GetAttribute("trackSpeed") or 0
	local syncTime = head:GetAttribute("trackSyncTime") or now

	local target = Trackable.wrapPosition(trackData, headPos + headSpeed * (now - syncTime))

	if localHeadPos == nil then
		localHeadPos = target
	else
		localHeadPos += headSpeed * dt
		local err = Trackable.deltaPosition(trackData, target, localHeadPos)
		if math.abs(err) > SNAP_THRESHOLD then
			localHeadPos = target
		else
			localHeadPos += err * math.min(1, CORRECTION_RATE * dt)
		end

		localHeadPos = Trackable.wrapPosition(trackData, localHeadPos)
	end

	local myPos = Trackable.wrapPosition(trackData, localHeadPos - cumulativeOffset)
	for _, car in ipairs(carAnchors) do
		local carPosition = Trackable.wrapPosition(trackData, myPos - car.Offset)
		car.Anchor.CFrame = Trackable.sampleTrack(trackData, carPosition)
	end
end)

end

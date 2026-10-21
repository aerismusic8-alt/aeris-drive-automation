--[[
	File: Trackable/makeFunctional.luau

	Trackable behavior. CFrame waypoint track following.

	Core principle: a 1D position (number) maps to a 3D CFrame on the track
	line. Tracks are developer-authored under workspace.Tracks as Folder or
	Model instances whose children are numbered Attachment or BasePart
	waypoints.

	Simulation is server-authoritative (TrackableServer integrates scalar
	position/speed and snapshots it to attributes) while animation is
	client-side (TrackableRunner pivots the anchored assembly every frame
	from snapshots).

	Waypoint names containing "lift" mark chain-lift segments. A track loops
	when its container has a Looped attribute set true, or when its first and
	last waypoints nearly coincide.

	Public API:
		Trackable.findNearestTrack / getWaypoints
		Trackable.getTrackLength / isLooped
		Trackable.resampleWaypoints / buildTrackData
		Trackable.wrapPosition / deltaPosition
		Trackable.sampleTrack / getTrackDirection / isInLift
		Trackable.getCFrameAtPosition / findNearestPosition1D
		Trackable.setup
]]--

-- Root

local Trackable = {}

-- Constants

local LOOP_AUTO_CLOSE_DISTANCE = 3
local DEFAULT_SMOOTHING_SPACING = 3
local DEFAULT_MAX_TRACK_SPEED = 40
local DEFAULT_TRACK_ACCELERATION = 20
local DEFAULT_LIFT_SPEED = 8
local DEFAULT_ENTER_DISTANCE = 12
local DEFAULT_AUTO_MODE_WAIT_TIME = 5
local MIN_SEGMENT_LENGTH = 0.001
local DEFAULT_CAR_GAP = 0.5

-- Types

export type Waypoint = {
	Name: string,
	CFrame: CFrame,
	Position: Vector3,
	IsLift: boolean,
}

export type TrackData = {
	Track: Instance,
	Waypoints: { Waypoint },
	Cumulative: { number },
	Length: number,
	Looped: boolean,
	LiftRanges: { { Start: number, Stop: number } },
}

export type TrackableHandle = {
	Model: Model,
	SetTargetSpeed: (self: TrackableHandle, speed: number?) -> (),
	GetTargetSpeed: (self: TrackableHandle) -> number?,
	SetRequireDriver: (self: TrackableHandle, required: boolean) -> (),
	GetRequireDriver: (self: TrackableHandle) -> boolean,
	SetMaxSpeed: (self: TrackableHandle, maxSpeed: number) -> (),
	SetAcceleration: (self: TrackableHandle, acceleration: number) -> (),
	GetSpeed: (self: TrackableHandle) -> number,
	GetPosition: (self: TrackableHandle) -> number,
	IsOnTrack: (self: TrackableHandle) -> boolean,
}

-- Local Functions

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function findSegment(trackData: TrackData, position1D: number): number
	local cumulative = trackData.Cumulative
	local low, high = 1, #cumulative - 1
	while low < high do
		local mid = math.floor((low + high + 1) / 2)
		if cumulative[mid] <= position1D then
			low = mid
		else
			high = mid - 1
		end
	end

	return math.clamp(low, 1, #cumulative - 1)
end

local function flipWaypoints(waypoints: { Waypoint }, looped: boolean): { Waypoint }
	local count = #waypoints
	local turn = CFrame.Angles(0, math.pi, 0)
	local flipped: { Waypoint } = {}

	for i = 1, count do
		local source = if looped then waypoints[((count - i + 1) % count) + 1] else waypoints[count - i + 1]
		table.insert(flipped, {
			Name = source.Name,
			CFrame = source.CFrame * turn,
			Position = source.Position,
			IsLift = source.IsLift,
		})
	end

	return flipped
end

local function makeHandle(assembledModel: Model): TrackableHandle
	local handle = {}
	handle.Model = assembledModel

	function handle:SetTargetSpeed(speed: number?)
		assembledModel:SetAttribute("targetTrackSpeed", speed)
	end

	function handle:GetTargetSpeed(): number?
		return assembledModel:GetAttribute("targetTrackSpeed") :: number?
	end

	function handle:SetRequireDriver(required: boolean)
		assembledModel:SetAttribute("requireDriver", required == true)
	end

	function handle:GetRequireDriver(): boolean
		return assembledModel:GetAttribute("requireDriver") == true
	end

	function handle:SetMaxSpeed(maxSpeed: number)
		assembledModel:SetAttribute("maxTrackSpeed", maxSpeed)
	end

	function handle:SetAcceleration(acceleration: number)
		assembledModel:SetAttribute("trackAcceleration", acceleration)
	end

	function handle:GetSpeed(): number
		return (assembledModel:GetAttribute("trackSpeed") :: number?) or 0
	end

	function handle:GetPosition(): number
		return (assembledModel:GetAttribute("trackPosition") :: number?) or 0
	end

	function handle:IsOnTrack(): boolean
		return assembledModel:GetAttribute("trackActive") == true
	end

	return handle
end

-- Public Functions

---Scans workspace.Tracks for the track container with a waypoint closest to
---`worldPosition`. Containers with fewer than two waypoints are skipped.
---@param worldPosition -- World-space search origin.
---@param maxDistance -- Search radius in studs; defaults to 100.
---@return track -- Closest track container, or nil if none in range.
function Trackable.findNearestTrack(worldPosition: Vector3, maxDistance: number?): Instance?
	local searchDistance = maxDistance or 100
	local tracksFolder = workspace:FindFirstChild("Tracks")
	if not tracksFolder then return nil end

	local bestTrack = nil
	local bestDist = searchDistance

	for _, track in ipairs(tracksFolder:GetChildren()) do
		if not track:IsA("Folder") and not track:IsA("Model") then continue end
		local waypoints = Trackable.getWaypoints(track)
		if #waypoints < 2 then continue end

		for _, wp in ipairs(waypoints) do
			local dist = (wp.Position - worldPosition).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestTrack = track
			end
		end
	end

	return bestTrack
end

---Collects Attachment/BasePart children of `trackInstance` as waypoints,
---sorted by the first number found in each child's name. Names containing
---"lift" flag the waypoint as part of a chain-lift segment.
---@param trackInstance -- Track container (Folder or Model).
---@return waypoints -- Ordered waypoint list.
function Trackable.getWaypoints(trackInstance: Instance): { Waypoint }
	local waypoints = {}
	for _, child in ipairs(trackInstance:GetChildren()) do
		local isLift = child.Name:lower():find("lift") ~= nil
		if child:IsA("Attachment") then
			table.insert(waypoints, { Name = child.Name, CFrame = child.WorldCFrame, Position = child.WorldPosition, IsLift = isLift })
		elseif child:IsA("BasePart") then
			table.insert(waypoints, { Name = child.Name, CFrame = child.CFrame, Position = child.Position, IsLift = isLift })
		end
	end

	table.sort(waypoints, function(a, b)
		local numA = tonumber(a.Name:match("%d+")) or 0
		local numB = tonumber(b.Name:match("%d+")) or 0
		return numA < numB
	end)

	return waypoints
end

---Sums the straight-line segment lengths between consecutive waypoints.
---@param waypoints -- Ordered waypoint list.
---@return length -- Total track length in studs.
function Trackable.getTrackLength(waypoints: { Waypoint }): number
	local length = 0
	for i = 2, #waypoints do
		length += (waypoints[i].Position - waypoints[i - 1].Position).Magnitude
	end

	return length
end

---Determines whether the track closes into a loop. A `Looped` attribute on
---the container overrides; otherwise the track loops when its first and last
---waypoints are within LOOP_AUTO_CLOSE_DISTANCE.
---@param trackInstance -- Track container.
---@param waypoints -- Ordered waypoint list.
---@return looped -- True when the track loops.
function Trackable.isLooped(trackInstance: Instance, waypoints: { Waypoint }): boolean
	local override = trackInstance:GetAttribute("Looped")
	if override ~= nil then return override == true end
	if #waypoints < 3 then return false end
	return (waypoints[1].Position - waypoints[#waypoints].Position).Magnitude <= LOOP_AUTO_CLOSE_DISTANCE
end

---Resamples the waypoint list through a Catmull-Rom spline at roughly
---`spacing` stud intervals, lerping up-vectors and carrying lift flags
---through. Returns the input unchanged with fewer than three waypoints.
---@param waypoints -- Ordered waypoint list.
---@param spacing -- Approximate stud distance between samples; defaults to DEFAULT_SMOOTHING_SPACING.
---@param looped -- Treat the list as a closed loop when true.
---@return resampled -- Smoothed waypoint list.
function Trackable.resampleWaypoints(waypoints: { Waypoint }, spacing: number?, looped: boolean?): { Waypoint }
	local count = #waypoints
	if count < 3 then return waypoints end

	local step = spacing or DEFAULT_SMOOTHING_SPACING

	local function sourceAt(index: number): Waypoint
		if looped then
			return waypoints[((index - 1) % count) + 1]
		end

		return waypoints[math.clamp(index, 1, count)]
	end

	local positions: { Vector3 } = {}
	local ups: { Vector3 } = {}
	local lifts: { boolean } = {}

	local segmentCount = if looped then count else count - 1
	for i = 1, segmentCount do
		local p0 = sourceAt(i - 1).Position
		local p1 = sourceAt(i).Position
		local p2 = sourceAt(i + 1).Position
		local p3 = sourceAt(i + 2).Position
		local upA = sourceAt(i).CFrame.UpVector
		local upB = sourceAt(i + 1).CFrame.UpVector
		local isLift = sourceAt(i).IsLift

		local segLen = (p2 - p1).Magnitude
		local steps = math.max(1, math.ceil(segLen / step))
		for s = 0, steps - 1 do
			local t = s / steps
			table.insert(positions, catmullRom(p0, p1, p2, p3, t))
			table.insert(ups, upA:Lerp(upB, t).Unit)
			table.insert(lifts, isLift)
		end
	end

	if not looped then
		table.insert(positions, waypoints[count].Position)
		table.insert(ups, waypoints[count].CFrame.UpVector)
		table.insert(lifts, waypoints[count].IsLift)
	end

	local resampled: { Waypoint } = {}
	local total = #positions
	for j = 1, total do
		local tangent
		if j < total then
			tangent = positions[j + 1] - positions[j]
		elseif looped then
			tangent = positions[1] - positions[j]
		else
			tangent = positions[j] - positions[math.max(1, j - 1)]
		end

		if tangent.Magnitude < MIN_SEGMENT_LENGTH then tangent = Vector3.zAxis end
		tangent = tangent.Unit

		local up = ups[j]
		if math.abs(tangent:Dot(up)) > 0.99 then
			up = if math.abs(tangent:Dot(Vector3.yAxis)) > 0.99 then Vector3.xAxis else Vector3.yAxis
		end

		table.insert(resampled, {
			Name = tostring(j),
			CFrame = CFrame.lookAlong(positions[j], tangent, up),
			Position = positions[j],
			IsLift = lifts[j],
		})
	end

	return resampled
end

---Builds the full TrackData for a container: waypoints (optionally
---smoothed), cumulative distances, total length, loop flag, and merged lift
---ranges. When looped, drops a near-duplicate final waypoint and re-appends
---the first waypoint to close the loop.
---@param trackInstance -- Track container.
---@param config -- Optional `Smoothing` (default true) and `Spacing` overrides.
---@return trackData -- Built TrackData, or nil with fewer than two waypoints.
function Trackable.buildTrackData(trackInstance: Instance, config: { Smoothing: boolean?, Spacing: number?, FlipDirection: boolean? }?): TrackData?
	local options = config or {}

	local waypoints = Trackable.getWaypoints(trackInstance)
	if #waypoints < 2 then return nil end

	local looped = Trackable.isLooped(trackInstance, waypoints)
	if looped and #waypoints >= 3 then
		local gap = (waypoints[1].Position - waypoints[#waypoints].Position).Magnitude
		if gap <= LOOP_AUTO_CLOSE_DISTANCE then
			table.remove(waypoints)
		end
	end

	if options.FlipDirection == true then
		waypoints = flipWaypoints(waypoints, looped)
	end

	if options.Smoothing ~= false then
		waypoints = Trackable.resampleWaypoints(waypoints, options.Spacing, looped)
	end

	if looped then
		local first = waypoints[1]
		table.insert(waypoints, { Name = first.Name, CFrame = first.CFrame, Position = first.Position, IsLift = first.IsLift })
	end

	local cumulative = { 0 }
	for i = 2, #waypoints do
		cumulative[i] = cumulative[i - 1] + (waypoints[i].Position - waypoints[i - 1].Position).Magnitude
	end

	local liftRanges = {}
	for i = 1, #waypoints - 1 do
		if not waypoints[i].IsLift then continue end
		local last = liftRanges[#liftRanges]
		if last and math.abs(last.Stop - cumulative[i]) < MIN_SEGMENT_LENGTH then
			last.Stop = cumulative[i + 1]
		else
			table.insert(liftRanges, { Start = cumulative[i], Stop = cumulative[i + 1] })
		end
	end

	return {
		Track = trackInstance,
		Waypoints = waypoints,
		Cumulative = cumulative,
		Length = cumulative[#waypoints],
		Looped = looped,
		LiftRanges = liftRanges,
	}
end

---Normalizes a 1D position onto the track: wraps by length when looped,
---clamps to [0, length] otherwise.
---@param trackData -- Built TrackData.
---@param position1D -- Raw 1D position.
---@return position -- Normalized 1D position.
function Trackable.wrapPosition(trackData: TrackData, position1D: number): number
	if trackData.Length <= 0 then return 0 end
	if trackData.Looped then
		return position1D % trackData.Length
	end

	return math.clamp(position1D, 0, trackData.Length)
end

---Signed difference `a - b` along the track, taking the shortest way around
---when looped.
---@param trackData -- Built TrackData.
---@param a -- First 1D position.
---@param b -- Second 1D position.
---@return delta -- Signed 1D distance.
function Trackable.deltaPosition(trackData: TrackData, a: number, b: number): number
	local delta = a - b
	if trackData.Looped and trackData.Length > 0 then
		delta = (delta + trackData.Length / 2) % trackData.Length - trackData.Length / 2
	end

	return delta
end

---Maps a 1D position to a world CFrame by lerping between the two waypoints
---bounding its segment.
---@param trackData -- Built TrackData.
---@param position1D -- 1D position along the track.
---@return cframe -- World CFrame on the track line.
function Trackable.sampleTrack(trackData: TrackData, position1D: number): CFrame
	local waypoints = trackData.Waypoints
	if #waypoints < 2 then return CFrame.new() end

	local pos = Trackable.wrapPosition(trackData, position1D)
	local index = findSegment(trackData, pos)
	local segStart = trackData.Cumulative[index]
	local segLength = trackData.Cumulative[index + 1] - segStart
	if segLength < MIN_SEGMENT_LENGTH then return waypoints[index].CFrame end

	local alpha = math.clamp((pos - segStart) / segLength, 0, 1)
	return waypoints[index].CFrame:Lerp(waypoints[index + 1].CFrame, alpha)
end

---Direction of travel at a 1D position: the unit vector of the segment the
---position falls on, falling back to the waypoint's LookVector on degenerate
---segments.
---@param trackData -- Built TrackData.
---@param position1D -- 1D position along the track.
---@return direction -- Unit direction vector.
function Trackable.getTrackDirection(trackData: TrackData, position1D: number): Vector3
	local waypoints = trackData.Waypoints
	if #waypoints < 2 then return Vector3.zAxis end

	local pos = Trackable.wrapPosition(trackData, position1D)
	local index = findSegment(trackData, pos)
	local direction = waypoints[index + 1].Position - waypoints[index].Position
	if direction.Magnitude < MIN_SEGMENT_LENGTH then return waypoints[index].CFrame.LookVector end

	return direction.Unit
end

---Whether a 1D position falls inside any chain-lift range.
---@param trackData -- Built TrackData.
---@param position1D -- 1D position along the track.
---@return inLift -- True when inside a lift range.
function Trackable.isInLift(trackData: TrackData, position1D: number): boolean
	local pos = Trackable.wrapPosition(trackData, position1D)
	for _, range in ipairs(trackData.LiftRanges) do
		if pos >= range.Start and pos <= range.Stop then return true end
	end

	return false
end

---Maps a 1D position to a CFrame by walking raw waypoints directly, without
---requiring built TrackData. Non-looped; clamps to the track ends.
---@param waypoints -- Ordered waypoint list.
---@param position1D -- 1D position along the track.
---@param trackLength -- Optional precomputed length; computed when nil.
---@return cframe -- World CFrame on the track line.
function Trackable.getCFrameAtPosition(waypoints: { Waypoint }, position1D: number, trackLength: number?): CFrame
	if #waypoints < 2 then return CFrame.new() end

	local length = trackLength or Trackable.getTrackLength(waypoints)
	local pos = math.clamp(position1D, 0, length)
	local accumulated = 0
	for i = 2, #waypoints do
		local segmentLength = (waypoints[i].Position - waypoints[i - 1].Position).Magnitude
		if accumulated + segmentLength >= pos then
			local alpha = if segmentLength < MIN_SEGMENT_LENGTH then 0 else (pos - accumulated) / segmentLength
			alpha = math.clamp(alpha, 0, 1)
			return waypoints[i - 1].CFrame:Lerp(waypoints[i].CFrame, alpha)
		end

		accumulated += segmentLength
	end

	return waypoints[#waypoints].CFrame
end

---Projects a world position onto every track segment and returns the
---closest 1D position along the track.
---@param waypoints -- Ordered waypoint list.
---@param worldPosition -- World-space position to project.
---@return position -- Closest 1D position.
---@return distance -- Distance from `worldPosition` to that point.
function Trackable.findNearestPosition1D(waypoints: { Waypoint }, worldPosition: Vector3, _): (number, number)
	local bestPos = 0
	local bestDist = math.huge
	local accumulated = 0

	for i = 2, #waypoints do
		local a = waypoints[i - 1].Position
		local b = waypoints[i].Position
		local segDir = b - a
		local segLen = segDir.Magnitude
		if segLen < MIN_SEGMENT_LENGTH then continue end
		segDir = segDir / segLen

		local toPoint = worldPosition - a
		local proj = math.clamp(toPoint:Dot(segDir), 0, segLen)
		local closestPoint = a + segDir * proj
		local dist = (worldPosition - closestPoint).Magnitude

		if dist < bestDist then
			bestDist = dist
			bestPos = accumulated + proj
		end

		accumulated += segLen
	end

	return bestPos, bestDist
end

---Behavior entry point. Stamps track attributes on the assembled model,
---unanchors every BasePart, creates the TrackThrottleEvent RemoteEvent, and
---clones the TrackableServer/TrackableRunner template scripts in enabled.
---@param assembledModel -- Assembled behavior model.
---@param config -- Optional attribute overrides (driveMode, maxTrackSpeed, ...).
function Trackable.setup(assembledModel: Model, config: { [string]: any }?): TrackableHandle
	local options = config or {}

	assembledModel:SetAttribute("driveMode", options.driveMode or "track")
	assembledModel:SetAttribute("trackActive", false)
	assembledModel:SetAttribute("trackPosition", 0)
	assembledModel:SetAttribute("trackSpeed", 0)
	assembledModel:SetAttribute("trackSyncTime", 0)
	assembledModel:SetAttribute("trackOffset", 0)
	assembledModel:SetAttribute("maxTrackSpeed", options.maxTrackSpeed or DEFAULT_MAX_TRACK_SPEED)
	assembledModel:SetAttribute("trackAcceleration", options.trackAcceleration or DEFAULT_TRACK_ACCELERATION)
	assembledModel:SetAttribute("useGravity", options.useGravity or false)
	assembledModel:SetAttribute("liftSpeed", options.liftSpeed or DEFAULT_LIFT_SPEED)
	assembledModel:SetAttribute("trackSmoothing", options.smoothing ~= false)
	assembledModel:SetAttribute("trackEnterDistance", options.trackEnterDistance or DEFAULT_ENTER_DISTANCE)
	assembledModel:SetAttribute("requireDriver", options.requireDriver == true)
	assembledModel:SetAttribute("autoMode", options.autoMode == true)
	assembledModel:SetAttribute("autoModeWaitTime", options.autoModeWaitTime or DEFAULT_AUTO_MODE_WAIT_TIME)
	assembledModel:SetAttribute("autoModeStartType", options.autoModeStartType or "soft")
	assembledModel:SetAttribute("noRollback", options.noRollback == true)
	assembledModel:SetAttribute("flipDirection", options.flipDirection == true)
	if typeof(options.targetTrackSpeed) == "number" then
		assembledModel:SetAttribute("targetTrackSpeed", options.targetTrackSpeed)
	end

	local cars = options.cars
	if cars and #cars > 0 then
		assembledModel:SetAttribute("trackMultiCar", true)

		local offset = 0
		for index, car in ipairs(cars) do
			local anchor = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart", true)
			if not anchor then
				warn("[Trackable] Car has no BasePart, skipping: " .. car:GetFullName())
				continue
			end

			car.PrimaryPart = anchor
			if index > 1 then
				local previous = cars[index - 1]
				if options.manualCarAlignment == true then
					offset += (car:GetPivot().Position - previous:GetPivot().Position).Magnitude
				else
					offset += previous:GetExtentsSize().Z / 2 + car:GetExtentsSize().Z / 2 + DEFAULT_CAR_GAP
				end
			end

			car:SetAttribute("trackCarOffset", offset)
		end

		if cars[1].PrimaryPart then
			assembledModel.PrimaryPart = cars[1].PrimaryPart
		end
	end

	for _, desc in ipairs(assembledModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
		end
	end

	local throttleEvent = Instance.new("RemoteEvent")
	throttleEvent.Name = "TrackThrottleEvent"
	throttleEvent.Parent = assembledModel

	for _, templateName in ipairs({ "TrackableServer", "TrackableRunner" }) do
		local template = script.Parent:FindFirstChild(templateName)
		if template then
			local clone = template:Clone()
			if clone:IsA("BaseScript") then
				clone.Enabled = true
			end
			clone.Parent = assembledModel
		else
			warn("[Trackable] Missing template script: " .. templateName)
		end
	end

	return makeHandle(assembledModel)
end

-- Return

return Trackable

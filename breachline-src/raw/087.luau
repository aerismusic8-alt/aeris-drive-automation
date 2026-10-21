--[[
	File: AimArc.luau

	Client-side predicted-trajectory arc renderer shared by Gunnable SubTypes.
	Given an origin Attachment plus ballistic parameters (speed / gravity /
	range), it draws a tapered beam arc that follows the same path math the
	server fires along (Common/Trajectory) and clips it at the first obstacle
	the shot would strike.

	Purely cosmetic and local: nothing here applies damage or replicates. The
	owner creates one, calls SetEnabled(true) while the local player is aiming,
	and Destroy()s it when done.

	Pass Hidden = true to keep the beams invisible while still running the solve,
	so callers that only need GetImpactPosition() (e.g. a reticle) can share one
	trajectory computation instead of casting a second time.
]]--

-- Root

local AimArc = {}
AimArc.__index = AimArc

-- Roblox Services

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Dependencies

local Trajectory = require(script.Parent.Trajectory)

-- Constants

local DEFAULT_SEGMENTS = 48
local DEFAULT_COLLISION_SEGMENTS = 12
local DEFAULT_WIDTH = 0.5
local DEFAULT_MID_TRANSPARENCY = 0.5
local DEFAULT_COLOR = Color3.new(1, 1, 1)
local MIN_SEGMENT_LENGTH = 1e-3

-- Private Methods

function AimArc:_build()
	local segments = self._segments

	local folder = Instance.new("Folder")
	folder.Name = self._name
	self._folder = folder

	local holder = Instance.new("Part")
	holder.Name = "ArcHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.1
	holder.Parent = folder

	self._nodes = table.create(segments + 1, Vector3.zero)
	self._attachments = table.create(segments + 1)
	self._beams = table.create(segments)

	for index = 1, segments + 1 do
		local attachment = Instance.new("Attachment")
		attachment.Name = "ArcNode" .. index
		attachment.Parent = holder
		self._attachments[index] = attachment
	end

	for index = 1, segments do
		local beam = Instance.new("Beam")
		beam.Name = "ArcBeam" .. index
		beam.Attachment0 = self._attachments[index]
		beam.Attachment1 = self._attachments[index + 1]
		beam.FaceCamera = true
		beam.Segments = 1
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.LightInfluence = 0
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(self._color)
		beam.Width0 = self:_widthAtNode(index - 1, segments)
		beam.Width1 = self:_widthAtNode(index, segments)
		beam.Transparency = NumberSequence.new(
			self:_transparencyAtNode(index - 1, segments),
			self:_transparencyAtNode(index, segments)
		)
		beam.Enabled = false
		beam.Parent = holder
		self._beams[index] = beam
	end

	folder.Parent = Workspace
end

function AimArc:_widthAtNode(nodeIndex: number, lastIndex: number): number
	if nodeIndex == 0 or nodeIndex >= lastIndex then
		return 0
	end

	return self._width
end

function AimArc:_transparencyAtNode(nodeIndex: number, lastIndex: number): number
	if nodeIndex == 0 or nodeIndex >= lastIndex then
		return 1
	end

	return self._midTransparency
end

function AimArc:_solveClip(startPosition: Vector3, direction: Vector3, timeEnd: number): (number, Vector3)
	local speed = self._speed
	local gravity = self._gravity
	local collisionSegments = self._collisionSegments
	local stepTime = timeEnd / collisionSegments

	local previousPosition = startPosition
	local previousTime = 0
	for index = 1, collisionSegments do
		local nextTime = index * stepTime
		local nextPosition = Trajectory.positionAt(startPosition, direction, speed, gravity, nextTime)
		local segment = nextPosition - previousPosition
		local segmentLength = segment.Magnitude
		if segmentLength >= MIN_SEGMENT_LENGTH then
			local result = Workspace:Raycast(previousPosition, segment, self._castParams)
			if result then
				local fraction = (result.Position - previousPosition).Magnitude / segmentLength
				return previousTime + fraction * stepTime, result.Position
			end
		end

		previousPosition = nextPosition
		previousTime = nextTime
	end

	return timeEnd, Trajectory.positionAt(startPosition, direction, speed, gravity, timeEnd)
end

-- Public Methods

function AimArc:Update()
	local origin = self._origin
	if not origin.Parent then return end

	local originCFrame = origin.WorldCFrame
	local startPosition = originCFrame.Position
	local direction = if self._getDirection then self._getDirection(originCFrame) else originCFrame.LookVector
	local speed = self._speed
	local gravity = self._gravity
	local timeEnd = self._range / speed

	local timeClip, impactPosition = self:_solveClip(startPosition, direction, timeEnd)
	self._impactPosition = impactPosition

	local segments = self._segments
	local nodes = self._nodes
	for index = 0, segments do
		if index == segments then
			nodes[index + 1] = impactPosition
		else
			nodes[index + 1] = Trajectory.positionAt(startPosition, direction, speed, gravity, timeClip * index / segments)
		end
	end

	for index = 1, segments + 1 do
		self._attachments[index].WorldPosition = nodes[index]
	end
end

function AimArc:GetImpactPosition(): Vector3?
	return self._impactPosition
end

function AimArc:SetEnabled(enabled: boolean)
	if enabled == self._enabled then return end
	self._enabled = enabled

	for _, beam in self._beams do
		beam.Enabled = enabled and not self._hidden
	end

	if enabled then
		self:Update()
		self._connection = RunService.RenderStepped:Connect(function()
			self:Update()
		end)
	elseif self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function AimArc:Destroy()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end

	self._folder:Destroy()
	table.clear(self)
end

-- Constructor

function AimArc.new(originAttachment: Attachment, params: AimArcParams): AimArc
	assert(typeof(originAttachment) == "Instance" and originAttachment:IsA("Attachment"), "[AimArc] originAttachment must be an Attachment")
	assert(params.Speed > 0, "[AimArc] Speed must be > 0")

	local self = setmetatable({}, AimArc)

	self._origin = originAttachment
	self._speed = params.Speed
	self._gravity = math.max(0, params.Gravity)
	self._range = params.Range
	self._segments = math.max(2, math.floor(params.Segments or DEFAULT_SEGMENTS))
	self._collisionSegments = math.max(1, math.floor(params.CollisionSegments or DEFAULT_COLLISION_SEGMENTS))
	self._width = params.Width or DEFAULT_WIDTH
	self._midTransparency = params.MidTransparency or DEFAULT_MID_TRANSPARENCY
	self._color = params.Color or DEFAULT_COLOR
	self._name = params.Name or "Gunnable_AimArc"
	self._castParams = params.CastParams
	self._getDirection = params.GetDirection
	self._hidden = params.Hidden == true

	self._enabled = false
	self._impactPosition = nil
	self._connection = nil
	self._nodes = nil
	self._attachments = nil
	self._beams = nil
	self._folder = nil

	self:_build()

	return self
end

-- Types

export type AimArcParams = {
	Speed: number,
	Gravity: number,
	Range: number,
	Segments: number?,
	CollisionSegments: number?,
	Width: number?,
	MidTransparency: number?,
	Color: Color3?,
	CastParams: RaycastParams?,
	Name: string?,
	GetDirection: ((originCFrame: CFrame) -> Vector3)?,
	Hidden: boolean?,
}

export type AimArc = {
	Update: (self: AimArc) -> (),
	GetImpactPosition: (self: AimArc) -> Vector3?,
	SetEnabled: (self: AimArc, enabled: boolean) -> (),
	Destroy: (self: AimArc) -> (),
}

-- Return

return AimArc
$
--[[
	File: WaterVehicle2.luau
]]--

-- Root

local WaterVehicle2 = {}
WaterVehicle2.__index = WaterVehicle2

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local Dumpster = require(FourD.Libs.Dumpster)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local GetExternalCFrame = require(FourD.Common.getExternalCFrame)
local StripCapabilityTag = require(FourD.Common.stripCapabilityTag)
local WaterUtils = require(Shared.Utils.WaterUtils)

-- Constants

local BALLAST_KP = 4
local BALLAST_RESOLUTION = 5
local COVERAGE_DROP_RATIO = 0.5
local DEBUG_BALLASTS = false
local DEBUG_FREEZE = false
local ELONGATION_THRESHOLD = 8
local MAX_VERTICAL_SPEED = 20
local PLOP_THRESHOLD = 30
local RUDDER_BLADE_TAG = "RudderBlade"
local RUDDER_FLATNESS_THRESHOLD = 0.25
local SEAT_NAMES = { "Seat", "SeatLeft", "PilotSeat", "MainSeat" }
local THINNESS_THRESHOLD = 0.05
local VERBOSE_LOGGING = false
local VESSEL_DENSITY = 1.25
local VOLUME_THRESHOLD_RATIO = 0.01
local Y_SAMPLE_STEP = 0.5
local DEFAULT_PARAMS: SetupParams = {
	Draft = 0.5,
	MaxForwardSpeed = 40,
	MaxReverseSpeed = 20,
	Acceleration = 8,
	MaxTurnSpeed = 45,
	TurnAcceleration = 60,
	UseProximityPrompt = true,
	ProximityPromptText = "Drive",
}

-- Types (local)

type PartBounds = {
	Part: BasePart,
	MinX: number, MaxX: number,
	MinY: number, MaxY: number,
	MinZ: number, MaxZ: number,
	Volume: number,
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function setOwner(assembly: BasePart|Instance, owner: Player?)
	if assembly:IsA("BasePart") then
		assembly:SetNetworkOwner(owner)
	end

	for _, object in assembly:GetDescendants() do
		if object:IsA("BasePart") then
			object:SetNetworkOwner(owner)
		end
	end
end

local function setCharacterMassless(character: Model, massless: boolean)
	for _, part in GeometryUtils.getInstanceParts(character) do
		part.Massless = massless
	end
end

local function setCharacterVisibility(character: Model, transparency: number)
	for _, descendant in character:GetDescendants() do
		if descendant.Name == "HumanoidRootPart" then continue end
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.Transparency = transparency
		end
	end
end

local function findSeatReference(body: PVInstance): PVInstance?
	for _, desc in body:GetDescendants() do
		if not desc:IsA("PVInstance") then continue end
		if desc:IsA("Seat") or desc:IsA("VehicleSeat") then continue end
		if table.find(SEAT_NAMES, desc.Name) then
			return desc
		end
	end

	return nil
end

local function makeBallastPart(cf: CFrame, size: Vector3, name: string): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = cf
	part.Name = name
	part.Size = size
	part.Transparency = if DEBUG_BALLASTS then 0.5 else 1
	return part
end

local function makeRootPart(cf: CFrame, forwardAxis: Vector3): Part
	local part = Instance.new("Part")
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(cf.Position, cf.Position + forwardAxis)
	part.Massless = true
	part.Name = "HullRoot"
	part.Size = Vector3.new(2, 2, 2)
	part.Transparency = if DEBUG_BALLASTS then 0.5 else 1

	if DEBUG_FREEZE then
		part.Anchored = true
	end

	if DEBUG_BALLASTS then
		part.Color = Color3.new(0, 1, 0)
	end

	return part
end

local function computePartBounds(part: BasePart, refCFInverse: CFrame): PartBounds
	local localCF = refCFInverse * part.CFrame
	local hs = part.Size / 2
	local localPos = localCF.Position
	local rx = math.abs(localCF.RightVector.X) * hs.X + math.abs(localCF.UpVector.X) * hs.Y + math.abs(localCF.LookVector.X) * hs.Z
	local ry = math.abs(localCF.RightVector.Y) * hs.X + math.abs(localCF.UpVector.Y) * hs.Y + math.abs(localCF.LookVector.Y) * hs.Z
	local rz = math.abs(localCF.RightVector.Z) * hs.X + math.abs(localCF.UpVector.Z) * hs.Y + math.abs(localCF.LookVector.Z) * hs.Z
	return {
		Part = part,
		MinX = localPos.X - rx, MaxX = localPos.X + rx,
		MinY = localPos.Y - ry, MaxY = localPos.Y + ry,
		MinZ = localPos.Z - rz, MaxZ = localPos.Z + rz,
		Volume = hs.X * hs.Y * hs.Z * 8,
	}
end

local function fallbackHullResult(body: PVInstance, parts: {BasePart}, refCF: CFrame): (Vector3, Vector3, {BasePart}, Vector3)
	local center, size = GeometryUtils.getBodyBounds(body)
	local localForward = if size.X > size.Z then -Vector3.xAxis else -Vector3.zAxis
	return center, size, parts, refCF:VectorToWorldSpace(localForward)
end

local function detectHull(body: PVInstance, sternRef: PVInstance?): (Vector3, Vector3, {BasePart}, Vector3)
	local refCF = GeometryUtils.getInstanceCFrame(body)
	local refCFInverse = refCF:Inverse()

	local parts = GeometryUtils.getInstanceParts(body)
	if #parts <= 1 then
		return fallbackHullResult(body, parts, refCF)
	end

	-- filter out outliers (skinny/long/deco parts)
	local hullParts: {BasePart} = {}
	for _, part in parts do
		local dims = { part.Size.X, part.Size.Y, part.Size.Z }
		table.sort(dims)

		local elongation = dims[2] > 0 and (dims[3] / dims[2]) or math.huge
		local thinness = dims[2] > 0 and (dims[1] / dims[2]) or 0
		if elongation <= ELONGATION_THRESHOLD and thinness >= THINNESS_THRESHOLD then
			table.insert(hullParts, part)
		end
	end

	if #hullParts <= 1 then
		return fallbackHullResult(body, parts, refCF)
	end

	-- group by volume concentration
	local largestVolume = 0
	for _, part in hullParts do
		local vol = part.Size.X * part.Size.Y * part.Size.Z
		if vol > largestVolume then largestVolume = vol end
	end

	local significantParts: {BasePart} = {}
	for _, part in hullParts do
		if part.Size.X * part.Size.Y * part.Size.Z >= (largestVolume * VOLUME_THRESHOLD_RATIO) then
			table.insert(significantParts, part)
		end
	end

	if #significantParts <= 1 then
		significantParts = hullParts
	end

	-- filter superstructure via Y-level horizontal coverage
	local boundsCache: {PartBounds} = {}
	local globalMinY, globalMaxY = math.huge, -math.huge
	for _, part in significantParts do
		local bounds = computePartBounds(part, refCFInverse)
		table.insert(boundsCache, bounds)
		globalMinY = math.min(globalMinY, bounds.MinY)
		globalMaxY = math.max(globalMaxY, bounds.MaxY)
	end

	local coverageSteps = {}
	local maxCoverage = 0
	for y = globalMinY, globalMaxY, Y_SAMPLE_STEP do
		local sliceMinX, sliceMaxX = math.huge, -math.huge
		local sliceMinZ, sliceMaxZ = math.huge, -math.huge
		for _, bounds in boundsCache do
			if bounds.MinY <= y and bounds.MaxY >= y then
				sliceMinX = math.min(sliceMinX, bounds.MinX)
				sliceMaxX = math.max(sliceMaxX, bounds.MaxX)
				sliceMinZ = math.min(sliceMinZ, bounds.MinZ)
				sliceMaxZ = math.max(sliceMaxZ, bounds.MaxZ)
			end
		end

		local coverage = 0
		if sliceMinX < sliceMaxX and sliceMinZ < sliceMaxZ then
			coverage = (sliceMaxX - sliceMinX) * (sliceMaxZ - sliceMinZ)
		end

		table.insert(coverageSteps, { Y = y, Coverage = coverage })
		if coverage > maxCoverage then maxCoverage = coverage end
	end

	local coverageThreshold = maxCoverage * COVERAGE_DROP_RATIO
	local hullTopY = globalMinY
	for _, step in coverageSteps do
		if step.Coverage >= coverageThreshold then
			hullTopY = step.Y
		end
	end

	local filteredBounds: {PartBounds} = {}
	local filteredParts: {BasePart} = {}
	for _, bounds in boundsCache do
		if bounds.MinY <= hullTopY then
			table.insert(filteredBounds, bounds)
			table.insert(filteredParts, bounds.Part)
		end
	end

	if #filteredBounds <= 1 then
		filteredBounds = boundsCache
		filteredParts = significantParts
	end

	-- compute AABB from hull-filtered parts
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local weightedPos = Vector3.zero
	local totalVolume = 0
	for _, bounds in filteredBounds do
		minX = math.min(minX, bounds.MinX); maxX = math.max(maxX, bounds.MaxX)
		minY = math.min(minY, bounds.MinY); maxY = math.max(maxY, bounds.MaxY)
		minZ = math.min(minZ, bounds.MinZ); maxZ = math.max(maxZ, bounds.MaxZ)
		weightedPos += (refCFInverse * bounds.Part.Position) * bounds.Volume
		totalVolume += bounds.Volume
	end

	local center = weightedPos / totalVolume
	local hullSize = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	local forwardAxis = if hullSize.X > hullSize.Z then Vector3.xAxis else -Vector3.zAxis
	local sternHint = sternRef or body:FindFirstChild("rudder")
	if sternHint then
		local hintLocalPos = refCFInverse * GeometryUtils.getInstanceCFrame(sternHint).Position
		local axisComponent = forwardAxis:Dot(hintLocalPos - center)
		if axisComponent > 0 then
			forwardAxis = -forwardAxis
		end
	else
		-- fallback: bow half has less volume (tapers) (won't support barges...)
		local positiveVol, negativeVol = 0, 0
		for _, bounds in filteredBounds do
			if forwardAxis:Dot((refCFInverse * bounds.Part.Position) - center) >= 0 then
				positiveVol += bounds.Volume
			else
				negativeVol += bounds.Volume
			end
		end

		if positiveVol > negativeVol then
			forwardAxis = -forwardAxis
		end
	end

	local worldCenter = refCF * center
	local worldForwardAxis = refCF:VectorToWorldSpace(forwardAxis)
	return worldCenter, hullSize, filteredParts, worldForwardAxis
end

local function isSpinningPart(part: BasePart): boolean
	return part.Name == "PropHub" or string.find(part.Name, "Blade") ~= nil
end

local function computeWheelRadius(size: Vector3, forwardAxis: Vector3): number
	local forwardExtent = math.abs(forwardAxis.X) * size.X + math.abs(forwardAxis.Z) * size.Z
	return math.max(size.Y, forwardExtent) / 2
end

local function getRudderBladeCandidates(rudder: PVInstance): { BasePart }
	local parts: { BasePart } = {}
	if rudder:IsA("BasePart") then
		table.insert(parts, rudder)
	else
		for _, part in ConstructionHelpers.getAllParts({ rudder }) do
			table.insert(parts, part)
		end
	end
	return parts
end

local function detectRudderBlades(rudder: PVInstance): { BasePart }
	local candidates = getRudderBladeCandidates(rudder)
	if #candidates == 0 then return {} end

	local tagged: { BasePart } = {}
	for _, part in candidates do
		if CollectionService:HasTag(part, RUDDER_BLADE_TAG) then
			table.insert(tagged, part)
		end
	end
	if #tagged > 0 then return tagged end

	local named: { BasePart } = {}
	for _, part in candidates do
		if string.find(string.lower(part.Name), "blade") then
			table.insert(named, part)
		end
	end
	if #named > 0 then return named end

	if #candidates == 1 then
		return candidates
	end

	local best: BasePart? = nil
	local bestArea = 0
	for _, part in candidates do
		local dims = { part.Size.X, part.Size.Y, part.Size.Z }
		table.sort(dims)
		local minAxis, medianAxis, maxAxis = dims[1], dims[2], dims[3]
		if medianAxis <= 0 then continue end
		if (minAxis / medianAxis) > RUDDER_FLATNESS_THRESHOLD then continue end

		local area = medianAxis * maxAxis
		if area > bestArea then
			best = part
			bestArea = area
		end
	end

	if best then
		return { best }
	end

	return {}
end

local function computeRudderHinge(blades: { BasePart }, forwardAxis: Vector3): CFrame
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge

	for _, part in blades do
		local cf = part.CFrame
		local hs = part.Size / 2
		local rx = math.abs(cf.RightVector.X) * hs.X + math.abs(cf.UpVector.X) * hs.Y + math.abs(cf.LookVector.X) * hs.Z
		local ry = math.abs(cf.RightVector.Y) * hs.X + math.abs(cf.UpVector.Y) * hs.Y + math.abs(cf.LookVector.Y) * hs.Z
		local rz = math.abs(cf.RightVector.Z) * hs.X + math.abs(cf.UpVector.Z) * hs.Y + math.abs(cf.LookVector.Z) * hs.Z
		local p = cf.Position
		minX = math.min(minX, p.X - rx); maxX = math.max(maxX, p.X + rx)
		minY = math.min(minY, p.Y - ry); maxY = math.max(maxY, p.Y + ry)
		minZ = math.min(minZ, p.Z - rz); maxZ = math.max(maxZ, p.Z + rz)
	end

	local center = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)

	local forwardExtent = math.abs(forwardAxis.X) * size.X + math.abs(forwardAxis.Z) * size.Z
	local topY = maxY
	local hingeBase = center + forwardAxis * (forwardExtent / 2)
	local hingePos = Vector3.new(hingeBase.X, topY, hingeBase.Z)

	return CFrame.lookAt(hingePos, hingePos + forwardAxis, Vector3.yAxis)
end

local function updateBallast(ballast: BasePart, velocity: LinearVelocity, draftOffset: number)
	local waterLevelY = WaterUtils.getWaterLevel(ballast.Position)
	if not waterLevelY then
		velocity.VectorVelocity = Vector3.zero
		return
	end

	local draftError = (waterLevelY + draftOffset) - ballast.Position.Y
	if draftError <= -PLOP_THRESHOLD then
		velocity.VectorVelocity = Vector3.zero
		return
	end

	local vy = math.clamp(draftError * BALLAST_KP, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)
	velocity.VectorVelocity = Vector3.new(0, vy, 0)
end

-- Private Methods

function WaterVehicle2:_applyDensity()
	local props = PhysicalProperties.new(VESSEL_DENSITY, 0.3, 0.5, 1, 1)
	for _, desc in self.vesselModel:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CustomPhysicalProperties = props
		end
	end
end

function WaterVehicle2:_rigVesselStructure()
	local hullCenter, hullSize, _, forwardAxis = detectHull(self.bodyModel, self._params.SternReference)
	local isForwardX = hullSize.X > hullSize.Z
	local length = if isForwardX then hullSize.X else hullSize.Z
	local beam = if isForwardX then hullSize.Z else hullSize.X
	local hullPart = makeRootPart(CFrame.new(hullCenter), forwardAxis)
	hullPart.Parent = self.vesselModel
	self.vesselModel.PrimaryPart = hullPart
	ConstructionHelpers.weldAllParts(self.bodyModel, hullPart)

	for _, desc in self.bodyModel:GetDescendants() do
		if desc:IsA("BasePart") then desc.Massless = true end
	end

	local ballastLength = length / BALLAST_RESOLUTION
	local ballastSize = Vector3.new(beam, hullSize.Y, ballastLength)
	for i = 1, BALLAST_RESOLUTION do
		local offset = forwardAxis * (-length / 2 + ballastLength * (i - 0.5))
		local ballastPos = hullCenter + offset
		local newBallast = makeBallastPart(
			CFrame.lookAt(ballastPos, ballastPos + forwardAxis),
			ballastSize, `Ballast{i}`
		)

		if DEBUG_BALLASTS then -- quick lil debug visualizer :)
			local t = (i - 1) / math.max(BALLAST_RESOLUTION - 1, 1)
			newBallast.Color = Color3.new(1 - t, 0, t)
		end

		newBallast.Anchored = false
		newBallast.Parent = self.ballastFolder
		ConstructionHelpers.makeWeld(hullPart, newBallast)

		local buoyancyAtt = Instance.new("Attachment")
		buoyancyAtt.Name = "BuoyancyAttachment"
		buoyancyAtt.Parent = newBallast

		local buoyancyVelocity = Instance.new("LinearVelocity")
		buoyancyVelocity.Name = "BuoyancyVelocity"
		buoyancyVelocity.Attachment0 = buoyancyAtt
		buoyancyVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		buoyancyVelocity.MaxAxesForce = Vector3.new(0, math.huge, 0)
		buoyancyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		buoyancyVelocity.VectorVelocity = Vector3.zero
		buoyancyVelocity.Parent = newBallast

		self._ballastVelocities[i] = buoyancyVelocity
		table.insert(self._ballasts, newBallast)
	end

	self._draftOffset = hullSize.Y * (0.5 - self._params.Draft)
	self._hullCenter = hullCenter
	self._hullSize = hullSize
	self._forwardAxis = forwardAxis
	self.root = hullPart
end

function WaterVehicle2:_rigDriverSeat()
	local seat = Instance.new("VehicleSeat")
	seat.CanCollide = false
	seat.HeadsUpDisplay = false
	seat.Massless = true
	seat.MaxSpeed = 0
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Torque = 0
	seat.Transparency = 1
	seat.TurnSpeed = 0

	local seatRef = findSeatReference(self.bodyModel)
	if seatRef then
		local refCf = GeometryUtils.getInstanceCFrame(seatRef)
		seat.CFrame = CFrame.lookAlong(refCf.Position, self._forwardAxis)
	else
		local seatY = self._hullCenter.Y + self._hullSize.Y * 0.15
		seat.CFrame = CFrame.lookAlong(
			Vector3.new(self._hullCenter.X, seatY, self._hullCenter.Z),
			self._forwardAxis
		)
	end

	ConstructionHelpers.makeWeld(self.root, seat)
	seat.Parent = self.vesselModel
	self.driverSeat = seat
end

function WaterVehicle2:_rigRotorIfPresent()
	local rotors = self._params.Rotors
	if not rotors or #rotors == 0 then return end

	local isWheels = self._params.RotorsAreWheels == true
	local forwardAxis = self._forwardAxis

	local motorIndex = 0
	for _, rotor in rotors do
		local rotorRoot
		local wheelRadius: number? = nil
		if rotor:IsA("BasePart") then
			for _, child in self.root:GetChildren() do
				if child:IsA("WeldConstraint") and child.Part1 == rotor then
					child:Destroy()
					break
				end
			end

			rotorRoot = rotor
			if isWheels then
				wheelRadius = computeWheelRadius(rotor.Size, forwardAxis)
			end
		else
			local rotorModel = rotor
			local rotorParts = ConstructionHelpers.getAllParts({ rotorModel })

			if #rotorParts == 1 then
				local onlyPart = rotorParts[1]
				for _, child in self.root:GetChildren() do
					if child:IsA("WeldConstraint") and child.Part1 == onlyPart then
						child:Destroy()
						break
					end
				end

				rotorRoot = onlyPart
				if isWheels then
					wheelRadius = computeWheelRadius(onlyPart.Size, forwardAxis)
				end
			else
				local boundsCenter, boundsSize = GeometryUtils.getBodyBounds(rotorModel)
				local boundsBox = Instance.new("Part")
				boundsBox.CanCollide = false
				boundsBox.CanQuery = false
				boundsBox.CastShadow = false
				boundsBox.CFrame = CFrame.new(boundsCenter)
				boundsBox.Massless = true
				boundsBox.Name = "RotorBounds"
				boundsBox.Size = boundsSize
				boundsBox.Transparency = 1
				boundsBox.Parent = rotorModel
				rotorModel.PrimaryPart = boundsBox
				rotorRoot = boundsBox

				for _, part in rotorParts do
					if not isWheels and not isSpinningPart(part) then continue end

					for _, child in self.root:GetChildren() do
						if child:IsA("WeldConstraint") and child.Part1 == part then
							child:Destroy()
							break
						end
					end

					ConstructionHelpers.makeWeld(rotorRoot, part)
				end

				if isWheels then
					wheelRadius = computeWheelRadius(boundsSize, forwardAxis)
				end
			end
		end

		motorIndex += 1
		local motorName = if motorIndex == 1 then "RotorMotor" else `RotorMotor{motorIndex}`
		local rotorMotor = Instance.new("Motor6D")
		rotorMotor.Name = motorName
		rotorMotor.Part0 = self.root
		rotorMotor.Part1 = rotorRoot
		rotorMotor.C0 = self.root.CFrame:Inverse() * rotorRoot.CFrame
		rotorMotor.C1 = CFrame.identity
		if wheelRadius then
			rotorMotor:SetAttribute("WheelRadius", wheelRadius)
		end
		rotorMotor.Parent = self.root
	end

	local axis = if isWheels then Vector3.yAxis:Cross(forwardAxis).Unit else forwardAxis
	self.root:SetAttribute("RotorsAreWheels", isWheels)
	self.root:SetAttribute("SpinAxisX", axis.X)
	self.root:SetAttribute("SpinAxisY", axis.Y)
	self.root:SetAttribute("SpinAxisZ", axis.Z)
end

function WaterVehicle2:_rigRudderIfPresent()
	local rudder = self._params.Rudder
	if not rudder then return end

	local blades = detectRudderBlades(rudder)
	if #blades == 0 then
		vwarn(`rudder blade heuristic found no candidate parts on {rudder:GetFullName()}; skipping rudder animation`)
		return
	end

	for _, blade in blades do
		for _, child in self.root:GetChildren() do
			if child:IsA("WeldConstraint") and child.Part1 == blade then
				child:Destroy()
				break
			end
		end
	end

	local rudderRoot: BasePart
	local singleBlade = #blades == 1 and blades[1] == rudder
	if singleBlade then
		rudderRoot = blades[1]
	elseif rudder:IsA("BasePart") then
		rudderRoot = rudder
	else
		local rudderModel = rudder
		local boundsCenter, boundsSize = GeometryUtils.getBodyBounds(rudderModel)
		local boundsBox = Instance.new("Part")
		boundsBox.CanCollide = false
		boundsBox.CanQuery = false
		boundsBox.CastShadow = false
		boundsBox.CFrame = CFrame.new(boundsCenter)
		boundsBox.Massless = true
		boundsBox.Name = "RudderBounds"
		boundsBox.Size = boundsSize
		boundsBox.Transparency = 1
		boundsBox.Parent = rudderModel
		rudderModel.PrimaryPart = boundsBox
		rudderRoot = boundsBox

		for _, blade in blades do
			ConstructionHelpers.makeWeld(rudderRoot, blade)
		end
	end

	local hingeCFrame = computeRudderHinge(blades, self._forwardAxis)

	local rudderMotor = Instance.new("Motor6D")
	rudderMotor.Name = "RudderMotor"
	rudderMotor.Part0 = self.root
	rudderMotor.Part1 = rudderRoot
	rudderMotor.C0 = self.root.CFrame:Inverse() * hingeCFrame
	rudderMotor.C1 = rudderRoot.CFrame:Inverse() * hingeCFrame
	rudderMotor.Parent = self.root

	self.root:SetAttribute("HasRudder", true)
end

function WaterVehicle2:_rigPhysicsObjects()
	local hullAtt = Instance.new("Attachment")
	hullAtt.Name = "HullAttachment"
	hullAtt.Position = Vector3.zero
	hullAtt.Parent = self.root

	local surgeVel = Instance.new("LinearVelocity")
	surgeVel.Name = "SurgeVelocity"
	surgeVel.Attachment0 = hullAtt
	surgeVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	surgeVel.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	surgeVel.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	surgeVel.VectorVelocity = Vector3.zero
	surgeVel.Parent = self.root

	local yawVel = Instance.new("AngularVelocity")
	yawVel.Name = "YawVelocity"
	yawVel.Attachment0 = hullAtt
	yawVel.AngularVelocity = Vector3.zero
	yawVel.MaxTorque = math.huge
	yawVel.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	yawVel.Parent = self.root

	self._surgeVelocity = surgeVel
	self._yawVelocity = yawVel
end

function WaterVehicle2:_rigProximityPrompt()
	if not self._params.UseProximityPrompt then return end

	local drivePrompt = Instance.new("ProximityPrompt")
	drivePrompt.Name = "DrivePrompt"
	drivePrompt.ActionText = self._params.ProximityPromptText
	drivePrompt.MaxActivationDistance = math.min(self._hullSize.X, self._hullSize.Z) * 1.25
	drivePrompt.RequiresLineOfSight = false
	drivePrompt.Parent = self.driverSeat

	self.drivePrompt = drivePrompt
end

function WaterVehicle2:_rigController()
	self.root:SetAttribute("MaxForwardSpeed", self._params.MaxForwardSpeed)
	self.root:SetAttribute("MaxReverseSpeed", self._params.MaxReverseSpeed)
	self.root:SetAttribute("Acceleration", self._params.Acceleration)
	self.root:SetAttribute("MaxTurnSpeed", self._params.MaxTurnSpeed)
	self.root:SetAttribute("TurnAcceleration", self._params.TurnAcceleration)
	self.root:SetAttribute("DraftOffset", self._draftOffset)

	local controllerScript = script:FindFirstChild("WaterVehicle2Client")
	if not controllerScript then
		vwarn("WaterVehicle2Client not found in", script:GetFullName())
		return
	end

	local clone = controllerScript:Clone()
	clone.Parent = self.vesselModel
	-- WaterVehicle2Client is a ClientComponent ModuleScript (no Disabled).
	if clone:IsA("BaseScript") then
		clone.Disabled = false
	end

	local serverTemplate = script:FindFirstChild("WaterVehicle2Server")
	assert(serverTemplate and serverTemplate:IsA("Script"), "WaterVehicle2Server template is missing")
	local serverController = serverTemplate:Clone()
	serverController:SetAttribute("CASBehaviorManaged", true)
	serverController.Parent = self.vesselModel
	serverController.Disabled = false
end

function WaterVehicle2:_setupVessel()
	local rigModel = Instance.new("Model")
	rigModel.Name = `WaterVehicle_{self.bodyModel.Name}`
	rigModel.Parent = self.bodyModel.Parent

	local ballastFolder = Instance.new("Folder")
	ballastFolder.Name = "Ballasts"
	ballastFolder.Parent = rigModel

	self.ballastFolder = ballastFolder
	self.vesselModel = rigModel
	self.mainDump:Add(rigModel)

	self:_rigVesselStructure()
	self:_rigRotorIfPresent()
	self:_rigRudderIfPresent()
	self:_rigDriverSeat()
	self:_rigPhysicsObjects()
	self:_rigProximityPrompt()
	self:_rigController()
	self:_applyDensity()
	self.bodyModel.Parent = rigModel

	StripCapabilityTag(rigModel)
end

-- Public Methods

---Destroys class data, cleans up connections, and destroys tracked objects.
function WaterVehicle2:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self.mainDump:Destroy()
	for k, v in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function WaterVehicle2.build(body: PVInstance, params: SetupParams)
	assert(body ~= nil, "must supply valid body PVInstance")

	local self = setmetatable({}, WaterVehicle2)

	-- dumpsters
	self.mainDump = Dumpster.new()
	self.eventDump = self.mainDump:Extend()

	-- private keys (non-Instances, underscore prefix)
	self._ballasts = {}
	self._ballastVelocities = {}
	self._draftOffset = 0
	self._lastDriver = nil

	-- private keys (instances, no underscores)
	self.ballastFolder = nil
	self.bodyModel = body
	self.drivePrompt = nil
	self.driverSeat = nil
	self.vesselModel = nil

	-- default params
	self._params = params
	for k, v in DEFAULT_PARAMS do
		if self._params[k] ~= nil then continue end
		self._params[k] = v
	end

	self:_setupVessel()
	vprint(`Completed setup on {body} with params:`, self._params)
	return self
end

-- Types

export type SetupParams = {
	Draft: number?,
	MaxForwardSpeed: number?,
	MaxReverseSpeed: number?,
	Acceleration: number?,
	MaxTurnSpeed: number?,
	TurnAcceleration: number?,
	ProximityPromptText: string?,
	Rotors: { PVInstance }?,
	RotorsAreWheels: boolean?,
	Rudder: PVInstance?,
	SternReference: PVInstance?,
	UseProximityPrompt: boolean?,
}

-- Return

return WaterVehicle2

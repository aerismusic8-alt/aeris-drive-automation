--[[
	File: Heuristics.luau

	Geometry heuristics + rig scaling/welding helpers for TwoWheel.
]]--

-- Root

local Heuristics = {}

-- Dependencies

local FourD = script:FindFirstAncestor("FourD")
local Common = FourD.Common
local GeometryUtils = require(Common.GeometryUtils)
local SeatHelpers = require(Common.SeatHelpers)

-- Types

type Wheel = BasePart | Model

-- Constants

local DEFAULT_RAKE_DEG = 25
local MAX_STEER_HARD_CAP = 60
local MIN_STEER_DEGREES = 5
local DEFAULT_DRIVER_SEAT_X = 2
-- Roblox welds a seated avatar a fixed distance clear of the seat's top face
-- rather than flush with it: measured on a default R15 rig, the underside of
-- LowerTorso lands 0.48 studs above it. A car hides that gap inside a body
-- shell, but a saddle is a surface the rider sits on in plain view, so left in
-- it reads as the rider hovering.
local SEATED_HIP_GAP = 0.48
-- How far below the surface to bury the rider once that gap is cancelled. A
-- rider slightly inside a saddle reads as sitting on it; one floating the same
-- distance above reads as broken. The schema is author-supplied and arbitrary,
-- so the error is deliberately spent downwards.
local SEAT_SINK = 0.5
-- Lengthwise samples taken when probing the seat surface. Twenty-four puts a
-- sample every ~0.15 studs on a 3.5-stud seat, fine enough to find the ends of
-- the geometry without making the build noticeably slower.
local SEAT_SURFACE_SAMPLES = 24
local STEERING_PART_NAMES = { "handlebars", "front fork" }
local SUSPENSION_NATURAL_FREQ = 26
local SUSPENSION_DAMPING_RATIO = 0.8
local SUSPENSION_PRELOAD = 0.1
local SUSPENSION_REST_FACTOR = 0.55
local SUSPENSION_TRAVEL_FACTOR = 0.6
local CARRIER_MASS_FACTOR = 0.5
local CARRIER_MIN_MASS = 3

-- Local Functions

local function getWheelDiameter(wheel: Wheel): number
	if wheel:IsA("BasePart") then
		return math.max(wheel.Size.Y, wheel.Size.Z)
	end

	local _, sz = wheel:GetBoundingBox()
	return math.max(sz.X, sz.Y, sz.Z)
end

local function getWheelPrimaryPart(wheel: Wheel): BasePart
	if wheel:IsA("BasePart") then
		return wheel
	end

	local biggest = nil
	local biggestVolume = -1
	for _, descendant in wheel:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
		if volume > biggestVolume then
			biggestVolume = volume
			biggest = descendant
		end
	end

	assert(biggest, `wheel has no BasePart descendants: {wheel.Name}`)
	wheel.PrimaryPart = biggest
	return biggest
end

local function scaleAttachmentPositions(parent: BasePart, scale: Vector3)
	for _, child in parent:GetChildren() do
		if not child:IsA("Attachment") then
			continue
		end

		local scaled = Vector3.new(
			scale.X * child.CFrame.Position.X,
			scale.Y * child.CFrame.Position.Y,
			scale.Z * child.CFrame.Position.Z
		)
		child.CFrame = child.CFrame.Rotation + scaled
	end
end

local function rescalePartGroup(parts: { BasePart }, scale: number)
	local tempModel = Instance.new("Model")
	local tempPrimary = Instance.new("Part")
	tempPrimary.Size = Vector3.new(1, 1, 1)
	tempPrimary.CFrame = CFrame.new(0, 0, 0)
	tempPrimary.Parent = tempModel
	tempModel.PrimaryPart = tempPrimary

	local oldParents = {}
	for _, part in parts do
		oldParents[part] = part.Parent
		part.Parent = tempModel
	end

	tempModel:ScaleTo(scale)
	for part, parent in oldParents do
		part.Parent = parent
	end

	tempModel:Destroy()
end

local function attachCFrame(localPos: Vector3, xAxisDir: Vector3): CFrame
	local x = xAxisDir.Unit
	local refUp = Vector3.new(-1, 0, 0)
	if math.abs(x:Dot(refUp)) > 0.9 then
		refUp = Vector3.new(0, 0, -1)
	end

	local y = (refUp - x * x:Dot(refUp)).Unit
	local z = x:Cross(y).Unit
	return CFrame.fromMatrix(localPos, x, y, z)
end

local function makeAttachment(parent: BasePart, worldCFrame: CFrame, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = parent
	attachment.WorldCFrame = worldCFrame
	return attachment
end

local function setCarrierMass(part: BasePart, targetMass: number)
	part.Massless = false
	part.CanCollide = false
	local volume = math.max(part.Size.X * part.Size.Y * part.Size.Z, 1e-3)
	part.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(targetMass / volume, 0.7, 100), 0.3, 0)
end

local function computeRakeAxis(body: Model, frontPos: Vector3, forward: Vector3, up: Vector3): (Vector3, number)
	local handlebars = body:FindFirstChild("handlebars")
	if handlebars then
		local headPos = GeometryUtils.getInstanceCFrame(handlebars).Position
		local delta = headPos - frontPos
		if delta.Magnitude > 0.1 then
			return delta.Unit, delta.Magnitude
		end
	end

	local rake = math.rad(DEFAULT_RAKE_DEG)
	local axis = (up * math.cos(rake) - forward * math.sin(rake)).Unit
	return axis, 2
end

local function configureSpring(spring: SpringConstraint, restDistance: number, load: number, unsprungMass: number)
	local stiffness = SUSPENSION_NATURAL_FREQ * SUSPENSION_NATURAL_FREQ * unsprungMass
	local damping = 2 * SUSPENSION_DAMPING_RATIO * SUSPENSION_NATURAL_FREQ * unsprungMass
	local sag = load / stiffness

	spring.Stiffness = stiffness
	spring.Damping = damping
	spring.FreeLength = restDistance + sag + SUSPENSION_PRELOAD
	spring.MaxLength = restDistance
	spring.MinLength = math.max(restDistance * (1 - SUSPENSION_TRAVEL_FACTOR), 0.1)
	spring.LimitsEnabled = true
	spring.Coils = 4
end

local function getSteeringSchemaParts(body: Model): { BasePart }
	local parts = {}
	for _, name in STEERING_PART_NAMES do
		local sub = body:FindFirstChild(name)
		if not sub then continue end
		for _, p in GeometryUtils.getInstanceParts(sub) do
			table.insert(parts, p)
		end
	end

	return parts
end

local function getChassisBodyParts(body: Model): { BasePart }
	local steerParts: { [BasePart]: boolean } = {}
	for _, p in getSteeringSchemaParts(body) do
		steerParts[p] = true
	end

	local parts = {}
	for _, p in GeometryUtils.getInstanceParts(body) do
		if not steerParts[p] then
			table.insert(parts, p)
		end
	end

	return parts
end

-- Public Functions

function Heuristics.clampMaxSteerDegrees(value: number): number
	return math.clamp(value, MIN_STEER_DEGREES, MAX_STEER_HARD_CAP)
end

function Heuristics.computeBikeCFrame(frontWheel: Wheel, rearWheel: Wheel, body: Instance): CFrame
	local frontPosition = getWheelPrimaryPart(frontWheel).Position
	local rearPosition = getWheelPrimaryPart(rearWheel).Position
	local wheelMidpoint = (frontPosition + rearPosition) * 0.5
	local bodyCentroid = GeometryUtils.computeVolumeWeightedCentroid(GeometryUtils.getInstanceParts(body))

	local forwardRaw = frontPosition - rearPosition
	assert(forwardRaw.Magnitude >= 1e-4, "TwoWheel: front and rear wheels coincide; cannot determine forward axis")
	local forward = forwardRaw.Unit

	local upRaw = bodyCentroid - wheelMidpoint
	local up = upRaw - upRaw:Dot(forward) * forward
	if up.Magnitude < 1e-4 then
		up = Vector3.yAxis - Vector3.yAxis:Dot(forward) * forward
		if up.Magnitude < 1e-4 then
			up = forward:Cross(Vector3.xAxis)
		end
	end

	up = up.Unit

	local right = forward:Cross(up).Unit
	up = right:Cross(forward).Unit

	local center = GeometryUtils.measureExtentsInFrame(
		GeometryUtils.getInstanceParts(body),
		CFrame.fromMatrix(Vector3.zero, right, up)
	)
	return CFrame.fromMatrix(center, right, up)
end

function Heuristics.prepareGeometry(
	_: Model,
	frontWheel: Wheel,
	rearWheel: Wheel,
	body: Instance
)
	local wheels = { frontWheel, rearWheel }
	for _, wheel in wheels do
		for _, part in GeometryUtils.getInstanceParts(wheel) do
			part.CanCollide = false
			part.Massless = true
			part.Anchored = true
		end
	end

	for _, part in GeometryUtils.getInstanceParts(body) do
		part.Massless = true
		part.Anchored = true
	end
end

function Heuristics.updateBikeRig(
	bikeRig: Model,
	frontWheel: Wheel,
	rearWheel: Wheel,
	body: Model,
	bikeCFrame: CFrame,
	_: any
)
	local chassis = bikeRig:WaitForChild("Chassis")
	local engine = bikeRig:WaitForChild("Engine")
	local steeringFolder = bikeRig:WaitForChild("Steering")
	local suspension = bikeRig:WaitForChild("Suspension")
	local wheelsFolder = bikeRig:WaitForChild("Wheels")
	local frontWheelModel = wheelsFolder:WaitForChild("WheelF")
	local rearWheelModel = wheelsFolder:WaitForChild("WheelR")

	local frontWheelPart = getWheelPrimaryPart(frontWheel)
	local rearWheelPart = getWheelPrimaryPart(rearWheel)
	local frontPos = frontWheelPart.Position
	local rearPos = rearWheelPart.Position
	local frontDiameter = getWheelDiameter(frontWheel)
	local rearDiameter = getWheelDiameter(rearWheel)

	local _, bodySizeRaw = GeometryUtils.measureExtentsInFrame(GeometryUtils.getInstanceParts(body), bikeCFrame)
	local bodySize = Vector3.new(
		math.max(bodySizeRaw.X, 0.05),
		math.max(bodySizeRaw.Y, 0.05),
		math.max(bodySizeRaw.Z, 0.05)
	)
	local bodyCenter = bikeCFrame.Position
	local chassisCFrame = bikeCFrame
	local chassisRotation = chassisCFrame.Rotation
	local forward = chassisCFrame.LookVector
	local bikeUp = chassisCFrame.UpVector
	local spinAxis = chassisCFrame.RightVector
	local rakeAxis, forkLength = computeRakeAxis(body, frontPos, forward, bikeUp)
	local forkPivotWorld = frontPos + rakeAxis * forkLength

	local chassisScale = Vector3.new(bodySize.X / chassis.Size.X, 1, bodySize.Z / chassis.Size.Z)
	chassis.Size = Vector3.new(bodySize.X, chassis.Size.Y, bodySize.Z)
	scaleAttachmentPositions(chassis, chassisScale)
	chassis.CFrame = chassisCFrame

	local rigFrontWheel = frontWheelModel:WaitForChild("Wheel")
	local rigRearWheel = rearWheelModel:WaitForChild("Wheel")
	local knuckle = frontWheelModel:WaitForChild("Knuckle")
	local forkSlider = frontWheelModel:WaitForChild("ForkSlider")
	local mount = rearWheelModel:WaitForChild("Mount")

	rescalePartGroup({ frontWheelModel }, frontDiameter / rigFrontWheel.Size.X)
	rescalePartGroup({ rearWheelModel }, rearDiameter / rigRearWheel.Size.X)

	rigFrontWheel.CFrame = chassisRotation + frontPos
	forkSlider.CFrame = chassisRotation + frontPos
	knuckle.CFrame = chassisRotation + frontPos
	rigRearWheel.CFrame = chassisRotation + rearPos
	mount.CFrame = chassisRotation + rearPos

	local frontWheelMass = rigFrontWheel:GetMass()
	local rearWheelMass = rigRearWheel:GetMass()
	setCarrierMass(knuckle, math.max(frontWheelMass * CARRIER_MASS_FACTOR, CARRIER_MIN_MASS))
	setCarrierMass(forkSlider, math.max(frontWheelMass * CARRIER_MASS_FACTOR, CARRIER_MIN_MASS))
	setCarrierMass(mount, math.max(rearWheelMass * CARRIER_MASS_FACTOR, CARRIER_MIN_MASS))

	local frontRest = math.max(frontDiameter * SUSPENSION_REST_FACTOR, 0.5)

	local forkAxisRight = forward:Cross(rakeAxis)
	if forkAxisRight.Magnitude < 1e-4 then
		forkAxisRight = spinAxis
	end

	local steerJointCFrame = CFrame.fromMatrix(forkPivotWorld, forkAxisRight.Unit, rakeAxis)
	local forkMotor = chassis:WaitForChild("ForkMotor")
	forkMotor.Part0 = chassis
	forkMotor.Part1 = knuckle
	forkMotor.C0 = chassis.CFrame:Inverse() * steerJointCFrame
	forkMotor.C1 = knuckle.CFrame:Inverse() * steerJointCFrame

	local forkPrismatic = steeringFolder:WaitForChild("ForkPrismatic")
	forkPrismatic.Attachment0 = makeAttachment(knuckle, attachCFrame(frontPos, rakeAxis), "KnucklePrismaticAttachment")
	forkPrismatic.Attachment1 = makeAttachment(forkSlider, attachCFrame(frontPos, rakeAxis), "SliderPrismaticAttachment")
	forkPrismatic.ActuatorType = Enum.ActuatorType.None

	local frontSpring = suspension:WaitForChild("WheelFSuspension")
	frontSpring.Attachment0 =
		makeAttachment(knuckle, attachCFrame(frontPos + rakeAxis * frontRest, rakeAxis), "KnuckleSpringAttachment")
	frontSpring.Attachment1 = makeAttachment(forkSlider, attachCFrame(frontPos, rakeAxis), "SliderSpringAttachment")

	local frontMotor = engine:WaitForChild("WheelFMotor")
	frontMotor.Attachment0 = makeAttachment(forkSlider, attachCFrame(frontPos, spinAxis), "SliderMotorAttachment")
	frontMotor.Attachment1 = makeAttachment(rigFrontWheel, attachCFrame(frontPos, spinAxis), "FrontWheelMotorAttachment")
	frontMotor.ActuatorType = Enum.ActuatorType.Motor
	frontMotor.MotorMaxAcceleration = math.huge
	frontMotor.AngularVelocity = 0
	frontMotor.MotorMaxTorque = 0

	local rearRest = math.max(rearDiameter * SUSPENSION_REST_FACTOR, 0.5)

	local mountWeld = mount:FindFirstChild("WeldConstraint")
	if mountWeld then
		mountWeld.Enabled = false
	end

	local rearPrismatic = mount:WaitForChild("RearPrismatic")
	rearPrismatic.Attachment0 =
		makeAttachment(chassis, attachCFrame(rearPos, bikeUp), "ChassisRearPrismaticAttachment")
	rearPrismatic.Attachment1 = makeAttachment(mount, attachCFrame(rearPos, bikeUp), "MountPrismaticAttachment")

	local rearSpring = suspension:WaitForChild("WheelRSuspension")
	rearSpring.Attachment0 =
		makeAttachment(chassis, attachCFrame(rearPos + bikeUp * rearRest, bikeUp), "ChassisRearSpringAttachment")
	rearSpring.Attachment1 = makeAttachment(mount, attachCFrame(rearPos, bikeUp), "MountSpringAttachment")

	local rearMotor = engine:WaitForChild("WheelRMotor")
	rearMotor.Attachment0 = makeAttachment(mount, attachCFrame(rearPos, spinAxis), "MountMotorAttachment")
	rearMotor.Attachment1 = makeAttachment(rigRearWheel, attachCFrame(rearPos, spinAxis), "RearWheelMotorAttachment")
	rearMotor.ActuatorType = Enum.ActuatorType.Motor
	rearMotor.MotorMaxAcceleration = math.huge
	rearMotor.MotorMaxTorque = 0

	local gravity = workspace.Gravity
	local sprungMass = 0
	for _, descendant in bikeRig:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end
		if descendant.Massless then continue end
		if descendant == rigFrontWheel or descendant == rigRearWheel then continue end
		if descendant == knuckle or descendant == forkSlider or descendant == mount then continue end
		sprungMass += descendant:GetMass()
	end

	local frontProjection = frontPos:Dot(forward)
	local rearProjection = rearPos:Dot(forward)
	local wheelbase = frontProjection - rearProjection
	local frontLoadFraction = 0.5
	if math.abs(wheelbase) > 1e-3 then
		frontLoadFraction = math.clamp((bodyCenter:Dot(forward) - rearProjection) / wheelbase, 0.1, 0.9)
	end

	local totalWeight = sprungMass * gravity
	local frontUnsprung = forkSlider:GetMass() + frontWheelMass
	local rearUnsprung = mount:GetMass() + rearWheelMass
	configureSpring(frontSpring, frontRest, totalWeight * frontLoadFraction, frontUnsprung)
	configureSpring(rearSpring, rearRest, totalWeight * (1 - frontLoadFraction), rearUnsprung)

	forkPrismatic.LowerLimit = frontRest - frontSpring.MaxLength
	forkPrismatic.UpperLimit = frontRest - frontSpring.MinLength
	forkPrismatic.LimitsEnabled = true
	rearPrismatic.LowerLimit = rearRest - rearSpring.MaxLength
	rearPrismatic.UpperLimit = rearRest - rearSpring.MinLength
	rearPrismatic.LimitsEnabled = true

	suspension:SetAttribute("frontSuspensionStiffness", frontSpring.Stiffness)
	suspension:SetAttribute("frontSuspensionDamping", frontSpring.Damping)
	suspension:SetAttribute("frontSuspensionLength", frontSpring.FreeLength)
	suspension:SetAttribute("rearSuspensionStiffness", rearSpring.Stiffness)
	suspension:SetAttribute("rearSuspensionDamping", rearSpring.Damping)
	suspension:SetAttribute("rearSuspensionLength", rearSpring.FreeLength)

	local balanceTorque = chassis:WaitForChild("BalanceTorque")
	balanceTorque.Attachment0 = makeAttachment(chassis, chassisCFrame, "BalanceAttachment")

	local function addNoCollide(partA: BasePart, partB: BasePart)
		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = partA
		noCollide.Part1 = partB
		noCollide.Parent = partA
	end

	addNoCollide(rigFrontWheel, chassis)
	addNoCollide(rigFrontWheel, knuckle)
	addNoCollide(rigFrontWheel, forkSlider)
	addNoCollide(rigRearWheel, chassis)
	addNoCollide(rigRearWheel, mount)
	addNoCollide(knuckle, chassis)
	addNoCollide(forkSlider, chassis)
	addNoCollide(mount, chassis)

	chassis.LeftNitroEmitterAttachment.Position = Vector3.new(0, 0, bodySize.Z * 0.5)
	chassis.RightNitroEmitterAttachment.Position = Vector3.new(0, 0, bodySize.Z * 0.5)
	chassis.DrivePromptAttachment.DrivePrompt.MaxActivationDistance = bodySize.X * 0.5 + 10
	chassis.HoodCameraAttachment.Position = Vector3.new(0, chassis.Size.Y, -bodySize.Z * 0.5)
end

function Heuristics.attachGeometryToBikeRig(
	bikeRig: Model,
	frontWheel: Instance,
	rearWheel: Instance,
	body: Model,
	extraParts: { PVInstance }
)
	local function weldPartsToParent(parts: { BasePart }, parent: BasePart, weldName: string)
		for _, part in parts do
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = parent
			weld.Part1 = part
			weld.Name = weldName
			weld.Parent = parent
		end
	end

	local rigChassis = bikeRig:FindFirstChild("Chassis")
	local wheelsFolder = bikeRig:WaitForChild("Wheels")
	local frontWheelModel = wheelsFolder:WaitForChild("WheelF")
	local rearWheelModel = wheelsFolder:WaitForChild("WheelR")
	local frontKnuckle = frontWheelModel:WaitForChild("Knuckle")
	local frontWheelPart = frontWheelModel:WaitForChild("Wheel")
	local rearWheelPart = rearWheelModel:WaitForChild("Wheel")

	local chassisBodyParts = getChassisBodyParts(body)
	weldPartsToParent(chassisBodyParts, rigChassis, "BodyWeld")

	local steeringParts = getSteeringSchemaParts(body)
	weldPartsToParent(steeringParts, frontKnuckle, "SteeringWeld")

	local extraPartParts: { BasePart } = {}
	for _, extraPart in extraParts do
		local parts = GeometryUtils.getInstanceParts(extraPart)
		weldPartsToParent(parts, rigChassis, "ExtraPartWeld")
		for _, part in parts do
			table.insert(extraPartParts, part)
		end
	end

	local frontSourceParts = GeometryUtils.getInstanceParts(frontWheel)
	weldPartsToParent(frontSourceParts, frontWheelPart, frontWheel.Name .. "Weld")

	local rearSourceParts = GeometryUtils.getInstanceParts(rearWheel)
	weldPartsToParent(rearSourceParts, rearWheelPart, rearWheel.Name .. "Weld")

	local rigWheelParts = { frontWheelPart, rearWheelPart }

	local function addNoCollideBetween(parts: { BasePart }, others: { BasePart })
		for _, part in parts do
			for _, other in others do
				local noCollide = Instance.new("NoCollisionConstraint")
				noCollide.Part0 = part
				noCollide.Part1 = other
				noCollide.Parent = part
			end
		end
	end

	addNoCollideBetween(chassisBodyParts, rigWheelParts)
	addNoCollideBetween(steeringParts, rigWheelParts)

	local rigParts: { BasePart } = {}
	for _, descendant in bikeRig:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(rigParts, descendant)
		end
	end
	addNoCollideBetween(extraPartParts, rigParts)
end

-- Finds the stretch of a seat schema that actually has geometry under it, by
-- raycasting straight down onto it in body space at intervals along its length.
--
-- A bounding box is a poor stand-in for author-supplied seat geometry. Bike10's
-- seat is three CSG rails whose boxes are 3.5 studs long, while the solid they
-- describe fills only the rear 1.9 studs; centring on the box put the rider off
-- the front edge of the seat, in mid-air. Rays hit the solid, so they find the
-- seat wherever inside its box it happens to be.
--
-- Returns the midpoint of the hit stretch and the surface height there, or nil
-- if nothing answered.
local function probeSeatSurface(
	parts: { BasePart },
	bodyCFrame: CFrame,
	minLocalY: number,
	maxLocalY: number,
	minLocalZ: number,
	maxLocalZ: number
): (number?, number?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	params.IgnoreWater = true

	-- Start clear of the top face and reach past the bottom one, so a ray cannot
	-- begin inside the seat and miss it.
	local reach = (maxLocalY - minLocalY) + 2
	local samples = {}
	for i = 0, SEAT_SURFACE_SAMPLES do
		local z = minLocalZ + (maxLocalZ - minLocalZ) * (i / SEAT_SURFACE_SAMPLES)
		local origin = bodyCFrame:PointToWorldSpace(Vector3.new(0, maxLocalY + 1, z))
		local result = workspace:Raycast(origin, -bodyCFrame.UpVector * reach, params)
		if result then
			table.insert(samples, { z = z, y = bodyCFrame:PointToObjectSpace(result.Position).Y })
		end
	end

	if #samples == 0 then
		return nil, nil
	end

	local sitZ = (samples[1].z + samples[#samples].z) * 0.5

	local nearest, nearestDistance = samples[1], math.huge
	for _, sample in samples do
		local distance = math.abs(sample.z - sitZ)
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = sample
		end
	end

	return sitZ, nearest.y
end

function Heuristics.placeDriverSeatOnSchemaSeat(root: Model, vehicleSeat: VehicleSeat, body: Model, bikeCFrame: CFrame)
	local seatSchema = body:FindFirstChild("seat")
	if not seatSchema or not (seatSchema:IsA("BasePart") or seatSchema:IsA("Model")) then
		SeatHelpers.placeSeatOnModel(root, vehicleSeat, "ontop")
		return
	end

	local seatParts = GeometryUtils.getInstanceParts(seatSchema)
	if #seatParts == 0 then
		SeatHelpers.placeSeatOnModel(root, vehicleSeat, "ontop")
		return
	end

	local bodyPrimary = body.PrimaryPart or GeometryUtils.getOrSetPrimaryPart(body)
	local bodyCFrame = bodyPrimary.CFrame

	local minLocalX, maxLocalX = math.huge, -math.huge
	local minLocalY, maxLocalY = math.huge, -math.huge
	local minLocalZ, maxLocalZ = math.huge, -math.huge
	for _, part in seatParts do
		local halfX, halfY, halfZ = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5
		for _, signX in { -1, 1 } do
			for _, signY in { -1, 1 } do
				for _, signZ in { -1, 1 } do
					local cornerWorld = part.CFrame * CFrame.new(signX * halfX, signY * halfY, signZ * halfZ)
					local cornerLocal = bodyCFrame:PointToObjectSpace(cornerWorld.Position)
					if cornerLocal.X < minLocalX then minLocalX = cornerLocal.X end
					if cornerLocal.X > maxLocalX then maxLocalX = cornerLocal.X end
					if cornerLocal.Y < minLocalY then minLocalY = cornerLocal.Y end
					if cornerLocal.Y > maxLocalY then maxLocalY = cornerLocal.Y end
					if cornerLocal.Z < minLocalZ then minLocalZ = cornerLocal.Z end
					if cornerLocal.Z > maxLocalZ then maxLocalZ = cornerLocal.Z end
				end
			end
		end
	end

	local schemaWidth = maxLocalX - minLocalX
	local newSeatX = math.min(schemaWidth, DEFAULT_DRIVER_SEAT_X)
	if newSeatX <= 0 then
		newSeatX = DEFAULT_DRIVER_SEAT_X
	end

	vehicleSeat.Size = Vector3.new(newSeatX, vehicleSeat.Size.Y, vehicleSeat.Size.Z)

	local sitLocalZ, surfaceLocalY =
		probeSeatSurface(seatParts, bodyCFrame, minLocalY, maxLocalY, minLocalZ, maxLocalZ)

	local seatLocalY, seatLocalZ
	if surfaceLocalY and sitLocalZ then
		seatLocalY = surfaceLocalY - SEATED_HIP_GAP - SEAT_SINK - vehicleSeat.Size.Y * 0.5
		seatLocalZ = sitLocalZ
	else
		-- Nothing answered the probe: geometry that does not take raycasts, or a
		-- schema so thin every sample slipped past it. Fall back to the middle of
		-- the box, which at worst leaves the rider half its height out of place
		-- and cannot strand them off the end of it.
		seatLocalY = (minLocalY + maxLocalY) * 0.5
		seatLocalZ = (minLocalZ + maxLocalZ) * 0.5
	end

	-- The seat POSITION comes from the seat geometry in the body's own frame
	-- (round-tripped through world, so the body part's arbitrary authored
	-- orientation does not move it). The seat ORIENTATION must be the wheel-derived
	-- bike frame, not the body part's: the chassis drives along bikeCFrame.LookVector
	-- (front wheel + handlebars), and the rider faces the seat's LookVector, so
	-- taking rotation from the body part left the rider facing backward on any bike
	-- whose body part was authored pointing away from its own front wheel. (A bare
	-- position instead carries identity rotation -- world -Z -- which seated the
	-- rider sideways; bikeCFrame fixes both.)
	local seatPosition = (bodyCFrame * CFrame.new((minLocalX + maxLocalX) * 0.5, seatLocalY, seatLocalZ)).Position
	vehicleSeat.CFrame = CFrame.fromMatrix(seatPosition, bikeCFrame.RightVector, bikeCFrame.UpVector)
end

-- Return

return Heuristics

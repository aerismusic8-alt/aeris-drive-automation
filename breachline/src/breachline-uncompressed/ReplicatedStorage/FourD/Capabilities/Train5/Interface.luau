--[[
Train5 Capability - Track-following train engine

Uses Trackable behavior exclusively (waypoint following). Any extra model or part inside a car
is cosmetic and gets welded to that car's body. An optional 'chimney' model mounts the
ReplicatedStorage.Assets.VFX.TrainSmoke emitter, which ramps with track speed.
Schema: Train5 (body, left front wheel, right front wheel, left rear wheel, right rear wheel)

Multi-car consists are an author-only feature: set the MultiCar attribute to true on the tagged
model and name each car model "1", "2", ... Car 1 is the engine and carries the driver seat;
every other car is cosmetic and tracks the engine. ManualCarAlignment switches car spacing to
the authored pivot distances. Neither attribute is declared in the bind parameter schema, so
the generation pipeline never sees them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Beh = FourD:FindFirstChild("Behaviors")
local Trackable = require(Beh.Trackable.makeFunctional)
local HelpUI = require(FourD.Common.HelpUI)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local SeatHelpers = require(FourD.Common.SeatHelpers)

local WHEEL_NAMES = { "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" }
local MIN_AXIS_LENGTH = 0.001

local function attachSmokeEmitter(carModel: Model, chimney: Instance, bodyAnchor: BasePart): boolean
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	local template = vfx and vfx:FindFirstChild("TrainSmoke")
	if not template or not template:IsA("BasePart") then
		warn("[Train5] Missing ReplicatedStorage.Assets.VFX.TrainSmoke")
		return false
	end

	local chimneyParts = GeometryUtils.getInstanceParts(chimney)
	if #chimneyParts == 0 then
		warn("[Train5] 'chimney' has no parts to mount smoke on")
		return false
	end

	local frame = bodyAnchor.CFrame
	local chimneyCenter, chimneySize = GeometryUtils.measureExtentsInFrame(chimneyParts, frame)

	local smoke = template:Clone()
	smoke.Name = "SmokeEmitter"

	local emitter = smoke:FindFirstChildWhichIsA("ParticleEmitter")
	if emitter then
		emitter.Enabled = false
	end

	local topCenter = chimneyCenter + frame.UpVector * ((chimneySize.Y + smoke.Size.Y) / 2)
	smoke.CFrame = CFrame.fromMatrix(topCenter, frame.RightVector, frame.UpVector)
	smoke.Parent = carModel

	return true
end

local function cloneTemplates(carModel: Model, scriptNames: { string })
	for _, scriptName in ipairs(scriptNames) do
		local template = script.Parent:FindFirstChild(scriptName)
		if template then
			local clone = template:Clone()
			if clone:IsA("BaseScript") then
				clone.Enabled = true
			end
			clone.Parent = carModel
		end
	end
end

local function addDriverSeat(carModel: Model, bodyAnchor: BasePart, seatPosition: string)
	local vehicleSeat = Instance.new("VehicleSeat")
	vehicleSeat.Name = "DriverSeat"
	vehicleSeat.Size = Vector3.new(1.5, 0.3, 1.5)
	vehicleSeat.Transparency = 1
	vehicleSeat.CanCollide = false
	vehicleSeat.Massless = true
	vehicleSeat.Anchored = false
	vehicleSeat.MaxSpeed = 0
	vehicleSeat.Torque = 0
	vehicleSeat.HeadsUpDisplay = false
	vehicleSeat.Parent = carModel
	SeatHelpers.placeSeatOnModel(carModel, vehicleSeat, seatPosition)
	ConstructionHelpers.makeWeld(bodyAnchor, vehicleSeat)

	local extents = carModel:GetExtentsSize()
	local seatPrompt = Instance.new("ProximityPrompt")
	seatPrompt.Name = "SeatPrompt"
	seatPrompt.ActionText = "Drive"
	seatPrompt.ObjectText = "Train"
	seatPrompt.HoldDuration = 0
	seatPrompt.RequiresLineOfSight = false
	seatPrompt.MaxActivationDistance = math.max(extents.X, extents.Z) * 1.5 + 6
	seatPrompt.Parent = vehicleSeat
end

local function hasNumberedChildModels(model: Model): boolean
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and tonumber(child.Name) then
			return true
		end
	end

	return false
end

local function wheelParts(carModel: Model, wheelName: string): { BasePart }?
	local wheel = carModel:FindFirstChild(wheelName)
	if not wheel or not (wheel:IsA("Model") or wheel:IsA("BasePart")) then
		return nil
	end

	local parts = GeometryUtils.getInstanceParts(wheel)
	if #parts == 0 then
		return nil
	end
	return parts
end

local function partsCenter(parts: { BasePart }): Vector3
	local sum = Vector3.zero
	for _, part in ipairs(parts) do
		sum += part.Position
	end
	return sum / #parts
end

---Derives a car's reference frame from the ground contact points of its four wheels, independently of
---any authored pivot or PrimaryPart. Each wheel's radius is measured from its own geometry, so
---locomotives with differently sized leading and driving wheels still yield a level frame. Falls back
---to `fallbackAnchor` for cars without a full set of wheels.
local function buildCarFrame(carModel: Model, fallbackAnchor: BasePart): CFrame
	local wheelPartLists = {}
	local centers = {}
	for index, wheelName in ipairs(WHEEL_NAMES) do
		local parts = wheelParts(carModel, wheelName)
		if not parts then
			return fallbackAnchor.CFrame
		end
		wheelPartLists[index] = parts
		centers[index] = partsCenter(parts)
	end

	local right = (centers[2] + centers[4]) - (centers[1] + centers[3])
	if right.Magnitude < MIN_AXIS_LENGTH then
		return fallbackAnchor.CFrame
	end
	right = right.Unit

	local centerForward = (centers[1] + centers[2]) - (centers[3] + centers[4])
	centerForward -= right * centerForward:Dot(right)
	if centerForward.Magnitude < MIN_AXIS_LENGTH then
		return fallbackAnchor.CFrame
	end

	local radialAxis = right:Cross(centerForward.Unit).Unit
	local contacts = {}
	local contactSum = Vector3.zero
	for index, parts in ipairs(wheelPartLists) do
		local _, size = GeometryUtils.measureExtentsInFrame(parts, CFrame.fromMatrix(centers[index], right, radialAxis))
		contacts[index] = centers[index] - radialAxis * (size.Y / 2)
		contactSum += contacts[index]
	end

	local forward = (contacts[1] + contacts[2]) - (contacts[3] + contacts[4])
	forward -= right * forward:Dot(right)
	if forward.Magnitude < MIN_AXIS_LENGTH then
		return fallbackAnchor.CFrame
	end
	forward = forward.Unit

	local up = right:Cross(forward)
	if up.Magnitude < MIN_AXIS_LENGTH then
		return fallbackAnchor.CFrame
	end

	return CFrame.lookAlong(contactSum * 0.25, forward, up.Unit)
end

local function buildCar(carModel: Model, isEngine: boolean, options: { [string]: any })
	local body = carModel:FindFirstChild("body")
	if not body then
		if hasNumberedChildModels(carModel) then
			error(
				"[Train5] Missing 'body' in "
					.. carModel:GetFullName()
					.. " - it contains numbered child models, so set the MultiCar attribute to true to treat them as train cars"
			)
		end

		error("[Train5] Missing 'body' in " .. carModel:GetFullName())
	end

	if isEngine then
		for _, wheelName in ipairs(WHEEL_NAMES) do
			if not carModel:FindFirstChild(wheelName) then
				error("[Train5] Missing '" .. wheelName .. "' in " .. carModel:GetFullName())
			end
		end
	end

	local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
	carModel.PrimaryPart = bodyAnchor

	local chimney = carModel:FindFirstChild("chimney")
	local hasSmoke = chimney ~= nil and attachSmokeEmitter(carModel, chimney, bodyAnchor)

	for _, desc in ipairs(carModel:GetDescendants()) do
		if desc:IsA("BasePart") and desc ~= bodyAnchor then
			desc.Anchored = false
			desc.CanCollide = false
			desc.Massless = true
			ConstructionHelpers.makeWeld(bodyAnchor, desc)
		end
	end

	bodyAnchor.Anchored = false

	local templates = { "WheelSpin" }

	if isEngine then
		addDriverSeat(carModel, bodyAnchor, options.seatPosition or "inside")
		table.insert(templates, "SeatPrompt")
		table.insert(templates, "SeatPromptClient")
		table.insert(templates, "DriverClient")
		table.insert(templates, "DriverVisibility")
	end

	if hasSmoke then
		table.insert(templates, "SmokeRamp")
	end

	local rideAnchor = GeometryUtils.createBoundingBoxAnchor(carModel, buildCarFrame(carModel, bodyAnchor), "CarAnchor")
	ConstructionHelpers.makeWeld(bodyAnchor, rideAnchor)

	cloneTemplates(carModel, templates)
end

local function collectCars(root: Model): { Model }
	local carModels = {}
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") and tonumber(child.Name) then
			table.insert(carModels, child)
		elseif child:IsA("Model") or child:IsA("BasePart") then
			warn("[Train5] Ignoring non-numbered child in MultiCar model: " .. child.Name)
		end
	end

	table.sort(carModels, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)

	if #carModels == 0 then
		error("[Train5] MultiCar is enabled but no numbered car models were found")
	end

	return carModels
end

local function makeFunctional(root: Model, config: { [string]: any }?): Model
	local options = config or {}
	local multiCar = options.MultiCar == true
	local carModels = if multiCar then collectCars(root) else { root }

	for index, carModel in ipairs(carModels) do
		buildCar(carModel, index == 1, options)
	end

	root.PrimaryPart = carModels[1].PrimaryPart

	Trackable.setup(root, {
		driveMode = "track",
		maxTrackSpeed = options.maxTrackSpeed or 45,
		trackAcceleration = options.trackAcceleration or 12,
		liftSpeed = options.liftSpeed,
		trackEnterDistance = 24,
		requireDriver = options.requireDriver ~= false,
		targetTrackSpeed = options.targetSpeed,
		autoMode = options.autoMode == true,
		autoModeWaitTime = options.autoModeWaitTime,
		autoModeStartType = options.autoModeStartType,
		noRollback = options.noRollback == true,
		flipDirection = options.flipDirection == true,
		cars = if multiCar then carModels else nil,
		manualCarAlignment = options.ManualCarAlignment == true,
	})

	HelpUI.registerState(root, "Train5_Driver", {
		Sources = {
			{ Type = "Manual", Id = "Forward", Description = "Forward", Keyboard = "W", Gamepad = "ButtonR2" },
			{ Type = "Manual", Id = "Reverse", Description = "Reverse", Keyboard = "S", Gamepad = "ButtonL2" },
			{ Type = "Set", SetId = "Trackable" },
		},
	})
	HelpUI.registerState(root, "Train5_Rider", {
		Sources = {
			{ Type = "Set", SetId = "Trackable" },
		},
	})
	root:SetAttribute("HelpUI_DriverState", "Train5_Driver")
	root:SetAttribute("HelpUI_RiderState", "Train5_Rider")

	return root
end

local Train5 = CapabilityBase.createChild()

function Train5:getCapabilityDocumentation()
	return [[
The Train5Capability creates a train engine with throttle control.
The engine follows predefined track waypoints via the Trackable behavior.
By default the engine only moves while a player occupies the driver seat (requireDriver). Set requireDriver
to false for a free engine, or set targetSpeed to drive the engine at an exact speed with no driver.
Set autoMode to true for an unmanned run: the engine stops at the station (the track's first waypoint) each lap,
waits autoModeWaitTime seconds, then departs per autoModeStartType ("soft" ramps up to liftSpeed, "launch" jumps to it).
autoMode overrides requireDriver and ignores driver throttle input entirely, so pair it with targetSpeed: this engine has
no gravity to sustain it and would otherwise decay to a standstill once it leaves the station. All three autoMode
attributes can also be flipped at runtime on the train model.
Set noRollback to true to forbid backward travel along the track.
If the model contains a part or model named "chimney", steam particles are mounted on top of it and ramp
with the engine's speed while the driver seat is occupied.
Any other parts or models inside the train are cosmetic and are welded to the body automatically.
Requires track waypoints to be defined in workspace under a Tracks folder.
]]
end

function Train5:getModelSpecs()
	return {
		{
			name = "train",
			modelSchema = "Train5",
			description = "a train engine with a body and four wheels",
		},
	}
end

function Train5:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "inside",
			description = "Position of the driver seat",
		})
		:addOptionalArgument("maxTrackSpeed", { type = "number", default = 45, description = "Max speed on track" })
		:addOptionalArgument("trackAcceleration", {
			type = "number",
			default = 12,
			minimum = 0,
			description = "How quickly the engine gains or sheds speed along the track",
		})
		:addOptionalArgument("liftSpeed", { type = "number", default = 8, description = "Minimum speed enforced on chain-lift track segments, and the departure speed used by autoMode" })
		:addOptionalArgument("requireDriver", {
			type = "boolean",
			default = true,
			description = "When true, the engine only moves while a player occupies the driver seat",
		})
		:addOptionalArgument("targetSpeed", {
			type = "number",
			description = "When set, the server drives the engine toward this exact speed, overriding driver input",
		})
		:addOptionalArgument("autoMode", {
			type = "boolean",
			default = false,
			description = "When true, the engine runs unmanned: it stops at the station (first track waypoint) each lap, waits, then departs automatically",
		})
		:addOptionalArgument("autoModeWaitTime", {
			type = "number",
			default = 5,
			description = "Seconds the engine waits at the station before departing when autoMode is enabled",
		})
		:addOptionalArgument("autoModeStartType", {
			type = "string",
			default = "soft",
			description = "How the engine departs the station in autoMode: 'soft' accelerates gradually until it reaches liftSpeed, 'launch' instantly sets speed to liftSpeed",
		})
		:addOptionalArgument("noRollback", {
			type = "boolean",
			default = false,
			description = "When true, the engine can never move backward along the track: negative speed is clamped to zero (reverse throttle disabled)",
		})
		:build()
end

function Train5:getCapabilitySelectionExamples()
	return {
		{
			user = "a train engine",
			assistant = {
				capability_reasoning = "A train engine is a locomotive that rides a track. Train5Capability handles this.",
				capability_selection = "Train5Capability",
				overall_size_reasoning = "A train engine is about 3m tall, 3m wide, 12m long.",
				overall_size_selection = { x = 3, y = 3, z = 12 },
			},
		},
		{
			user = "a steam train",
			assistant = {
				capability_reasoning = "A steam train is a locomotive with a chimney. Train5Capability handles this and emits steam from a chimney when one is present.",
				capability_selection = "Train5Capability",
				overall_size_reasoning = "A steam train engine is about 3.5m tall, 3m wide, 14m long.",
				overall_size_selection = { x = 3, y = 3.5, z = 14 },
			},
		},
	}
end

function Train5:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("Train5Capability configuration error: " .. errorMsg) end

	local trainModel = generatedModels["train"]
	if not trainModel then error("Could not find 'train' model") end

	return makeFunctional(trainModel, parameters)
end

return Train5

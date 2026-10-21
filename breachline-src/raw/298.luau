--[[
RollercoasterCart3 Capability - Track-following cart with gravity-based speed

Uses Trackable behavior with gravity enabled. Speed increases on downslopes
and decreases on upslopes. Minimal throttle for chain-lift sections.
Schema: RollercoasterCart3 (cart + rollers + seat)
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Beh = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Trackable = require(Beh.Trackable.makeFunctional)
local HelpUI = require(FourD.Common.HelpUI)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local SeatHelpers = require(FourD.Common.SeatHelpers)

local function hasNumberedChildModels(model: Model): boolean
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and tonumber(child.Name) then
			return true
		end
	end

	return false
end

---World-space ground-contact point of a car's `rollers`: the centre of the roller bounds
---measured in `frame`'s axes, pushed down to their lowest extent. Every car in a train shares
---this datum no matter how tall or ornate its body is, which a bounding-box centre does not.
---@param carModel -- Car model to measure.
---@param frame -- Supplies the axes to measure in; its position is ignored.
---@return contact -- World-space contact point, or nil when the car has no roller geometry.
local function rollerContactPoint(carModel: Model, frame: CFrame): Vector3?
	local rollers = carModel:FindFirstChild("rollers")
	if not rollers or not (rollers:IsA("BasePart") or rollers:IsA("Model")) then return nil end

	local parts = GeometryUtils.getInstanceParts(rollers)
	if #parts == 0 then return nil end

	local center, size = GeometryUtils.measureExtentsInFrame(parts, frame)
	return center - frame.UpVector * (size.Y / 2)
end

---Frame of a car's `rollers`, used to decide which way the car faces once it is on the track.
---The body is the wrong datum for a train that mixes assets: it is also the weld root, so its
---rotation relative to itself is always zero, and the half-turn an author gives a body that was
---modelled backwards is discarded at build time, leaving that car riding reversed. The rollers
---sit on the rail and are placed alike across a train, so measuring from them keeps each body's
---authored facing intact.
---@param carModel -- Car model to read.
---@return frame -- CFrame of the roller geometry, or nil when the car has none.
local function rollerFrame(carModel: Model): CFrame?
	local rollers = carModel:FindFirstChild("rollers")
	if not rollers or not (rollers:IsA("BasePart") or rollers:IsA("Model")) then return nil end

	local part = GeometryUtils.getOrSetPrimaryPart(rollers)
	return if part then part.CFrame else nil
end

local function buildCar(carModel: Model, isLead: boolean, alignment: { Height: number?, Offset: number }?): BasePart
	local cartPart = carModel:FindFirstChild("cart")
	local anchor
	if cartPart then
		anchor = if cartPart:IsA("BasePart") then cartPart else GeometryUtils.getOrSetPrimaryPart(cartPart)
	else
		anchor = carModel:FindFirstChildWhichIsA("BasePart", true)
		warn(
			"[RollercoasterCart3] No 'cart' child in "
				.. carModel:GetFullName()
				.. ", so its reference frame falls back to '"
				.. (if anchor then anchor.Name else "<none>")
				.. "', whichever BasePart happens to come first. Rename the body model or part to 'cart'."
		)
	end

	if not anchor then error("No BasePart found in RollercoasterCart car: " .. carModel:GetFullName()) end
	carModel.PrimaryPart = anchor

	for _, desc in ipairs(carModel:GetDescendants()) do
		if desc:IsA("BasePart") and desc ~= anchor then
			desc.Anchored = false
			desc.CanCollide = false
			desc.Massless = true
			ConstructionHelpers.makeWeld(anchor, desc)
		end
	end

	anchor.Anchored = false

	-- Shared datum for this car when RollerAlignment is on. Both the ride seat's facing and the
	-- CarAnchor's axes are taken from it instead of from the body, so a body carrying an authored
	-- half-turn keeps that turn without spinning the rider around with it.
	local carFrame = if alignment then rollerFrame(carModel) else nil

	local rideSeat
	if isLead then
		local vehicleSeat = Instance.new("VehicleSeat")
		vehicleSeat.Name = "DriverSeat"
		vehicleSeat.MaxSpeed = 0
		vehicleSeat.Torque = 0
		vehicleSeat.HeadsUpDisplay = false
		rideSeat = vehicleSeat
	else
		rideSeat = Instance.new("Seat")
		rideSeat.Name = "PassengerSeat"
	end

	rideSeat.Size = Vector3.new(1.5, 0.3, 1.5)
	rideSeat.Transparency = 1
	rideSeat.CanCollide = false
	rideSeat.Massless = true
	rideSeat.Anchored = false
	rideSeat.Parent = carModel
	SeatHelpers.placeSeatOnModel(carModel, rideSeat, "inside")
	if carFrame then
		-- The helper aims the seat along the body, which is exactly the part that may be turned
		-- around, so re-aim it along the shared frame. Its computed position is kept as-is.
		rideSeat.CFrame = CFrame.lookAlong(rideSeat.Position, carFrame.LookVector)
	end
	ConstructionHelpers.makeWeld(anchor, rideSeat)

	local extents = carModel:GetExtentsSize()
	local seatPrompt = Instance.new("ProximityPrompt")
	seatPrompt.Name = "SeatPrompt"
	seatPrompt.ActionText = "Ride"
	seatPrompt.ObjectText = "Rollercoaster Cart"
	seatPrompt.HoldDuration = 0
	seatPrompt.RequiresLineOfSight = false
	seatPrompt.MaxActivationDistance = math.max(extents.X, extents.Z) * 1.5 + 6
	seatPrompt.Parent = rideSeat

	for _, scriptName in ipairs({ "SeatPrompt", "SeatPromptClient", "DriverClient" }) do
		local template = script.Parent:FindFirstChild(scriptName)
		if template then
			local clone = template:Clone()
			if clone:IsA("BaseScript") then
				clone.Enabled = true
			end
			clone.Parent = carModel
		end
	end

	-- Axes only: the box is still measured over the whole car, but taking those axes from the
	-- shared frame is what preserves each body's authored facing. A car whose rollers are
	-- missing falls back to its body and warns below.
	local rideAnchor = GeometryUtils.createBoundingBoxAnchor(carModel, carFrame or anchor.CFrame, "CarAnchor")

	if alignment then
		local contact = rollerContactPoint(carModel, rideAnchor.CFrame)
		if contact then
			local up = rideAnchor.CFrame.UpVector
			local currentHeight = (rideAnchor.Position - contact):Dot(up)
			-- The lead car sets the datum, so it keeps the pose the author gave it and the
			-- rest of the train moves to match, rather than every car shifting at once.
			alignment.Height = alignment.Height or currentHeight
			-- Vertical only: leaving the along-track and lateral position on the bounding-box
			-- centre keeps GetExtentsSize (and so Trackable's car spacing) unchanged.
			rideAnchor.CFrame = rideAnchor.CFrame + up * ((alignment.Height - alignment.Offset) - currentHeight)
		else
			warn(
				"[RollercoasterCart3] RollerAlignment is on but "
					.. carModel:GetFullName()
					.. " has no 'rollers' geometry, so this car still rides on its bounding-box centre."
			)
		end
	end

	ConstructionHelpers.makeWeld(anchor, rideAnchor)

	return rideAnchor
end

local function makeFunctional(root: Model, config: { [string]: any }?): Model
	local options = config or {}

	local carModels = {}
	if options.MultiCar == true then
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("Model") and tonumber(child.Name) then
				table.insert(carModels, child)
			elseif child:IsA("Model") or child:IsA("BasePart") then
				warn("[RollercoasterCart3] Ignoring non-numbered child in MultiCar model: " .. child.Name)
			end
		end

		table.sort(carModels, function(a, b)
			return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
		end)

		if #carModels == 0 then
			error("[RollercoasterCart3] MultiCar is enabled but no numbered car models were found")
		end
	else
		if hasNumberedChildModels(root) then
			warn(
				"[RollercoasterCart3] "
					.. root:GetFullName()
					.. " contains numbered child models but MultiCar is not enabled, so the whole model is being built as a single cart"
			)
		end

		carModels = { root }
	end

	local alignment = if options.RollerAlignment == true
		then { Offset = tonumber(options.RideHeightOffset) or 0 }
		else nil

	for index, carModel in ipairs(carModels) do
		buildCar(carModel, index == 1, alignment)
	end

	root.PrimaryPart = carModels[1].PrimaryPart

	Trackable.setup(root, {
		driveMode = "track",
		maxTrackSpeed = options.maxTrackSpeed or 0,
		trackAcceleration = options.trackAcceleration or 5,
		useGravity = true,
		liftSpeed = options.liftSpeed,
		smoothing = true,
		trackEnterDistance = 24,
		requireDriver = options.requireDriver ~= false,
		targetTrackSpeed = options.targetSpeed,
		autoMode = options.autoMode == true,
		autoModeWaitTime = options.autoModeWaitTime,
		autoModeStartType = options.autoModeStartType,
		noRollback = options.noRollback == true,
		flipDirection = options.flipDirection == true,
		cars = if options.MultiCar == true then carModels else nil,
		manualCarAlignment = options.ManualCarAlignment == true,
	})

	HelpUI.registerState(root, "RollercoasterCart3_Driver", {
		Sources = {
			{ Type = "Manual", Id = "Push", Description = "Push", Keyboard = "W", Gamepad = "ButtonR2" },
			{ Type = "Manual", Id = "Brake", Description = "Brake", Keyboard = "S", Gamepad = "ButtonL2" },
			{ Type = "Set", SetId = "Trackable" },
		},
	})
	HelpUI.registerState(root, "RollercoasterCart3_Rider", {
		Sources = {
			{ Type = "Set", SetId = "Trackable" },
		},
	})
	root:SetAttribute("HelpUI_DriverState", "RollercoasterCart3_Driver")
	root:SetAttribute("HelpUI_RiderState", "RollercoasterCart3_Rider")

	return root
end

local RollercoasterCart3 = CapabilityBase.createChild()

function RollercoasterCart3:getCapabilityDocumentation()
	return [[
The RollercoasterCart3Capability creates a cart (or multi-car train) that follows a predefined track with gravity-based speed.
The cart accelerates on downslopes and decelerates on upslopes. Player throttle provides minimal push.
Set the MultiCar attribute to true to treat numbered child models (1, 2, ...) as chained cars of one train;
every car gets a ride seat and the front car's driver seat controls the train.
Each car is normally placed on the track by its own body, so a train mixing body shapes (an ornate front
car with plain wagons behind it) rides at a different height per car, and a body that was modelled
backwards and turned around in Studio loses that half-turn and rides reversed. Set RollerAlignment to true
to place every car by its 'rollers' instead: the lead car keeps its authored pose, the rest align their
height to it, and every car keeps the facing you gave it. RideHeightOffset then raises (positive) or
lowers (negative) the whole train in studs.
By default the cart only moves while a player occupies the driver seat (requireDriver). Set requireDriver to false
for a free-rolling cart, or set targetSpeed to drive the cart at an exact speed with no driver.
Set autoMode to true for an unmanned ride cycle: the cart stops at the station (the track's first waypoint) each lap,
waits autoModeWaitTime seconds, then departs per autoModeStartType ("soft" ramps up, "launch" jumps to liftSpeed).
autoMode overrides requireDriver and ignores driver throttle input entirely. All three autoMode attributes can also be flipped at runtime on the cart model.
Requires track waypoints to be defined in workspace under a Tracks folder.
]]
end

function RollercoasterCart3:getModelSpecs()
	return {
		{
			name = "cart",
			modelSchema = "RollercoasterCart3",
			description = "a rollercoaster cart with rollers and seat",
		},
	}
end

function RollercoasterCart3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("maxTrackSpeed", { type = "number", default = 0, description = "Max speed on track; 0 or less means uncapped" })
		:addOptionalArgument("liftSpeed", { type = "number", default = 8, description = "Minimum speed enforced on chain-lift track segments" })
		:addOptionalArgument("requireDriver", {
			type = "boolean",
			default = true,
			description = "When true, the cart only moves while a player occupies the driver seat; when false it free-rolls with gravity and lifts",
		})
		:addOptionalArgument("targetSpeed", {
			type = "number",
			description = "When set, the server drives the cart toward this exact speed, overriding driver input and gravity",
		})
		:addOptionalArgument("autoMode", {
			type = "boolean",
			default = false,
			description = "When true, the cart runs unmanned: it stops at the station (first track waypoint) each lap, waits, then departs automatically",
		})
		:addOptionalArgument("autoModeWaitTime", {
			type = "number",
			default = 5,
			description = "Seconds the cart waits at the station before departing when autoMode is enabled",
		})
		:addOptionalArgument("autoModeStartType", {
			type = "string",
			default = "launch",
			description = "How the cart departs the station in autoMode: 'soft' accelerates gradually until it reaches liftSpeed, 'launch' instantly sets speed to liftSpeed",
		})
		:addOptionalArgument("noRollback", {
			type = "boolean",
			default = false,
			description = "When true, the cart can never move backward along the track: negative speed is clamped to zero (gravity rollback and reverse throttle disabled)",
		})
		:addOptionalArgument("MultiCar", {
			type = "boolean",
			default = false,
			description = "When true, numbered child models (1, 2, ...) are treated as chained cars of a single train",
		})
		:addOptionalArgument("ManualCarAlignment", {
			type = "boolean",
			default = false,
			description = "When true, train car spacing uses the authored distances between car models instead of computed bounding-box spacing",
		})
		:addOptionalArgument("RollerAlignment", {
			type = "boolean",
			default = false,
			description = "When true, each car is placed on the track by its 'rollers' instead of its own body, so cars with differently shaped bodies all ride at the same height and each keeps the facing it was given in Studio; the lead car keeps its authored pose and the rest align to it",
		})
		:addOptionalArgument("RideHeightOffset", {
			type = "number",
			default = 0,
			description = "Studs to shift the whole train relative to the track line; positive raises the cart, negative lowers it. Only applies when RollerAlignment is true",
		})
		:build()
end

function RollercoasterCart3:getCapabilitySelectionExamples()
	return {
		{
			user = "a rollercoaster cart",
			assistant = {
				capability_reasoning = "A rollercoaster cart follows a track with gravity. RollercoasterCart3Capability handles this.",
				capability_selection = "RollercoasterCart3Capability",
				overall_size_reasoning = "A cart is about 2m long, 1m wide, 1.5m tall.",
				overall_size_selection = { x = 1, y = 1.5, z = 2 },
			},
		},
	}
end

function RollercoasterCart3:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("RollercoasterCart3Capability configuration error: " .. errorMsg) end

	local model = generatedModels["cart"]
	if not model then error("Could not find 'cart' model") end

	return makeFunctional(model, parameters)
end

return RollercoasterCart3
~
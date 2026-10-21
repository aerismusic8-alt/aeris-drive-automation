--[[
Chest2 Capability - Static treasure chest with a hinged lid

Composes: Hingeable (Servo mode) - the lid swings open and closed on a back-bottom
hinge driven by per-client renderers.
Schema: Chest2 ("body" + "lid")

A player triggers a server-managed ProximityPrompt on the chest body. The lid
swings open, holds for a configurable duration, then swings closed. The prompt
is hidden while the chest is open. The lid loses collision while opened so
the player can stand inside the chest without being shoved.

Hinge placement heuristic (see computeLidHingeWorld): from the lid's bounding
box, pick the axis closest to world-up as "up", the longer of the two horizontal
axes as the hinge axis, and the shorter as the front-back axis. The "back" side
is chosen by comparing lid bbox extent vs body bbox extent on the front-back
axis - the side where the lid overhangs the body least is treated as the back.
For symmetric chests (lid and body co-extents on both sides) the heuristic
defaults to the +front-back direction. The hinge sign is then oriented so a
positive target angle lifts the front of the lid.

The hinge sits at the lid's back face center horizontally and at the body's
top face vertically. Using the body top (rather than the lid bbox bottom)
avoids placing the hinge below the body when the lid bbox is inflated by
hanging geometry (e.g. a padlock that drops below the lid plane).
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Hingeable = require(Behaviors.Hingeable)
local GeometryUtils = require(FourD.Common.GeometryUtils)

local DEFAULT_HOLD_SECONDS = 3
local DEFAULT_OPEN_ANGLE_DEGREES = 110
local DEFAULT_ACTION_TEXT = "Open Chest"

local PROMPT_RADIUS_RATIO = 1.25
local function getInstanceBoundingBox(instance: PVInstance): (CFrame, Vector3)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	return (instance :: Model):GetBoundingBox()
end

local function pickVerticalAxis(cf: CFrame, size: Vector3): (Vector3, number, number)
	local worldUp = Vector3.yAxis
	local axes = {
		{ dir = cf.RightVector, size = size.X, index = 1 },
		{ dir = cf.UpVector, size = size.Y, index = 2 },
		{ dir = -cf.LookVector, size = size.Z, index = 3 },
	}

	local bestIndex = 1
	local bestAbs = math.abs(axes[1].dir:Dot(worldUp))
	for i = 2, 3 do
		local absDot = math.abs(axes[i].dir:Dot(worldUp))
		if absDot > bestAbs then
			bestIndex = i
			bestAbs = absDot
		end
	end

	local chosen = axes[bestIndex]
	local upDir = chosen.dir
	if upDir:Dot(worldUp) < 0 then
		upDir = -upDir
	end

	return upDir, chosen.size, bestIndex
end

local function projectBboxExtents(cf: CFrame, size: Vector3, axis: Vector3): (number, number)
	local center = cf.Position:Dot(axis)
	local halfX = math.abs(cf.RightVector:Dot(axis)) * size.X * 0.5
	local halfY = math.abs(cf.UpVector:Dot(axis)) * size.Y * 0.5
	local halfZ = math.abs((-cf.LookVector):Dot(axis)) * size.Z * 0.5
	local half = halfX + halfY + halfZ
	return center - half, center + half
end

local function pickBackSign(lid: PVInstance, body: PVInstance, backDirWorld: Vector3): number
	local lidCF, lidSize = getInstanceBoundingBox(lid)
	local bodyCF, bodySize = getInstanceBoundingBox(body)

	local lidMin, lidMax = projectBboxExtents(lidCF, lidSize, backDirWorld)
	local bodyMin, bodyMax = projectBboxExtents(bodyCF, bodySize, backDirWorld)

	local overhangPositive = math.max(0, lidMax - bodyMax)
	local overhangNegative = math.max(0, bodyMin - lidMin)

	local tolerance = 0.01
	if overhangPositive > overhangNegative + tolerance then
		return -1
	elseif overhangNegative > overhangPositive + tolerance then
		return 1
	end
	return 1
end

local function computeLidHingeWorld(lid: PVInstance, body: PVInstance): CFrame
	local lidCF, lidSize = getInstanceBoundingBox(lid)
	local bodyCF, bodySize = getInstanceBoundingBox(body)
	local upDir, _, vertIndex = pickVerticalAxis(lidCF, lidSize)

	local axes = {
		{ dir = lidCF.RightVector, size = lidSize.X, index = 1 },
		{ dir = lidCF.UpVector, size = lidSize.Y, index = 2 },
		{ dir = -lidCF.LookVector, size = lidSize.Z, index = 3 },
	}

	local horizontal: { { dir: Vector3, size: number, index: number } } = {}
	for i = 1, 3 do
		if i ~= vertIndex then
			table.insert(horizontal, axes[i])
		end
	end

	local hingeAxisData = horizontal[1]
	local backAxisData = horizontal[2]
	if backAxisData.size > hingeAxisData.size then
		hingeAxisData, backAxisData = backAxisData, hingeAxisData
	end

	local backSign = pickBackSign(lid, body, backAxisData.dir)
	local backDir = backAxisData.dir * backSign

	local hingeAxis = upDir:Cross(backDir)
	if hingeAxis.Magnitude < 1e-4 then
		hingeAxis = hingeAxisData.dir
	else
		hingeAxis = hingeAxis.Unit
	end

	local lidBackCenter = lidCF.Position + backDir * (backAxisData.size * 0.5)
	local _, bodyTopOnUp = projectBboxExtents(bodyCF, bodySize, upDir)
	local hingeWorldPos = lidBackCenter + upDir * (bodyTopOnUp - lidBackCenter:Dot(upDir))

	return CFrame.fromMatrix(hingeWorldPos, hingeAxis, upDir)
end

local function makeFunctional(chestModel: Model, body: PVInstance, lid: PVInstance, config: { [string]: any }): Model
	for _, part in ipairs(GeometryUtils.getInstanceParts(body)) do
		part.Anchored = true
	end

	local primaryPart = GeometryUtils.findLargestPart(body)
	if not primaryPart then
		error("Chest2Capability: 'body' contains no BasePart")
	end
	chestModel.PrimaryPart = primaryPart

	local lidParts = GeometryUtils.getInstanceParts(lid)
	if #lidParts == 0 then
		error("Chest2Capability: 'lid' contains no BasePart")
	end

	for _, part in ipairs(lidParts) do
		part:SetAttribute("FourDOriginalCanCollide", part.CanCollide)
	end

	local hingeWorldCFrame = computeLidHingeWorld(lid, body)
	local pivotLocalCFrame = lid:GetPivot():ToObjectSpace(hingeWorldCFrame)
	Hingeable.new(lid, {
		PivotCFrame = pivotLocalCFrame,
		Mode = "Servo",
		TargetAngle = 0,
		RelativeTo = body,
	})

	local extents = chestModel:GetExtentsSize()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenChestPrompt"
	prompt.ActionText = config.actionText
	prompt.ObjectText = "Chest"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(extents.X, extents.Z) * PROMPT_RADIUS_RATIO
	prompt.Parent = primaryPart

	local activate = Instance.new("BindableEvent")
	activate.Name = "FourDActivate"
	activate.Parent = chestModel

	local controllerTemplate = script.Parent:FindFirstChild("ChestController")
	assert(controllerTemplate and controllerTemplate:IsA("Script"), "ChestController template is missing")
	local controller = controllerTemplate:Clone()
	controller.Name = "FourDChestServer"
	controller:SetAttribute("CASBehaviorManaged", true)
	controller.Parent = chestModel
	controller.Disabled = false

	return chestModel
end

local Chest2 = CapabilityBase.createChild()

function Chest2:getCapabilityDocumentation(): string
	return [[
The Chest2Capability creates a static treasure chest that any player can open
via a proximity prompt. The chest is placed by the developer or an AI caller
as a world prop; it does not move. When triggered, the lid swings open on a
hinge along the back-bottom edge, stays open for a configurable hold duration,
then swings closed. The prompt is hidden while the chest is open, and the lid
loses collision during the open cycle so the player is not shoved by the swing.
Use this for any stationary openable treasure chest, loot box, storage trunk,
or similar two-piece hinged container.
]]
end

function Chest2:getModelSpecs(): { { name: string, modelSchema: string, description: string } }
	return {
		{
			name = "chest",
			modelSchema = "Chest2",
			description = "a treasure chest with a rectangular body (the storage compartment, open on top) and a separate lid that sits flush on top of the body when closed",
		},
	}
end

function Chest2:getBindParametersDefinition(): { [string]: any }
	return SchemaBuilder.define()
		:addOptionalArgument("holdSeconds", {
			type = "number",
			default = DEFAULT_HOLD_SECONDS,
			minimum = 0.25,
			description = "Seconds the lid stays open before swinging closed",
		})
		:addOptionalArgument("openAngleDegrees", {
			type = "number",
			default = DEFAULT_OPEN_ANGLE_DEGREES,
			minimum = 30,
			maximum = 170,
			description = "Angle in degrees the lid swings open from its closed pose",
		})
		:addOptionalArgument("actionText", {
			type = "string",
			default = DEFAULT_ACTION_TEXT,
			description = "Action text shown on the open ProximityPrompt",
		})
		:build()
end

function Chest2:getCapabilitySelectionExamples(): { any }
	return {
		{
			user = "a pirate treasure chest",
			assistant = {
				capability_reasoning = 'The user wants a "pirate treasure chest" - a stationary openable container. This maps to Chest2Capability, which creates a static chest whose lid swings open on a ProximityPrompt and closes after a hold.',
				capability_selection = "Chest2Capability",
				overall_size_reasoning = "A pirate chest is a compact prop, roughly 4 studs wide, 3 studs tall (including the curved lid), and 3 studs deep.",
				overall_size_selection = { x = 4, y = 3, z = 3 },
			},
		},
		{
			user = "a wooden storage trunk in a tavern",
			assistant = {
				capability_reasoning = 'The user wants a "wooden storage trunk" - a hinged container. Chest2Capability is correct: it creates a two-piece body+lid chest that opens on player interaction.',
				capability_selection = "Chest2Capability",
				overall_size_reasoning = "A storage trunk is slightly larger than a pirate chest, roughly 5 studs wide, 3 studs tall, and 3 studs deep.",
				overall_size_selection = { x = 5, y = 3, z = 3 },
			},
		},
	}
end

function Chest2:getModelPlanningExamples(): { any }
	return {
		{
			user = "a pirate treasure chest with iron bands",
			assistant = {
				size_reasoning = "The body is the storage box, roughly 4 studs wide, 1.5 studs tall, and 3 studs deep. The lid is a domed cover sitting on top, the same footprint as the body but about 1.25 studs tall to give the chest its curved silhouette. Combined the chest is about 3 studs tall.",
				chest = {
					description = "a pirate treasure chest with a rectangular wooden body wrapped in iron bands, an open top, and a domed wooden lid with iron banding that sits flush on the body when closed",
					size = { x = 4, y = 3, z = 3 },
				},
			},
		},
	}
end

function Chest2:getConfigureCapabilityExamples(): { any }
	return {
		{
			user = "a chest that snaps shut quickly",
			assistant = {
				capability_parameters_reasoning = "A quick-snapping chest should hold open only briefly: a 1.5 second hold, a normal 110 degree open angle, and the default action text.",
				capability_parameters_selection = {
					holdSeconds = 1.5,
					openAngleDegrees = 110,
				},
			},
		},
		{
			user = "a chest that opens wide and lingers",
			assistant = {
				capability_parameters_reasoning = "An inviting chest should open wide and stay open: a 5 second hold and a 140 degree open angle.",
				capability_parameters_selection = {
					holdSeconds = 5,
					openAngleDegrees = 140,
				},
			},
		},
	}
end

function Chest2:bind(generatedModels: { [string]: Instance }, parameters: { [string]: any }): Model
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Chest2Capability configuration error: " .. tostring(errorMsg))
	end

	local chestModel = generatedModels["chest"]
	if not chestModel then
		error("Chest2Capability: could not find 'chest' model in generatedModels")
	end

	local body = chestModel:FindFirstChild("body")
	local lid = chestModel:FindFirstChild("lid")

	if not body or not body:IsA("PVInstance") then
		error("Chest2Capability: missing 'body' PVInstance child of chest model")
	end
	if not lid or not lid:IsA("PVInstance") then
		error("Chest2Capability: missing 'lid' PVInstance child of chest model")
	end

	return makeFunctional(chestModel, body, lid, parameters)
end

return Chest2

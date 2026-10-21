--[[
Flashlight3Capability - Equippable handheld flashlight with toggleable directional light

Composes: Handheld Tool + Lightable Behavior (directional SurfaceLight)
Schema: Flashlight3 (model with lens BasePart and handle body/Grip sub-parts)

Activate to toggle, auto-on when equipped, auto-off when unequipped.
]]

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local Common = FourD:FindFirstChild("Common")
local Architects = FourD:FindFirstChild("Architects")
local Behaviors = FourD:FindFirstChild("Behaviors")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local GeometryUtils = require(Common.GeometryUtils)
local Lightable = require(Behaviors.Lightable)
local SimpleTool = require(Architects.SimpleTool)

-- Constants

local DEFAULT_LIGHT_COLOR3 = Color3.new(1, 1, 1)
local DEFAULT_LIGHT_BRIGHTNESS = 2
local DEFAULT_LIGHT_RANGE = 25
local DEFAULT_LIGHT_SPREAD = 35
local FACE_NORMALS = {
	[Enum.NormalId.Right] = Vector3.new(1,  0,  0),
	[Enum.NormalId.Left] = Vector3.new(-1,  0,  0),
	[Enum.NormalId.Top] = Vector3.new(0,  1,  0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1,  0),
	[Enum.NormalId.Back] = Vector3.new(0,  0,  1),
	[Enum.NormalId.Front] = Vector3.new(0,  0, -1),
}

-- Local Functions

local function FillConfigDefaults(config: { [string]: any })
	config.lightColor3 = config.lightColor3 or DEFAULT_LIGHT_COLOR3
	config.lightBrightness = config.lightBrightness or DEFAULT_LIGHT_BRIGHTNESS
	config.lightRange = config.lightRange or DEFAULT_LIGHT_RANGE
	config.lightSpread = config.lightSpread or DEFAULT_LIGHT_SPREAD
end

local function FindLensInstance(model: Instance, name: string): (BasePart | Model)?
	local lowerName = name:lower()
	for _, desc in model:GetDescendants() do
		if (desc:IsA("BasePart") or desc:IsA("Model")) and desc.Name:lower() == lowerName then
			return desc
		end
	end

	return nil
end

local function ResolveLensEmitPart(lens: BasePart | Model): BasePart
	if lens:IsA("BasePart") then
		return lens
	end

	local primary = GeometryUtils.getOrSetPrimaryPart(lens)
	if primary then
		return primary
	end

	local largest = GeometryUtils.findLargestPart(lens)
	if largest then
		return largest
	end

	error("Flashlight3: lens Model contains no BasePart to emit from")
end

local function GetLensCenter(lens: BasePart | Model): Vector3
	if lens:IsA("BasePart") then
		return lens.Position
	end

	local cf, _ = lens:GetBoundingBox()
	return cf.Position
end

local function DetectOutwardFace(emitPart: BasePart, outwardDir: Vector3): Enum.NormalId
	if outwardDir.Magnitude < 1e-4 then
		return Enum.NormalId.Front
	end

	outwardDir = outwardDir.Unit
	local bestFace = Enum.NormalId.Front
	local bestDot = -math.huge
	for face, localNormal in FACE_NORMALS do
		local worldNormal = emitPart.CFrame:VectorToWorldSpace(localNormal)
		local dot = worldNormal:Dot(outwardDir)
		if dot > bestDot then
			bestDot = dot
			bestFace = face
		end
	end

	return bestFace
end

-- Main Function

local function MakeFunctional(model: Model, config: { [string]: any }): Tool
	config = config or {}
	FillConfigDefaults(config)

	local lens = FindLensInstance(model, "lens")
	if not lens then
		error("Flashlight3: Could not find 'lens' part or model in model")
	end

	local emitPart = ResolveLensEmitPart(lens)
	local boundingCF = model:GetBoundingBox()
	local outwardDir = GetLensCenter(lens) - boundingCF.Position
	local outwardFace = DetectOutwardFace(emitPart, outwardDir)

	Lightable.newStatic(emitPart, {
		Type = "surface",
		Face = outwardFace,
		Color = config.lightColor3,
		Brightness = config.lightBrightness,
		Range = config.lightRange,
		Angle = config.lightSpread,
		Enabled = false,
	})

	local simpleTool = SimpleTool.build(model, {
		FrontFacingSchemaPart = lens,
		Collisions = true,
		UseDebounce = 0.1,
	})

	local light = emitPart:FindFirstChild("Light")
	assert(light and light:IsA("Light"), "Flashlight3 static light was not authored")

	local activate = Instance.new("BindableEvent")
	activate.Name = "FourDActivate"
	activate.Parent = simpleTool.Tool

	local controllerTemplate = script.Parent:FindFirstChild("FlashlightController")
	assert(controllerTemplate and controllerTemplate:IsA("Script"), "FlashlightController template is missing")
	local controller = controllerTemplate:Clone()
	controller.Name = "FourDFlashlightServer"
	controller:SetAttribute("CASBehaviorManaged", true)
	local lightRef = Instance.new("ObjectValue")
	lightRef.Name = "LightRef"
	lightRef.Value = light
	lightRef.Parent = controller
	controller.Parent = simpleTool.Tool
	controller.Disabled = false

	return simpleTool.Tool
end

local Flashlight3 = CapabilityBase.createChild()

function Flashlight3:getCapabilityDocumentation()
	return [[
Flashlight3Capability creates an equippable handheld flashlight that players can pick up, equip, and aim.
The flashlight emits a directional SurfaceLight from its lens. The light is off by default.
When equipped, the light turns on automatically. When unequipped, it turns off.
Clicking (Activated) toggles the light on or off while equipped.
Use this for any handheld illumination tool: flashlights, lanterns, spotlights, etc.
]]
end

function Flashlight3:getModelSpecs()
	return {
		{
			name = "flashlight",
			modelSchema = "Flashlight3",
			description = "a handheld flashlight with a cylindrical body, lens at the front, and grip at the rear",
		},
	}
end

function Flashlight3:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("lightColor3", {
			type = "Color3",
			default = Color3.new(1, 1, 1),
			description = "Color of the emitted light",
		})
		:addOptionalArgument("lightBrightness", {
			type = "number",
			default = 2,
			minimum = 0,
			description = "Brightness of the emitted light",
		})
		:addOptionalArgument("lightRange", {
			type = "number",
			default = 25,
			minimum = 0,
			description = "Range of the emitted light in studs",
		})
		:addOptionalArgument("lightSpread", {
			type = "number",
			default = 35,
			minimum = 0,
			maximum = 180,
			description = "Spread angle of the emitted light beam in degrees",
		})
		:build()
end

function Flashlight3:getCapabilitySelectionExamples()
	return {
		{
			user = "a flashlight",
			assistant = {
				capability_reasoning = 'The user wants a "flashlight" — a handheld tool that emits a directed beam of light. Flashlight3Capability creates an equippable Tool with a toggleable directional light.',
				capability_selection = "Flashlight3Capability",
				overall_size_reasoning = "A flashlight for a Roblox avatar should be roughly hand-sized: about 0.5m long (z), 0.25m diameter (y/x).",
				overall_size_selection = { x = 0.25, y = 0.25, z = 0.5 },
			},
		},
	}
end

function Flashlight3:getConfigureCapabilityExamples()
	return {
		{
			user = "an old flashlight",
			assistant = {
				capability_parameters_reasoning = "An older flashlight emits soft, warm, low-brightness light with a wide spread angle.",
				capability_parameters_selection = {
					lightColor3 = Color3.fromRGB(255, 200, 120),
					lightBrightness = 2,
					lightRange = 12,
					lightSpread = 90,
				},
			},
		},
		{
			user = "a police tactical flashlight",
			assistant = {
				capability_parameters_reasoning = "A tactical flashlight emits a bright white focused beam with high brightness and narrow spread.",
				capability_parameters_selection = {
					lightColor3 = Color3.new(1, 1, 1),
					lightBrightness = 8,
					lightRange = 40,
					lightSpread = 20,
				},
			},
		},
	}
end

function Flashlight3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Flashlight3Capability configuration error: " .. errorMsg)
	end

	local flashlightModel = generatedModels["flashlight"]
	if not flashlightModel then
		error("Flashlight3Capability: Could not find 'flashlight' model")
	end

	return MakeFunctional(flashlightModel, parameters)
end

return Flashlight3

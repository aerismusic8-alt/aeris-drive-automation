--[[
Sirennable Behavior - Adds flashing siren lights to an assembled vehicle.

Accepts the assembled vehicle model and a light bar (BasePart or multi-part Model).
Welds every light bar part to its anchor, welds the anchor to the rig Chassis,
builds two Lightable strobes (red on the leftmost light bar part, blue on the
rightmost) with opposed two-keyframe patterns so they alternate, and clones
SirenClient (Script with RunContext = Client) into the model so the driver can
request a toggle on a keybind (V by default). Toggle authority lives on the server:
the driver client fires a RemoteEvent parented to the model, the server re-validates
seat occupancy, then flips both strobes' StrobeEnabled attribute and the model's
sirenEnabled attribute. Every client sees the synchronized strobe via Lightable's
tagged-folder client renderer (workspace:GetServerTimeNow() phase clock).

Dependencies: FourD/Common (GeometryUtils, ConstructionHelpers), FourD/Behaviors/Lightable
]]

local FourD = script:FindFirstAncestor("FourD")
local Behaviors = FourD.Behaviors
local Common = FourD.Common
local ConstructionHelpers = require(Common.ConstructionHelpers)
local GeometryUtils = require(Common.GeometryUtils)
local Lightable = require(Behaviors.Lightable)

export type SirenConfig = {
	FlashRate: number?,
	ColorLeft: Color3?,
	ColorRight: Color3?,
	Brightness: number?,
	Range: number?,
	ToggleKey: EnumItem?,
}

local Sirennable = {}

local DEFAULT_CONFIG: SirenConfig = {
	FlashRate = 4,
	ColorLeft = Color3.fromRGB(255, 0, 0),
	ColorRight = Color3.fromRGB(0, 100, 255),
	Brightness = 3,
	Range = 30,
	ToggleKey = Enum.KeyCode.V,
}

function Sirennable.setup(assembledModel: Model, lightBarPart: Instance, config: SirenConfig?)
	local resolvedConfig: SirenConfig = config or {}
	for k, v in pairs(DEFAULT_CONFIG) do
		if resolvedConfig[k] == nil then resolvedConfig[k] = v end
	end

	local lightBarAnchor = if lightBarPart:IsA("BasePart")
		then lightBarPart
		else GeometryUtils.getOrSetPrimaryPart(lightBarPart)

	local lightBarParts = GeometryUtils.getInstanceParts(lightBarPart)
	for _, part in ipairs(lightBarParts) do
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
	end

	for _, part in ipairs(lightBarParts) do
		if part ~= lightBarAnchor then
			ConstructionHelpers.makeWeld(lightBarAnchor, part)
		end
	end

	local chassis = GeometryUtils.findRigChassis(assembledModel)
	if chassis then
		ConstructionHelpers.makeWeld(chassis, lightBarAnchor)
	end

	local leftHost, rightHost = lightBarAnchor, lightBarAnchor
	if #lightBarParts > 1 then
		local rightAxis = lightBarAnchor.CFrame.RightVector
		local minDot, maxDot = math.huge, -math.huge
		for _, part in ipairs(lightBarParts) do
			local projected = (part.Position - lightBarAnchor.Position):Dot(rightAxis)
			if projected < minDot then
				minDot = projected
				leftHost = part
			end

			if projected > maxDot then
				maxDot = projected
				rightHost = part
			end
		end
	end

	local flashRate = resolvedConfig.FlashRate
	assert(flashRate, "FlashRate nil after default merge")
	local halfPeriod = 1 / flashRate
	Lightable.newStrobe(leftHost, {
		Type = "point",
		Color = resolvedConfig.ColorLeft,
		Brightness = resolvedConfig.Brightness,
		Range = resolvedConfig.Range,
		Enabled = false,
		Strobe = {
			{ Time = halfPeriod, Enabled = true },
			{ Time = halfPeriod, Enabled = false },
		},
	})
	Lightable.newStrobe(rightHost, {
		Type = "point",
		Color = resolvedConfig.ColorRight,
		Brightness = resolvedConfig.Brightness,
		Range = resolvedConfig.Range,
		Enabled = false,
		Strobe = {
			{ Time = halfPeriod, Enabled = false },
			{ Time = halfPeriod, Enabled = true },
		},
	})

	local toggleKey = resolvedConfig.ToggleKey
	assert(toggleKey, "ToggleKey nil after default merge")

	assembledModel:SetAttribute("sirenEnabled", false)
	assembledModel:SetAttribute("sirenFlashRate", resolvedConfig.FlashRate)
	assembledModel:SetAttribute("sirenToggleKey", toggleKey.Name)

	local toggleEvent = Instance.new("RemoteEvent")
	toggleEvent.Name = "SirenToggleEvent"
	toggleEvent.Parent = assembledModel

	local serverTemplate = script.Parent:FindFirstChild("SirenServer")
	assert(serverTemplate and serverTemplate:IsA("Script"), "SirenServer template is missing")
	local server = serverTemplate:Clone()
	server:SetAttribute("CASBehaviorManaged", true)
	local leftRef = Instance.new("ObjectValue")
	leftRef.Name = "LeftStrobeRef"
	leftRef.Value = leftHost:FindFirstChild("Lightable_Strobe")
	leftRef.Parent = server
	local rightRef = Instance.new("ObjectValue")
	rightRef.Name = "RightStrobeRef"
	rightRef.Value = rightHost:FindFirstChild("Lightable_Strobe")
	rightRef.Parent = server
	server.Parent = assembledModel
	server.Enabled = true

	if assembledModel:FindFirstChild("SirenClient") then return end

	local sirenScript = script.Parent:FindFirstChild("SirenClient")
	if sirenScript then
		local clone = sirenScript:Clone()
		if clone:IsA("BaseScript") then
			clone.Enabled = true
		end
		clone.Parent = assembledModel
	end
end

return Sirennable

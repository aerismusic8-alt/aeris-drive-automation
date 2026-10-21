--[[
	File: Hud.luau
]]--

-- Root

local Hud = {}

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SharedUtils = Shared:WaitForChild("Utils")
local FormatNumber = require(SharedUtils:WaitForChild("FormatNumber"))

-- Constants

local TEMPLATE_PATH = { "Assets", "UI", "AirVehicleHud" }
local STUDS_TO_FEET = 0.918
local SMOOTH_RATE = 12
local PAD_WIDTH = 3
local LEADING_ZERO_OPEN = `<font color="#000000">`

-- Module State

local active = false
local cachedRoot: BasePart? = nil
local screenGui: ScreenGui? = nil
local speedLabel: TextLabel? = nil
local altitudeLabel: TextLabel? = nil
local headingLabel: TextLabel? = nil
local renderConnection: RBXScriptConnection? = nil
local displayedSpeed = 0
local displayedAltitude = 0
local displayedHeading = 0
local lastSpeedRounded: number? = nil
local lastAltitudeRounded: number? = nil
local lastHeadingRounded: number? = nil

-- Local Functions

local function getTemplate(): ScreenGui
	local current: Instance = ReplicatedStorage
	for _, name in TEMPLATE_PATH do
		current = current:WaitForChild(name)
	end
	return current :: ScreenGui
end

local function computeHeading(lookVector: Vector3): number
	local rad = math.atan2(lookVector.X, -lookVector.Z)
	local deg = math.deg(rad)
	return (deg + 360) % 360
end

local function shortestArcDelta(from: number, to: number): number
	return ((to - from + 540) % 360) - 180
end

local function smoothAlpha(dt: number): number
	return 1 - math.exp(-SMOOTH_RATE * dt)
end

local function formatPaddedRich(value: number): string
	local valueStr = tostring(math.abs(value))
	local padCount = math.max(PAD_WIDTH - #valueStr, 0)
	local padded = string.rep("0", padCount) .. valueStr

	local firstNonZero = string.find(padded, "[^0]") or (#padded + 1)
	firstNonZero = math.min(firstNonZero, #padded)
	local leadingZeros = string.sub(padded, 1, firstNonZero - 1)
	local rest = string.sub(padded, firstNonZero)

	local leadingPart = if #leadingZeros > 0
		then `{LEADING_ZERO_OPEN}{leadingZeros}</font>`
		else ""

	return `{leadingPart}{rest}`
end

local function update(dt: number)
	if not active then return end
	if not cachedRoot then return end
	if not speedLabel or not altitudeLabel or not headingLabel then return end

	local root = cachedRoot
	local lookV = root.CFrame.LookVector
	local horizontalVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	local targetSpeed = horizontalVelocity.Magnitude
	local targetAltitude = root.Position.Y * STUDS_TO_FEET
	local targetHeading = computeHeading(lookV)

	local alpha = smoothAlpha(dt)
	displayedSpeed += (targetSpeed - displayedSpeed) * alpha
	displayedAltitude += (targetAltitude - displayedAltitude) * alpha
	local headingDelta = shortestArcDelta(displayedHeading, targetHeading)
	displayedHeading = (displayedHeading + headingDelta * alpha + 360) % 360

	local speedRounded = math.round(displayedSpeed)
	if speedRounded ~= lastSpeedRounded then
		speedLabel.Text = formatPaddedRich(speedRounded)
		lastSpeedRounded = speedRounded
	end

	local altitudeRounded = math.round(displayedAltitude)
	if altitudeRounded ~= lastAltitudeRounded then
		altitudeLabel.Text = `{FormatNumber.AddCommas(altitudeRounded)} ft`
		lastAltitudeRounded = altitudeRounded
	end

	local headingRounded = math.round(displayedHeading) % 360
	if headingRounded ~= lastHeadingRounded then
		headingLabel.Text = formatPaddedRich(headingRounded)
		lastHeadingRounded = headingRounded
	end
end

-- Public Functions

function Hud.enable(_: Model, root: BasePart)
	if active then return end
	active = true

	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local template = getTemplate()
	local cloned = template:Clone()
	cloned.Parent = playerGui
	screenGui = cloned

	local hudFrame = cloned:WaitForChild("Hud")
	speedLabel = hudFrame:WaitForChild("SpeedFrame"):WaitForChild("ValueLabel") :: TextLabel
	altitudeLabel = hudFrame:WaitForChild("AltitudeFrame"):WaitForChild("ValueLabel") :: TextLabel
	headingLabel = hudFrame:WaitForChild("HeadingFrame"):WaitForChild("ValueLabel") :: TextLabel
	local throttleFrame = (hudFrame :: any).ThrottleFrame
	throttleFrame.Visible = false

	cachedRoot = root
	local lookV = root.CFrame.LookVector
	local horizontalVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	displayedSpeed = horizontalVelocity.Magnitude
	displayedAltitude = root.Position.Y * STUDS_TO_FEET
	displayedHeading = computeHeading(lookV)

	if speedLabel and altitudeLabel and headingLabel then
		speedLabel.RichText = true
		altitudeLabel.RichText = true
		headingLabel.RichText = true
		lastSpeedRounded = math.round(displayedSpeed)
		lastAltitudeRounded = math.round(displayedAltitude)
		lastHeadingRounded = math.round(displayedHeading) % 360
		speedLabel.Text = formatPaddedRich(lastSpeedRounded)
		altitudeLabel.Text = `{FormatNumber.AddCommas(lastAltitudeRounded)} ft`
		headingLabel.Text = formatPaddedRich(lastHeadingRounded)
	end

	renderConnection = RunService.RenderStepped:Connect(update)
end

function Hud.disable()
	if not active then return end
	active = false

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end

	speedLabel = nil
	altitudeLabel = nil
	headingLabel = nil
	cachedRoot = nil
	displayedSpeed = 0
	displayedAltitude = 0
	displayedHeading = 0
	lastSpeedRounded = nil
	lastAltitudeRounded = nil
	lastHeadingRounded = nil
end

-- Return

return Hud

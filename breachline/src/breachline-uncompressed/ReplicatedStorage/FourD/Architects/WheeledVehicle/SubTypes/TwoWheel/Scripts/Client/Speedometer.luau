local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Parent.Constants)
local Units = require(script.Parent.Parent.Units)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local guiTemplate = script.SpeedometerGui
local car = script.Parent.Parent.Parent
local chassis = car.Chassis
local engine = car.Engine

local enabled = false
local gui = nil
local heartbeatConnection = nil
local nitroUsableConnection = nil

local function updateNitroVisibility()
	local nitroUsable = car:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE)
	gui.Speedometer.NitroFrame.Visible = nitroUsable == true
end

-- Update the speedometer dial and nitro bar
local function update()
	-- Update UI size. This is the same logic used by the default touch controls
	local minScreenSize = math.min(gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
	local isSmallScreen = minScreenSize < Constants.UI_SMALL_SCREEN_THRESHOLD
	gui.Speedometer.UIScale.Scale = if isSmallScreen then Constants.UI_SMALL_SCREEN_SCALE else 1

	-- Update speedometer dial
	local speed = chassis.AssemblyLinearVelocity.Magnitude
	-- Velocity is in studs per second by default, and needs to be converted to miles per hour
	local milesPerHour = Units.studsPerSecondToMilesPerHour(speed)
	local speedString = tostring(math.round(milesPerHour))
	gui.Speedometer.SpeedFrame.SpeedLabel.Text = speedString

	-- Update the nitro meter
	if car:GetAttribute(Constants.NITRO_USABLE_ATTRIBUTE) then
		local nitro = engine:GetAttribute(Constants.ENGINE_NITRO_ATTRIBUTE)
		gui.Speedometer.NitroFrame.Nitro.Bar.Size = UDim2.fromScale(nitro, 1)
	end
end

local Speedometer = {}

function Speedometer:enable()
	if enabled then
		return
	end
	enabled = true

	local newGui = guiTemplate:Clone()
	newGui.Parent = playerGui
	gui = newGui

	updateNitroVisibility()
	nitroUsableConnection = car:GetAttributeChangedSignal(Constants.NITRO_USABLE_ATTRIBUTE):Connect(updateNitroVisibility)

	heartbeatConnection = RunService.Heartbeat:Connect(update)
end

function Speedometer:disable()
	if not enabled then
		return
	end
	enabled = false

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	if nitroUsableConnection then
		nitroUsableConnection:Disconnect()
		nitroUsableConnection = nil
	end

	if gui then
		gui:Destroy()
		gui = nil
	end
end

return Speedometer

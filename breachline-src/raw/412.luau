local Players = game:GetService("Players")

local Constants = require(script.Parent.Parent.Constants)

local car = script.Parent.Parent.Parent
local driverSeat = car.DriverSeat
local engine = car.Engine
local remotes = car.Remotes
local setNitroEnabledRemote = remotes.SetNitroEnabled

local function getDrivingPlayer(): Player?
	local humanoid = driverSeat.Occupant
	if not humanoid then
		return nil
	end

	return Players:GetPlayerFromCharacter(humanoid.Parent)
end

local function onOccupantChanged()
	-- Disable nitro whenever the car is exited
	local humanoid = driverSeat.Occupant
	if not humanoid then
		engine:SetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE, false)
	end
end

local function onSetNitroEnabledEvent(player: Player, enabled: boolean)
	-- Make sure the remote cannot be exploited to set the attribute to an arbitrary value
	if typeof(enabled) ~= "boolean" then
		return
	end

	-- Make sure the remote event call is coming from the player who is actually driving the car
	local drivingPlayer = getDrivingPlayer()
	if player ~= drivingPlayer then
		return
	end

	engine:SetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE, enabled)
end

setNitroEnabledRemote.OnServerEvent:Connect(onSetNitroEnabledEvent)
driverSeat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)

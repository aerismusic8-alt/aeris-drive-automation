--[[
	File: Common/Controller.luau

	Resolves who controls the gun. Priority: explicit override (caller API)
	then SecondarySeat occupant (e.g. GunnerSeat) then PrimarySeat occupant
	(e.g. DriverSeat) then nil. Used by both Turret and Hardpoint SubTypes on
	server and client.
]]--

local Players = game:GetService("Players")

local OVERRIDE_ATTR = "Gunnable_ControllerUserId"
local TURRET_BOUND_ATTR = "Gunnable_TurretBound"

export type SeatOptions = {
	PrimarySeat: Seat?,
	SecondarySeat: Seat?,
}

local Controller = {}

Controller.OVERRIDE_ATTR = OVERRIDE_ATTR
Controller.TURRET_BOUND_ATTR = TURRET_BOUND_ATTR

local function getSeatPlayer(seat: Seat?): Player?
	if not seat then return nil end
	local occupant = seat.Occupant
	if not occupant then return nil end
	local character = occupant.Parent
	if not character then return nil end
	return Players:GetPlayerFromCharacter(character)
end

function Controller.setOverride(model: Model, player: Player?)
	model:SetAttribute(OVERRIDE_ATTR, if player then player.UserId else 0)
end

function Controller.getOverridePlayer(model: Model): Player?
	local userId = model:GetAttribute(OVERRIDE_ATTR)
	if typeof(userId) ~= "number" or userId == 0 then return nil end
	return Players:GetPlayerByUserId(userId)
end

function Controller.resolve(model: Model, opts: SeatOptions): Player?
	local override = Controller.getOverridePlayer(model)
	if override then return override end

	local secondary = getSeatPlayer(opts.SecondarySeat)
	if secondary then return secondary end

	return getSeatPlayer(opts.PrimarySeat)
end

function Controller.isAuthorizedFirer(model: Model, player: Player, opts: SeatOptions): boolean
	return Controller.resolve(model, opts) == player
end

function Controller.isSecondaryOccupied(opts: SeatOptions): boolean
	if not opts.SecondarySeat then return false end
	return opts.SecondarySeat.Occupant ~= nil
end

function Controller.localIsAuthorized(model: Model, opts: SeatOptions): boolean
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return false end
	return Controller.resolve(model, opts) == localPlayer
end

function Controller.localIsOverride(model: Model): boolean
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return false end
	return Controller.getOverridePlayer(model) == localPlayer
end

function Controller.seatOptsFor(model: Model, ownSeat: Seat?): SeatOptions
	if model:GetAttribute(TURRET_BOUND_ATTR) then
		local driverRef = model:FindFirstChild("Gunnable_DriverSeatRef")
		local gunnerRef = model:FindFirstChild("Gunnable_GunnerSeatRef")

		return {
			PrimarySeat = if driverRef and driverRef:IsA("ObjectValue") then driverRef.Value :: any else nil,
			SecondarySeat = if gunnerRef and gunnerRef:IsA("ObjectValue") then gunnerRef.Value :: any else nil,
		}
	end

	return {
		PrimarySeat = ownSeat,
		SecondarySeat = nil,
	}
end

return Controller

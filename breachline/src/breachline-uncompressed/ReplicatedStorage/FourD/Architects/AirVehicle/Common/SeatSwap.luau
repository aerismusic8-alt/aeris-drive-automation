--[[
	File: SeatSwap.luau

	Server-side helpers shared by AirVehicle SubTypes for swapping a player
	between the welded pilot position and a caller-owned Gunnable gunner Seat.
]]--

-- Root

local SeatSwap = {}

-- Public Functions

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function occupiedBy(seat: Seat, player: Player): boolean
	local occupant = seat.Occupant
	if not occupant then return false end
	return occupant.Parent == player.Character
end

local function forceSit(seat: Seat, humanoid: Humanoid)
	seat:Sit(humanoid)
end

local function eject(humanoid: Humanoid)
	humanoid.Sit = false
end

SeatSwap.getHumanoid = getHumanoid
SeatSwap.occupiedBy = occupiedBy
SeatSwap.forceSit = forceSit
SeatSwap.eject = eject

-- Return

return SeatSwap

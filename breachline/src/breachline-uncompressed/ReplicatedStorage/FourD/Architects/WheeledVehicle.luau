--[[
	File: WheeledVehicle.luau
]]--

-- Root

local WheeledVehicle = {}

-- Dependencies

local FourWheel = require(script.SubTypes.FourWheel)
local TwoWheel = require(script.SubTypes.TwoWheel)
local Board = require(script.SubTypes.Board)

-- Public Functions

function WheeledVehicle.build4Wheel(container: Model, params: FourWheelSetupParams): FourWheel.FourWheelInstance
	return FourWheel.new(container, params)
end

function WheeledVehicle.build2Wheel(container: Model, params: TwoWheelSetupParams): TwoWheel.TwoWheelInstance
	return TwoWheel.new(container, params)
end

function WheeledVehicle.buildBoard(container: Model, params: BoardSetupParams): Board.BoardInstance
	return Board.new(container, params)
end

-- Types

export type FourWheelSetupParams = FourWheel.SetupParams
export type TwoWheelSetupParams = TwoWheel.SetupParams
export type BoardSetupParams = Board.SetupParams

-- Return

return WheeledVehicle

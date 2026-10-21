--[[
	File: AirVehicle.luau
]]--

-- Root

local AirVehicle = {}

-- Dependencies

local Plane = require(script.SubTypes.Plane)
local Rotor = require(script.SubTypes.Rotor)
local Jetpack = require(script.SubTypes.Jetpack)

-- Public Functions

function AirVehicle.buildPlane(bodyModel: Model, params: PlaneSetupParams): Plane.PlaneInstance
	return Plane.new(bodyModel, params)
end

function AirVehicle.buildRotor(bodyModel: Model, params: RotorSetupParams): Rotor.RotorInstance
	return Rotor.new(bodyModel, params)
end

function AirVehicle.buildJetpack(bodyModel: Model, params: JetpackSetupParams): Jetpack.JetpackInstance
	return Jetpack.new(bodyModel, params)
end

-- Types

export type PlaneSetupParams = Plane.SetupParams
export type RotorSetupParams = Rotor.SetupParams
export type JetpackSetupParams = Jetpack.SetupParams

-- Return

return AirVehicle

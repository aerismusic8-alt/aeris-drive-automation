--[[
	File: Camera.luau

	Shim. The shared chase camera lives in
	`AirVehicle.Common.Scripts.Camera` so Plane and Rotor share a single
	implementation.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
return require(FourD.Architects.AirVehicle.Common.Scripts.Camera)
v
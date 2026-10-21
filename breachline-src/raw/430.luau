--[[
Train5 SmokeRamp - emits chimney smoke only while the driver seat is occupied,
ramping emitter rate and particle speed linearly with the train's track speed.
Cloned into every car model that has a chimney by bind().
]]

local UPDATE_INTERVAL = 0.1
local MIN_RATE = 5
local MAX_RATE = 30
local MIN_SPEED = 0
local MAX_SPEED = 15

local carModel = script.Parent
if not carModel:IsA("Model") then return end

local smoke = carModel:FindFirstChild("SmokeEmitter")
local emitter = smoke and smoke:FindFirstChildWhichIsA("ParticleEmitter")
if not emitter then return end

local rootModel = carModel

local function resolveRoot(): Model
	if rootModel:GetAttribute("driveMode") ~= nil then
		return rootModel
	end

	local candidate: Instance? = carModel
	while candidate do
		if candidate:IsA("Model") and candidate:GetAttribute("driveMode") ~= nil then
			rootModel = candidate
			break
		end

		candidate = candidate.Parent
	end

	return rootModel
end

local seat = resolveRoot():FindFirstChildWhichIsA("VehicleSeat", true)
if not seat then return end

emitter.Enabled = false

local function getSpeedRatio(): number
	local root = resolveRoot()
	local maxTrackSpeed = root:GetAttribute("maxTrackSpeed")
	if typeof(maxTrackSpeed) ~= "number" or maxTrackSpeed <= 0 then return 0 end

	local trackSpeed = root:GetAttribute("trackSpeed")
	if typeof(trackSpeed) ~= "number" then return 0 end

	return math.clamp(math.abs(trackSpeed) / maxTrackSpeed, 0, 1)
end

while carModel.Parent do
	local occupied = seat.Occupant ~= nil
	emitter.Enabled = occupied

	if occupied then
		local ratio = getSpeedRatio()
		emitter.Rate = MIN_RATE + (MAX_RATE - MIN_RATE) * ratio
		emitter.Speed = NumberRange.new(MIN_SPEED + (MAX_SPEED - MIN_SPEED) * ratio)
	end

	task.wait(UPDATE_INTERVAL)
end
=
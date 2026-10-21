--[[
	File: WaterSubmersible.luau
]]--

-- Root

local WaterSubmersible = {}
WaterSubmersible.__index = WaterSubmersible

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local Dumpster = require(FourD.Libs.Dumpster)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local StripCapabilityTag = require(FourD.Common.stripCapabilityTag)
local WaterUtils = require(Shared.Utils.WaterUtils)

-- Constants

local DENSITY = 1.25
local IDLE_DEPTH_KP = 4
local IDLE_DEPTH_MAX_SPEED = 5
local SEAT_NAMES = { "Seat", "SeatLeft", "PilotSeat", "MainSeat" }
local VERBOSE_LOGGING = false
local DEFAULT_PARAMS: SetupParams = {
	MaxForwardSpeed = 40,
	MaxReverseSpeed = 20,
	Acceleration = 8,
	MaxTurnSpeed = 45,
	TurnAcceleration = 60,
	DepthChangeSpeed = 15,
	UseProximityPrompt = true,
	ProximityPromptText = "Pilot",
}

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function setOwner(assembly: BasePart | Instance, owner: Player?)
	if assembly:IsA("BasePart") then
		assembly:SetNetworkOwner(owner)
	end

	for _, object in assembly:GetDescendants() do
		if object:IsA("BasePart") then
			object:SetNetworkOwner(owner)
		end
	end
end

local function setCharacterMassless(character: Model, massless: boolean)
	for _, part in GeometryUtils.getInstanceParts(character) do
		part.Massless = massless
	end
end

local function setCharacterVisibility(character: Model, transparency: number)
	for _, descendant in character:GetDescendants() do
		if descendant.Name == "HumanoidRootPart" then continue end
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.Transparency = transparency
		end
	end
end

local function findSeatReference(body: PVInstance): PVInstance?
	for _, desc in body:GetDescendants() do
		if not desc:IsA("PVInstance") then continue end
		if desc:IsA("Seat") or desc:IsA("VehicleSeat") then continue end
		if table.find(SEAT_NAMES, desc.Name) then
			return desc
		end
	end

	return nil
end

local function makeRootPart(cf: CFrame, forwardAxis: Vector3): Part
	local part = Instance.new("Part")
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(cf.Position, cf.Position + forwardAxis)
	part.Massless = true
	part.Name = "HullRoot"
	part.Size = Vector3.new(2, 2, 2)
	part.Transparency = 1
	return part
end

local function isSpinningPart(part: BasePart): boolean
	return part.Name == "PropHub" or string.find(part.Name, "Blade") ~= nil
end

local function detectHullBounds(body: PVInstance, rotors: { PVInstance }?): (Vector3, Vector3, Vector3)
	local refCF = GeometryUtils.getInstanceCFrame(body)
	local refCFInverse = refCF:Inverse()
	local parts = GeometryUtils.getInstanceParts(body)

	if #parts == 0 then
		local center, size = GeometryUtils.getBodyBounds(body)
		local localForward = if size.X > size.Z then Vector3.xAxis else -Vector3.zAxis
		return center, size, refCF:VectorToWorldSpace(localForward)
	end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local weightedPos = Vector3.zero
	local totalVolume = 0

	for _, part in parts do
		local localCF = refCFInverse * part.CFrame
		local hs = part.Size / 2
		local lp = localCF.Position
		local rx = math.abs(localCF.RightVector.X) * hs.X + math.abs(localCF.UpVector.X) * hs.Y + math.abs(localCF.LookVector.X) * hs.Z
		local ry = math.abs(localCF.RightVector.Y) * hs.X + math.abs(localCF.UpVector.Y) * hs.Y + math.abs(localCF.LookVector.Y) * hs.Z
		local rz = math.abs(localCF.RightVector.Z) * hs.X + math.abs(localCF.UpVector.Z) * hs.Y + math.abs(localCF.LookVector.Z) * hs.Z
		minX = math.min(minX, lp.X - rx); maxX = math.max(maxX, lp.X + rx)
		minY = math.min(minY, lp.Y - ry); maxY = math.max(maxY, lp.Y + ry)
		minZ = math.min(minZ, lp.Z - rz); maxZ = math.max(maxZ, lp.Z + rz)
		local vol = hs.X * hs.Y * hs.Z * 8
		weightedPos += (refCFInverse * part.Position) * vol
		totalVolume += vol
	end

	local localCenter = weightedPos / totalVolume
	local hullSize = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	local forwardAxis = if hullSize.X > hullSize.Z then Vector3.xAxis else -Vector3.zAxis

	local rotorLocalPos: Vector3? = nil
	if rotors and #rotors > 0 then
		local rotorWeighted = Vector3.zero
		local rotorVolume = 0
		for _, rotor in rotors do
			for _, part in GeometryUtils.getInstanceParts(rotor) do
				local vol = part.Size.X * part.Size.Y * part.Size.Z
				rotorWeighted += (refCFInverse * part.Position) * vol
				rotorVolume += vol
			end
		end

		if rotorVolume > 0 then
			rotorLocalPos = rotorWeighted / rotorVolume
		end
	end

	if rotorLocalPos then
		if forwardAxis:Dot(rotorLocalPos - localCenter) > 0 then
			forwardAxis = -forwardAxis
		end
	else
		local rudder = body:FindFirstChild("rudder")
		if rudder then
			local rudderLocalPos = refCFInverse * GeometryUtils.getInstanceCFrame(rudder).Position
			if forwardAxis:Dot(rudderLocalPos - localCenter) > 0 then
				forwardAxis = -forwardAxis
			end
		else
			local positiveVol, negativeVol = 0, 0
			for _, part in parts do
				local partLocalPos = refCFInverse * part.Position
				if forwardAxis:Dot(partLocalPos - localCenter) >= 0 then
					positiveVol += part.Size.X * part.Size.Y * part.Size.Z
				else
					negativeVol += part.Size.X * part.Size.Y * part.Size.Z
				end
			end

			if positiveVol > negativeVol then
				forwardAxis = -forwardAxis
			end
		end
	end

	return refCF * localCenter, hullSize, refCF:VectorToWorldSpace(forwardAxis)
end

-- Private Methods

function WaterSubmersible:_applyDensity(target: Instance?)
	local props = PhysicalProperties.new(DENSITY, 0.3, 0.5, 1, 1)
	for _, desc in (target or self._vesselModel):GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CustomPhysicalProperties = props
		end
	end
end

function WaterSubmersible:_rigVesselStructure()
	self:_applyDensity(self._bodyModel)

	local hullCenter, hullSize, forwardAxis = detectHullBounds(self._bodyModel, self._params.Rotors)

	local waterY = WaterUtils.getWaterLevel(hullCenter)
	if waterY then
		local deltaY = waterY - hullCenter.Y
		if math.abs(deltaY) > 1e-4 then
			self._bodyModel:PivotTo(self._bodyModel:GetPivot() + Vector3.new(0, deltaY, 0))
			hullCenter = hullCenter + Vector3.new(0, deltaY, 0)
		end
	else
		vwarn("no water detected at hull center; vessel placed as-is")
	end

	local hullPart = makeRootPart(CFrame.new(hullCenter), forwardAxis)
	hullPart.Parent = self._vesselModel
	self._vesselModel.PrimaryPart = hullPart
	ConstructionHelpers.weldAllParts(self._bodyModel, hullPart)

	for _, desc in self._bodyModel:GetDescendants() do
		if desc:IsA("BasePart") then desc.Massless = true end
	end

	self._hullCenter = hullCenter
	self._hullSize = hullSize
	self._forwardAxis = forwardAxis
	self._root = hullPart
	self._holdDepthY = hullPart.Position.Y
end

function WaterSubmersible:_rigRotorIfPresent()
	local rotors = self._params.Rotors
	if not rotors or #rotors == 0 then return end

	local motorIndex = 0
	for _, rotor in rotors do
		local rotorRoot
		local spinAxis: Vector3
		if rotor:IsA("BasePart") then
			for _, child in self._root:GetChildren() do
				if child:IsA("WeldConstraint") and child.Part1 == rotor then
					child:Destroy()
					break
				end
			end

			rotorRoot = rotor
			spinAxis = GeometryUtils.getFlattestAxis(rotor.Size)
		else
			local rotorModel = rotor
			local rotorParts = ConstructionHelpers.getAllParts({ rotorModel })

			if #rotorParts == 1 then
				local onlyPart = rotorParts[1]
				for _, child in self._root:GetChildren() do
					if child:IsA("WeldConstraint") and child.Part1 == onlyPart then
						child:Destroy()
						break
					end
				end

				rotorRoot = onlyPart
				spinAxis = GeometryUtils.getFlattestAxis(onlyPart.Size)
			else
				local boundsCenter, boundsSize = GeometryUtils.getBodyBounds(rotorModel)
				local boundsBox = Instance.new("Part")
				boundsBox.CanCollide = false
				boundsBox.CanQuery = false
				boundsBox.CastShadow = false
				boundsBox.CFrame = CFrame.new(boundsCenter)
				boundsBox.Massless = true
				boundsBox.Name = "RotorBounds"
				boundsBox.Size = boundsSize
				boundsBox.Transparency = 1
				boundsBox.Parent = rotorModel
				rotorModel.PrimaryPart = boundsBox
				rotorRoot = boundsBox
				spinAxis = self._forwardAxis

				for _, part in rotorParts do
					if not isSpinningPart(part) then continue end

					for _, child in self._root:GetChildren() do
						if child:IsA("WeldConstraint") and child.Part1 == part then
							child:Destroy()
							break
						end
					end

					ConstructionHelpers.makeWeld(rotorRoot, part)
				end
			end
		end

		motorIndex += 1
		local motorName = if motorIndex == 1 then "RotorMotor" else `RotorMotor{motorIndex}`
		local rotorMotor = Instance.new("Motor6D")
		rotorMotor.Name = motorName
		rotorMotor.Part0 = self._root
		rotorMotor.Part1 = rotorRoot
		rotorMotor.C0 = self._root.CFrame:Inverse() * rotorRoot.CFrame
		rotorMotor.C1 = CFrame.identity
		rotorMotor:SetAttribute("SpinAxisX", spinAxis.X)
		rotorMotor:SetAttribute("SpinAxisY", spinAxis.Y)
		rotorMotor:SetAttribute("SpinAxisZ", spinAxis.Z)
		rotorMotor.Parent = self._root
	end
end

function WaterSubmersible:_rigDriverSeat()
	local seat = Instance.new("VehicleSeat")
	seat.CanCollide = false
	seat.HeadsUpDisplay = false
	seat.Massless = true
	seat.MaxSpeed = 0
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Torque = 0
	seat.Transparency = 1
	seat.TurnSpeed = 0

	local seatRef = findSeatReference(self._bodyModel)
	if seatRef then
		local refCf = GeometryUtils.getInstanceCFrame(seatRef)
		seat.CFrame = CFrame.lookAlong(refCf.Position, self._forwardAxis)
	else
		local seatY = self._hullCenter.Y + self._hullSize.Y * 0.15
		seat.CFrame = CFrame.lookAlong(
			Vector3.new(self._hullCenter.X, seatY, self._hullCenter.Z),
			self._forwardAxis
		)
	end

	ConstructionHelpers.makeWeld(self._root, seat)
	seat.Parent = self._vesselModel
	self._driverSeat = seat
end

function WaterSubmersible:_rigPhysicsObjects()
	local att = Instance.new("Attachment")
	att.Name = "HullAttachment"
	att.Position = Vector3.zero
	att.Parent = self._root

	local surgeVel = Instance.new("LinearVelocity")
	surgeVel.Name = "SurgeVelocity"
	surgeVel.Attachment0 = att
	surgeVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	surgeVel.MaxAxesForce = Vector3.new(0, 0, math.huge)
	surgeVel.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	surgeVel.VectorVelocity = Vector3.zero
	surgeVel.Parent = self._root

	local yawVel = Instance.new("AngularVelocity")
	yawVel.Name = "YawVelocity"
	yawVel.Attachment0 = att
	yawVel.AngularVelocity = Vector3.zero
	yawVel.MaxTorque = math.huge
	yawVel.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	yawVel.Parent = self._root

	local depthVel = Instance.new("LinearVelocity")
	depthVel.Name = "DepthVelocity"
	depthVel.Attachment0 = att
	depthVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	depthVel.MaxAxesForce = Vector3.new(0, math.huge, 0)
	depthVel.RelativeTo = Enum.ActuatorRelativeTo.World
	depthVel.VectorVelocity = Vector3.zero
	depthVel.Parent = self._root

	self._surgeVelocity = surgeVel
	self._yawVelocity = yawVel
	self._depthVelocity = depthVel
end

function WaterSubmersible:_rigProximityPrompt()
	if not self._params.UseProximityPrompt then return end

	local drivePrompt = Instance.new("ProximityPrompt")
	drivePrompt.Name = "DrivePrompt"
	drivePrompt.ActionText = self._params.ProximityPromptText
	drivePrompt.MaxActivationDistance = math.min(self._hullSize.X, self._hullSize.Z) * 1.25
	drivePrompt.RequiresLineOfSight = false
	drivePrompt.Parent = self._driverSeat

	self._drivePrompt = drivePrompt
end

function WaterSubmersible:_rigController()
	local p = self._params
	self._root:SetAttribute("MaxForwardSpeed", p.MaxForwardSpeed)
	self._root:SetAttribute("MaxReverseSpeed", p.MaxReverseSpeed)
	self._root:SetAttribute("Acceleration", p.Acceleration)
	self._root:SetAttribute("MaxTurnSpeed", p.MaxTurnSpeed)
	self._root:SetAttribute("TurnAcceleration", p.TurnAcceleration)
	self._root:SetAttribute("DepthChangeSpeed", p.DepthChangeSpeed)

	local controllerScript = script:FindFirstChild("WaterSubmersibleClient")
	if not controllerScript then
		vwarn("WaterSubmersibleClient not found in", script:GetFullName())
		return
	end

	local clone = controllerScript:Clone()
	clone.Parent = self._vesselModel
	-- WaterSubmersibleClient is a ClientComponent ModuleScript (no Disabled).
	if clone:IsA("BaseScript") then
		clone.Disabled = false
	end

	local serverTemplate = script:FindFirstChild("WaterSubmersibleServer")
	assert(serverTemplate and serverTemplate:IsA("Script"), "WaterSubmersibleServer template is missing")
	local serverController = serverTemplate:Clone()
	serverController:SetAttribute("CASBehaviorManaged", true)
	serverController.Parent = self._vesselModel
	serverController.Disabled = false
end

function WaterSubmersible:_setupVessel()
	local rigModel = Instance.new("Model")
	rigModel.Name = `WaterSubmersible_{self._bodyModel.Name}`
	rigModel.Parent = self._bodyModel.Parent

	self._vesselModel = rigModel
	self._mainDump:Add(rigModel)
	self:_rigVesselStructure()
	self:_rigRotorIfPresent()
	self:_rigDriverSeat()
	self:_rigPhysicsObjects()
	self:_rigProximityPrompt()
	self:_rigController()
	self._bodyModel.Parent = rigModel
	self:_applyDensity(rigModel)

	StripCapabilityTag(rigModel)
end

-- Public Methods

function WaterSubmersible:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed class")
	self._mainDump:Destroy()
	for k, v in self do rawset(self, k, nil) end
	table.freeze(self)
end

-- Constructor

function WaterSubmersible.build(body: PVInstance, params: SetupParams)
	assert(body ~= nil, "must supply valid body PVInstance")

	local self = setmetatable({}, WaterSubmersible)

	self._mainDump = Dumpster.new()
	self._eventDump = self._mainDump:Extend()

	self._bodyModel = body
	self._depthVelocity = nil
	self._drivePrompt = nil
	self._driverSeat = nil
	self._forwardAxis = Vector3.zero
	self._holdDepthY = 0
	self._hullCenter = Vector3.zero
	self._hullSize = Vector3.zero
	self._lastDriver = nil
	self._root = nil
	self._surgeVelocity = nil
	self._vesselModel = nil
	self._yawVelocity = nil

	self._params = params or {}
	for k, v in DEFAULT_PARAMS do
		if self._params[k] ~= nil then continue end
		self._params[k] = v
	end

	self:_setupVessel()
	vprint(`Completed setup on {body.Name} with params:`, self._params)
	return self
end

-- Types

export type SetupParams = {
	Acceleration: number?,
	DepthChangeSpeed: number?,
	MaxForwardSpeed: number?,
	MaxReverseSpeed: number?,
	MaxTurnSpeed: number?,
	ProximityPromptText: string?,
	Rotors: { PVInstance }?,
	TurnAcceleration: number?,
	UseProximityPrompt: boolean?,
}

-- Return

return WaterSubmersible

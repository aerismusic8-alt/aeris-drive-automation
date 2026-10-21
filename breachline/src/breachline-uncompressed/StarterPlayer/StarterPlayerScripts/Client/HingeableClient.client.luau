--[[
	File: StarterPlayerScripts/Client/HingeableClient.client.luau

	Single shared client renderer for the Hingeable behavior. Discovers
	tagged wrapper folders via CollectionService and drives the local
	Motor6D each Heartbeat for the three kinematic modes (`Motor`, `Servo`,
	`Locked`). `Free` mode is skipped -- it's server-physics-driven and
	Roblox replicates it automatically.

	All timing math reads `workspace:GetServerTimeNow()` so every client
	(including late-joiners) derives an identical pose from the server's
	published `StartAngle` / `StartTime` snapshot.
]]--

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Behaviors = FourD:FindFirstChild("Behaviors")
local BehaviorRoot = Behaviors and Behaviors:FindFirstChild("Hingeable")
if BehaviorRoot == nil then
	return
end
local Constants = require(BehaviorRoot.Common.Constants)

-- Constants

local VERBOSE_LOGGING = false

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

-- Types

type Entry = {
	Wrapper: Folder,
	Motor: Motor6D?,
	MotorRef: ObjectValue?,
	BaseC0: CFrame,
	Mode: string,
	StartAngle: number,
	StartTime: number,
	Rate: number,
	TargetAngle: number,
	MaxSpeed: number,
	Damping: number,
	Stiffness: number,
	LockedAngle: number,
	CurrentAngle: number,
	CurrentVelocity: number,
	LastWrittenAngle: number?,
	Connections: { RBXScriptConnection },
}

-- State

local entries: { [Folder]: Entry } = {}

-- Helpers

local function resolveMotor(wrapper: Folder): (Motor6D?, ObjectValue?)
	local ref = wrapper:FindFirstChild(Constants.MOTOR_REF_VALUE_NAME)
	if not ref or not ref:IsA("ObjectValue") then
		return nil, nil
	end

	local value = ref.Value
	if value and value:IsA("Motor6D") then
		return value, ref
	end

	return nil, ref
end

local function readNumber(wrapper: Folder, name: string, fallback: number): number
	local v = wrapper:GetAttribute(name)
	if typeof(v) == "number" then
		return v
	end
	return fallback
end

local function readCFrame(wrapper: Folder, name: string): CFrame
	local v = wrapper:GetAttribute(name)
	if typeof(v) == "CFrame" then
		return v
	end
	return CFrame.identity
end

local function readMode(wrapper: Folder): string
	local v = wrapper:GetAttribute(Constants.ATTR_MODE)
	if typeof(v) == "string" then
		return v
	end
	return Constants.MODE_FREE
end

local function seedSnapshot(entry: Entry)
	-- On any StartTime / Mode / TargetAngle / Rate / LockedAngle change, the
	-- server has published a fresh authoritative snapshot. Reset the client's
	-- integration state so the spring/ramp restarts cleanly from that point.
	entry.CurrentAngle = entry.StartAngle
	entry.CurrentVelocity = 0
	entry.LastWrittenAngle = nil
end

local function refreshFromAttributes(entry: Entry)
	local wrapper = entry.Wrapper
	entry.Mode = readMode(wrapper)
	entry.BaseC0 = readCFrame(wrapper, Constants.ATTR_BASE_C0)
	entry.StartAngle = readNumber(wrapper, Constants.ATTR_START_ANGLE, 0)
	entry.StartTime = readNumber(wrapper, Constants.ATTR_START_TIME, 0)
	entry.Rate = readNumber(wrapper, Constants.ATTR_RATE, 0)
	entry.TargetAngle = readNumber(wrapper, Constants.ATTR_TARGET_ANGLE, 0)
	entry.MaxSpeed = readNumber(wrapper, Constants.ATTR_MAX_SPEED, 6)
	entry.Damping = readNumber(wrapper, Constants.ATTR_DAMPING, 1)
	entry.Stiffness = readNumber(wrapper, Constants.ATTR_STIFFNESS, 3)
	entry.LockedAngle = readNumber(wrapper, Constants.ATTR_LOCKED_ANGLE, 0)
end

local function register(wrapper: Instance)
	if not wrapper:IsA("Folder") then return end
	if entries[wrapper] then return end

	local motor, motorRef = resolveMotor(wrapper)

	local entry: Entry = {
		Wrapper = wrapper,
		Motor = motor,
		MotorRef = motorRef,
		BaseC0 = CFrame.identity,
		Mode = Constants.MODE_FREE,
		StartAngle = 0,
		StartTime = 0,
		Rate = 0,
		TargetAngle = 0,
		MaxSpeed = 6,
		Damping = 1,
		Stiffness = 3,
		LockedAngle = 0,
		CurrentAngle = 0,
		CurrentVelocity = 0,
		LastWrittenAngle = nil,
		Connections = {},
	}

	refreshFromAttributes(entry)
	entry.CurrentAngle = entry.StartAngle

	-- Watch every attribute that influences pose. Snapshot-resetting ones
	-- (Mode, StartTime, TargetAngle, Rate, LockedAngle) also seed integration
	-- state so the renderer picks up the new state on the next tick without
	-- a jump.
	local function bind(name: string, resetSnapshot: boolean)
		local conn = wrapper:GetAttributeChangedSignal(name):Connect(function()
			refreshFromAttributes(entry)
			if resetSnapshot then
				seedSnapshot(entry)
			end
		end)
		table.insert(entry.Connections, conn)
	end

	bind(Constants.ATTR_MODE, true)
	bind(Constants.ATTR_START_TIME, true)
	bind(Constants.ATTR_START_ANGLE, false)
	-- TargetAngle changes must not reseed CurrentAngle; for Servo we want the
	-- integrator to keep its live pose and spring toward the new target.
	bind(Constants.ATTR_TARGET_ANGLE, false)
	bind(Constants.ATTR_RATE, true)
	bind(Constants.ATTR_LOCKED_ANGLE, true)
	bind(Constants.ATTR_BASE_C0, false)
	bind(Constants.ATTR_MAX_SPEED, false)
	bind(Constants.ATTR_DAMPING, false)
	bind(Constants.ATTR_STIFFNESS, false)

	if motorRef then
		local conn = motorRef.Changed:Connect(function()
			local newMotor = motorRef.Value
			if newMotor and newMotor:IsA("Motor6D") then
				entry.Motor = newMotor
				entry.LastWrittenAngle = nil
			else
				entry.Motor = nil
			end
		end)
		table.insert(entry.Connections, conn)
	end

	entries[wrapper] = entry
	vprint("registered", wrapper:GetFullName())
end

local function unregister(wrapper: Instance)
	local entry = entries[wrapper :: Folder]
	if not entry then return end

	for _, conn in entry.Connections do
		conn:Disconnect()
	end
	entries[wrapper :: Folder] = nil
	vprint("unregistered", wrapper:GetFullName())
end

local function tick(dt: number)
	local now = workspace:GetServerTimeNow()

	for _, entry in entries do
		local motor = entry.Motor
		if not motor or motor.Parent == nil then
			continue
		end

		local mode = entry.Mode
		if mode == Constants.MODE_FREE then
			-- Server physics owns Free mode; nothing to draw here.
			continue
		end

		local angle: number
		if mode == Constants.MODE_MOTOR then
			angle = entry.StartAngle + entry.Rate * (now - entry.StartTime)
		elseif mode == Constants.MODE_LOCKED then
			angle = entry.LockedAngle
		elseif mode == Constants.MODE_SERVO then
			-- Stiffness exposed as a "snappier means higher" knob; under the hood it
			-- is Hz so settle time at Damping = 1 is ~ 1 / Stiffness seconds.
			local omega = 2 * math.pi * math.max(entry.Stiffness, 0)
			local zeta = math.max(entry.Damping, 0)
			local err = entry.CurrentAngle - entry.TargetAngle
			local accel = -2 * zeta * omega * entry.CurrentVelocity - omega * omega * err
			entry.CurrentVelocity = math.clamp(entry.CurrentVelocity + accel * dt, -entry.MaxSpeed, entry.MaxSpeed)
			entry.CurrentAngle = entry.CurrentAngle + entry.CurrentVelocity * dt
			angle = entry.CurrentAngle
		else
			vwarn("unknown mode", mode, "on", entry.Wrapper:GetFullName())
			continue
		end

		if entry.LastWrittenAngle ~= angle then
			motor.C0 = entry.BaseC0 * CFrame.fromAxisAngle(Vector3.xAxis, angle)
			entry.LastWrittenAngle = angle
		end
	end
end

-- Bootstrap

for _, wrapper in CollectionService:GetTagged(Constants.WRAPPER_TAG) do
	register(wrapper)
end

CollectionService:GetInstanceAddedSignal(Constants.WRAPPER_TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(Constants.WRAPPER_TAG):Connect(unregister)

RunService.Heartbeat:Connect(tick)

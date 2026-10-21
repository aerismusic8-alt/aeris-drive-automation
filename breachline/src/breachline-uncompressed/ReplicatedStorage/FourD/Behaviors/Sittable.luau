--[[
	File: Sittable/init.luau

	Sittable behavior. Adds an invisible Seat to a BasePart so players can sit
	on benches, chairs, stools, or any flat surface without a full vehicle rig.
	The seat is welded to the host part, so passengers ride along with whatever
	the host is attached to (a moving vehicle, a spinning carousel, etc.).

	Public API:
		Sittable.new(host, params?) -> Sittable
		Sittable:GetSeat -> Seat
		Sittable:GetHost -> BasePart
		Sittable:Destroy
]]--

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)

-- Root

local Sittable = {}
Sittable.__index = Sittable

-- Local Functions

local function findAnyBasePart(pvInstance: PVInstance): BasePart?
	if pvInstance:IsA("BasePart") then
		return pvInstance
	end
	if pvInstance:IsA("Model") then
		if pvInstance.PrimaryPart then
			return pvInstance.PrimaryPart
		end
		for _, descendant in pvInstance:GetDescendants() do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end
	return nil
end

-- Internal Methods

function Sittable:_assertAlive()
	assert(table.isfrozen(self) == false, "cannot operate on a destroyed Sittable")
end

-- Public Methods

---Returns the Seat instance.
function Sittable:GetSeat(): Seat
	self:_assertAlive()
	return self._seat
end

---Returns the host BasePart the seat is welded to.
function Sittable:GetHost(): BasePart
	self:_assertAlive()
	return self._host
end

---Drains the Dumpster, nils every field, and freezes self.
function Sittable:Destroy()
	self:_assertAlive()
	self._dumpster:Destroy()
	for key in self do
		rawset(self, key, nil)
	end
	table.freeze(self)
end

-- Types

export type SittableParams = {
	---Seat offset in host-local space. When nil, the seat is placed just above
	---the host's top surface, oriented to the host's local frame.
	Offset: CFrame?,
	---Whether to use a VehicleSeat instead of a Seat. VehicleSeats expose
	---throttle/steer inputs for scripted rigs. Default false.
	VehicleSeat: boolean?,
}

-- Constructor

---Creates a Sittable on `host`. The host can be any PVInstance with at least
---one BasePart. An invisible, non-colliding Seat is welded to the resolved
---host part just above its top surface (or at the given Offset).
function Sittable.new(host: PVInstance, params: SittableParams?): Sittable
	params = params or {}

	local hostPart = findAnyBasePart(host)
	assert(hostPart, `host "{host:GetFullName()}" must contain at least one BasePart`)

	local mainDump = Dumpster.new()
	mainDump:AttachTo(hostPart)

	local useVehicleSeat = params.VehicleSeat == true

	-- Size proportional to the host.
	local s = hostPart.Size
	local wide = math.max(s.X, s.Z, 1)
	local narrow = math.max(math.min(s.X, s.Z), 1)

	local seat: Seat
	if useVehicleSeat then
		seat = Instance.new("VehicleSeat")
	else
		seat = Instance.new("Seat")
	end
	seat.Name = "Sittable_Seat"
	seat.Size = Vector3.new(wide * 0.8, 0.4, narrow * 0.8)
	seat.CanCollide = false
	seat.Transparency = 1
	seat.Massless = true

	-- Position: just above the host's top surface in host-local orientation.
	local offset = params.Offset
	if not offset then
		offset = CFrame.new(0, s.Y * 0.5 + 0.4, 0)
	end
	seat.CFrame = hostPart.CFrame * offset
	seat.Parent = hostPart

	-- Weld to ride with the host.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hostPart
	weld.Part1 = seat
	weld.Parent = seat
	seat.Anchored = false

	mainDump:Add(seat)

	local self = setmetatable({
		_dumpster = mainDump,
		_host = hostPart,
		_seat = seat,
	}, Sittable)

	return self
end

export type Sittable = typeof(Sittable)

return Sittable

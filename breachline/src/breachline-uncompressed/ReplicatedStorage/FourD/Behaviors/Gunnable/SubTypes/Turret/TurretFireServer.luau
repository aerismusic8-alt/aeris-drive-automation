--[[
	FourDServerComponent -- started at Play by ServerScriptService.FourDServerRuntime.

	Restores turret firing. The relay TurretFire -> launcher:Fire, gated by the
	controlling player, was an in-memory connection made inside the edit-time
	bind() (Gunnable's connectLauncherFire) and did not survive to Play: a compiled
	tank received TurretFire on the server with nothing listening and never spawned
	a shell. This rebuilds the launcher from the state Launcher.new persisted
	(GunnableLauncherConfig + LauncherShot + the origin/projectile refs) and
	reconnects the relay plus aim-arc viewer tracking. Gunnable clones one of these
	into the rig when a launcher is bound to a turret.
]]

-- Resolve FourD through ReplicatedStorage, not script:FindFirstAncestor("FourD"):
-- this module is cloned into the rig (e.g. Workspace.Tank), so it has no FourD
-- ancestor at Play. Matches how the co-located TurretServer/LauncherClient resolve it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FourD = ReplicatedStorage:WaitForChild("FourD")
local Gunnable = FourD:WaitForChild("Behaviors"):WaitForChild("Gunnable")
local Controller = require(Gunnable:WaitForChild("Common"):WaitForChild("Controller"))
local Launcher = require(Gunnable:WaitForChild("SubTypes"):WaitForChild("Launcher"))

local function refValue(model: Instance, name: string): Instance?
	local ref = model:FindFirstChild(name)
	if ref and ref:IsA("ObjectValue") then return ref.Value end
	return nil
end

return function(root: Instance, _manifest: Instance)
	assert(root:IsA("Model"), "[TurretFireServer] root must be a Model")

	local fireEvent = root:WaitForChild("TurretFire", 10)
	assert(fireEvent and fireEvent:IsA("RemoteEvent"), "[TurretFireServer] missing TurretFire RemoteEvent")

	local launcher = Launcher.rehydrate(root)
	assert(launcher, "[TurretFireServer] could not rehydrate launcher from persisted config")

	local seatOpts = {
		PrimarySeat = refValue(root, "Gunnable_DriverSeatRef"),
		SecondarySeat = refValue(root, "Gunnable_GunnerSeatRef"),
	}

	local connections: { RBXScriptConnection } = {}

	local function updateAimArcViewers()
		local controller = Controller.resolve(root, seatOpts)
		launcher:SetAimArcViewer(controller)
	end

	table.insert(
		connections,
		fireEvent.OnServerEvent:Connect(function(player, originHint, directionHint)
			if Controller.resolve(root, seatOpts) ~= player then return end
			launcher:Fire(originHint, directionHint)
		end)
	)
	table.insert(
		connections,
		root:GetAttributeChangedSignal(Controller.OVERRIDE_ATTR):Connect(updateAimArcViewers)
	)

	local driverSeat = seatOpts.PrimarySeat
	if driverSeat and driverSeat:IsA("BasePart") then
		table.insert(connections, driverSeat:GetPropertyChangedSignal("Occupant"):Connect(updateAimArcViewers))
	end
	local gunnerSeat = seatOpts.SecondarySeat
	if gunnerSeat and gunnerSeat:IsA("BasePart") then
		table.insert(connections, gunnerSeat:GetPropertyChangedSignal("Occupant"):Connect(updateAimArcViewers))
	end
	updateAimArcViewers()

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

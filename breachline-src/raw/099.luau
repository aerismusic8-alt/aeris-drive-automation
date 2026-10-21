--[[
	File: Common/TracerRender.luau

	Client-side tracer renderer shared by Turret and Hardpoint. Mirrors the
	Launcher SubType's render path: the server broadcasts a single TracerShot
	payload per fired barrel; each client clones the cosmetic bullet template
	locally and animates it along a straight line (gravity = 0) anchored to
	`workspace:GetServerTimeNow()`, so all observers converge on the same
	impact moment regardless of latency. No moving server-owned parts = no
	replication chop.
]]--

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Trajectory = require(script.Parent:WaitForChild("Trajectory"))

local TracerRender = {}

export type TracerShotPayload = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Gravity: number,
	ImpactPoint: Vector3,
	ImpactTime: number,
	TravelTime: number,
	Expired: boolean,
}

local function makeInert(projectile: PVInstance)
	local parts: { BasePart } = {}
	if projectile:IsA("BasePart") then
		table.insert(parts, projectile)
	end

	for _, descendant in projectile:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
end

---Binds a TracerShot listener to `model`. Each broadcast clones
---`templateRef.Value` into a per-model workspace render Folder and animates
---it along the shot path until impact. Returns a cleanup closure that
---disconnects everything and destroys the render Folder.
function TracerRender.bind(model: Model, tracerEvent: UnreliableRemoteEvent, templateRef: ObjectValue): () -> ()
	local renderFolder = Instance.new("Folder")
	renderFolder.Name = model.Name .. "_GunnableBullets"
	renderFolder.Parent = Workspace

	local connections: { RBXScriptConnection } = {}

	local function renderShot(shot: TracerShotPayload)
		local template = templateRef.Value
		if not template or not template:IsA("PVInstance") then return end

		local projectile = template:Clone()
		makeInert(projectile)
		projectile:PivotTo(CFrame.new(shot.Origin))
		projectile.Parent = renderFolder

		local launchTime = shot.ImpactTime - shot.TravelTime

		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function()
			if not projectile.Parent then
				connection:Disconnect()
				return
			end

			local elapsed = Workspace:GetServerTimeNow() - launchTime
			if elapsed >= shot.TravelTime then
				connection:Disconnect()
				projectile:Destroy()
				return
			end

			local position = Trajectory.positionAt(shot.Origin, shot.Direction, shot.Speed, shot.Gravity, elapsed)
			local velocity = Trajectory.velocityAt(shot.Direction, shot.Speed, shot.Gravity, elapsed)
			if velocity.Magnitude > 1e-4 then
				projectile:PivotTo(CFrame.lookAt(position, position + velocity))
			else
				projectile:PivotTo(CFrame.new(position))
			end
		end)

		table.insert(connections, connection)
	end

	table.insert(connections, tracerEvent.OnClientEvent:Connect(renderShot))

	local function cleanup()
		for _, c in connections do
			if c.Connected then c:Disconnect() end
		end
		table.clear(connections)

		if renderFolder.Parent then
			renderFolder:Destroy()
		end
	end

	table.insert(connections, model.Destroying:Connect(cleanup))

	return cleanup
end

return TracerRender

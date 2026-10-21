--[[
	FourDServerComponent -- started at Play by ServerScriptService.FourDServerRuntime.

	Restores the taxi sign toggle. The relay TaxiSignToggleEvent -> flip the roof
	sign light, gated by the driving player, was an in-memory connection made
	inside the edit-time bind() (Taxi6's MakeFunctional) and did not survive to
	Play: a compiled taxi received TaxiSignToggleEvent on the server with nothing
	listening, so pressing T did nothing. Taxi6 clones one of these into the rig
	when a sign light is present.

	State is fully persisted: the toggle state is the `taxiSignOn` attribute and
	the sign light is reached through the Taxi6_SignLightRef ObjectValue, so this
	rebuilds nothing -- it just reconnects the relay.
]]

-- Resolve FourD through ReplicatedStorage, not script:FindFirstAncestor("FourD"):
-- this module is cloned into the rig (Workspace.<taxi>), so it has no FourD
-- ancestor at Play. Matches how the co-located TaxiClient resolves it.
local _ReplicatedStorage = game:GetService("ReplicatedStorage")

local function refValue(model: Instance, name: string): Instance?
	local ref = model:FindFirstChild(name)
	if ref and ref:IsA("ObjectValue") then
		return ref.Value
	end
	return nil
end

return function(root: Instance, _manifest: Instance)
	assert(root:IsA("Model"), "[TaxiSignServer] root must be a Model")

	local toggleEvent = root:WaitForChild("TaxiSignToggleEvent", 10)
	assert(toggleEvent and toggleEvent:IsA("RemoteEvent"), "[TaxiSignServer] missing TaxiSignToggleEvent RemoteEvent")

	local light = refValue(root, "Taxi6_SignLightRef")
	assert(light and light:IsA("Light"), "[TaxiSignServer] missing Taxi6_SignLightRef -> Light")

	-- The persisted attribute is the source of truth for the current state; sync
	-- the light to it in case the two ever drift.
	local signOn = root:GetAttribute("taxiSignOn") == true
	light.Enabled = signOn

	local connections: { RBXScriptConnection } = {}
	table.insert(
		connections,
		toggleEvent.OnServerEvent:Connect(function(firingPlayer: Player)
			local seat = root:FindFirstChildWhichIsA("VehicleSeat", true)
			if not seat then return end
			local occupant = seat.Occupant
			if not occupant then return end
			local character = firingPlayer.Character
			if not character or occupant.Parent ~= character then return end

			signOn = not signOn
			root:SetAttribute("taxiSignOn", signOn)
			light.Enabled = signOn
		end)
	)

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

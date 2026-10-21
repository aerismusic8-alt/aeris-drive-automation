--!strict
--[[
	File: PushRegistry.luau

	Server-side record of which pushable each player is currently holding.

	PushableServer runs as one script instance per cart, so no single instance can
	tell that a player already has hold of a different cart -- its activePlayer is
	only ever about itself. Without a shared view a player could grab any number of
	pushables at once, ending up with several carts stacked in front of them and two
	competing IKControls per arm.

	Claiming is exclusive: taking a new cart releases whatever the player was already
	holding, via that cart's own release function, before the claim is recorded.

	Server state only. A client that requires this gets its own unused copy.
]]

local Players = game:GetService("Players")

local PushRegistry = {}

export type ReleaseFn = () -> ()

type Claim = {
	model: Instance,
	release: ReleaseFn,
}

local claims: { [Player]: Claim } = {}

---Gives `player` exclusively to `model`, releasing anything else they held first.
---Returns once the previous holder's release has run, so callers can treat the
---player as free.
function PushRegistry.claim(player: Player, model: Instance, release: ReleaseFn)
	local existing = claims[player]
	if existing and existing.model ~= model then
		-- Dropped before releasing so the outgoing cart's release -> clear round trip
		-- cannot see a half-written claim, and so a release that errors cannot leave
		-- the player owned by a cart they are no longer holding.
		claims[player] = nil
		local ok, err = pcall(existing.release)
		if not ok then
			warn(string.format("[PushRegistry] release of '%s' failed: %s", existing.model.Name, tostring(err)))
		end
	end

	claims[player] = { model = model, release = release }
end

---Drops `player`'s claim, but only if `model` still owns it. The guard keeps a late
---release from a cart the player already left from clearing their current one.
function PushRegistry.clear(player: Player, model: Instance)
	local existing = claims[player]
	if existing and existing.model == model then
		claims[player] = nil
	end
end

function PushRegistry.heldModel(player: Player): Instance?
	local existing = claims[player]
	return if existing then existing.model else nil
end

-- A leaving player's cart normally releases itself and clears its own claim. This
-- is the backstop for the case where it cannot, so the table never retains a Player
-- that has gone.
Players.PlayerRemoving:Connect(function(player: Player)
	claims[player] = nil
end)

return PushRegistry

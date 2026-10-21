--!strict
-- What dying costs.
--
-- Death used to be free: the player was sent home and respawned four seconds
-- later with every coin still in the bank. In the fields that can kill you that
-- made the whole risk side of the game imaginary — you could not lose, so there
-- was nothing to weigh against pushing one more wave. The training field still
-- cannot kill, so a new player still learns the buttons without a penalty.
--
-- Pure logic, no Roblox globals, so the rule is tested under the CLI like the
-- rest of the shared modules.

local Config = require("./Config")

local Death = {}

export type Penalty = {
	-- Coins actually taken. Zero when the player was not charged.
	coins: number,
	-- Balance after the charge, which is what the caller stores back.
	remaining: number,
	-- True when a charge was applied, so the caller can decide whether to tell
	-- the player at all. A free death should not print a "you lost 0" line.
	charged: boolean,
}

-- The charge for one death, given the player's balance and the place they died.
--
-- `lethal` is passed in rather than looked up so this stays independent of the
-- zone table, and so the caller cannot accidentally charge in the training
-- field by asking the wrong question.
function Death.penalty(coins: number, lethal: boolean): Penalty
	if not lethal then
		return { coins = 0, remaining = coins, charged = false }
	end
	-- A player with almost nothing keeps what they have. Taking the last coins
	-- off somebody who just died is how a bad session becomes a reason to leave.
	if coins < Config.Death.MinCoinsToCharge then
		return { coins = 0, remaining = coins, charged = false }
	end

	local take = math.floor(coins * Config.Death.CoinLossPercent)
	if take > Config.Death.MaxCoinLoss then
		take = Config.Death.MaxCoinLoss
	end
	-- The cap can exceed a small balance, and the percent can round to zero on a
	-- balance just over the floor. Neither may take more than the player has, and
	-- a zero charge is reported as no charge rather than as a loss of nothing.
	if take > coins then
		take = coins
	end
	if take <= 0 then
		return { coins = 0, remaining = coins, charged = false }
	end

	return { coins = take, remaining = coins - take, charged = true }
end

return Death

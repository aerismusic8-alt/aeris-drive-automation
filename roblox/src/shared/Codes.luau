--!strict
-- Promo codes. Pure Luau: no Roblox globals.
--
-- Codes are the cheapest growth loop a game has: a creator posts one on
-- YouTube or TikTok, viewers open the game to redeem it, and the game appears
-- in more sessions that day. Each code is single-use per player.

local Config = require("./Config")

local Codes = {}

export type CodeDef = {
	code: string,
	coins: number,
	xp: number,
	luckCharges: number,
	expiresAt: number?, -- unix seconds; nil means it never expires
}

export type Redemption = {
	code: string,
	at: number,
}

-- Codes are matched case-insensitively but stored uppercase.
local CODES: { [string]: CodeDef } = {
	RELEASE = { code = "RELEASE", coins = 5000, xp = 250, luckCharges = 1 },
	AXARENA = { code = "AXARENA", coins = 2500, xp = 150, luckCharges = 0 },
	FARM2026 = { code = "FARM2026", coins = 7500, xp = 400, luckCharges = 2 },
	TRENDING = { code = "TRENDING", coins = 10000, xp = 500, luckCharges = 3 },
	THANKYOU = { code = "THANKYOU", coins = 1000, xp = 100, luckCharges = 1 },
}

local function normalize(code: string): string
	return string.upper(string.gsub(code, "%s", ""))
end

function Codes.get(code: string): CodeDef?
	if type(code) ~= "string" then
		return nil
	end
	return CODES[normalize(code)]
end

function Codes.list(): { CodeDef }
	local out = {}
	for _, def in pairs(CODES) do
		table.insert(out, def)
	end
	table.sort(out, function(a, b)
		return a.code < b.code
	end)
	return out
end

-- Has this player already used the code? `redeemed` maps code -> redemption.
function Codes.hasRedeemed(redeemed: { [string]: Redemption }, code: string): boolean
	local def = Codes.get(code)
	if not def then
		return false
	end
	return redeemed[def.code] ~= nil
end

-- Try to redeem. Returns the updated map, the reward and nil, or nil plus a
-- reason. Reasons are stable strings so the client can show a clear message.
function Codes.redeem(
	redeemed: { [string]: Redemption },
	code: string,
	now: number
): ({ [string]: Redemption }?, CodeDef?, string?)
	local def = Codes.get(code)
	if not def then
		return nil, nil, "UNKNOWN_CODE"
	end

	if redeemed[def.code] then
		return nil, nil, "ALREADY_REDEEMED"
	end

	if def.expiresAt and now > def.expiresAt then
		return nil, nil, "CODE_EXPIRED"
	end

	local next = {}
	for k, v in pairs(redeemed) do
		next[k] = v
	end
	next[def.code] = { code = def.code, at = now }

	return next, def, nil
end

function Codes.snapshot(redeemed: { [string]: Redemption }): { [string]: Redemption }
	local out = {}
	if type(redeemed) ~= "table" then
		return out
	end
	for rawCode, entry in pairs(redeemed) do
		local def = Codes.get(rawCode)
		-- Drop codes that no longer exist so old saves stay clean.
		if def and type(entry) == "table" then
			out[def.code] = {
				code = def.code,
				at = math.max(0, math.floor(tonumber(entry.at) or 0)),
			}
		end
	end
	return out
end

function Codes.fromSnapshot(raw: any): { [string]: Redemption }
	return Codes.snapshot(raw)
end

return Codes

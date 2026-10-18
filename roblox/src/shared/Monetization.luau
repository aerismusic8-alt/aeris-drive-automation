--!strict
-- Monetization catalogue and purchase validation. Pure Luau.
--
-- The catalogue lives on the server so prices and grants cannot be forged by
-- the client. Roblox's own purchase flow confirms the Robux was really spent;
-- this module decides what the player is owed and guards against replay.

local Config = require("./Config")

local Monetization = {}

export type ProductKind = "gamepass" | "devproduct"

export type Product = {
	id: string,
	kind: ProductKind,
	name: string,
	robux: number,
	description: string,
	-- One-time purchase (gamepass) or repeatable (dev product).
	repeatable: boolean,
}

-- Robux prices. Keep these in one place: they are shown in the UI and used
-- to sanity-check what the platform reports.
local PRODUCTS: { [string]: Product } = {
	Vip = {
		id = "Vip",
		kind = "gamepass",
		name = "VIP",
		robux = 199,
		description = "2x coins, 1.5x XP, and 2 extra pet slots. Permanent.",
		repeatable = false,
	},
	AutoHatch = {
		id = "AutoHatch",
		kind = "gamepass",
		name = "Auto Hatch",
		robux = 149,
		description = "Automatically opens eggs while you farm. Permanent.",
		repeatable = false,
	},
	FastWalk = {
		id = "FastWalk",
		kind = "gamepass",
		name = "Super Speed",
		robux = 99,
		description = "+8 walk speed, permanent.",
		repeatable = false,
	},
	DoubleCoins1h = {
		id = "DoubleCoins1h",
		kind = "devproduct",
		name = "2x Coins (1 hour)",
		robux = 25,
		description = "Double coin rewards for one hour.",
		repeatable = true,
	},
	LuckyBoost = {
		id = "LuckyBoost",
		kind = "devproduct",
		name = "Lucky Boost",
		robux = 35,
		description = "Improves your next 10 egg hatches.",
		repeatable = true,
	},
	ZonePass = {
		id = "ZonePass",
		kind = "gamepass",
		name = "Zone Pass",
		robux = 299,
		description = "Unlocks every zone regardless of level. Permanent.",
		repeatable = false,
	},
}

local ORDER = { "Vip", "AutoHatch", "FastWalk", "DoubleCoins1h", "LuckyBoost", "ZonePass" }

function Monetization.get(productId: string): Product?
	return PRODUCTS[productId]
end

function Monetization.list(): { Product }
	local out: { Product } = {}
	for _, id in ipairs(ORDER) do
		table.insert(out, PRODUCTS[id])
	end
	return out
end

-- Per-player entitlements and temporary boosts.
export type Entitlements = {
	owned: { [string]: boolean },
	-- Timestamps (os.time) at which a temporary boost expires.
	boosts: { [string]: number },
	luckyCharges: number,
}

function Monetization.newEntitlements(): Entitlements
	return { owned = {}, boosts = {}, luckyCharges = 0 }
end

function Monetization.owns(ent: Entitlements, productId: string): boolean
	return ent.owned[productId] == true
end

export type GrantResult = {
	entitlements: Entitlements,
	-- What the caller should actually do, so the side effects stay visible.
	effect: string?,
}

-- Apply a purchase. `now` is os.time. Returns nil plus a reason when the
-- product is unknown or the purchase must not be granted again.
function Monetization.grant(
	ent: Entitlements,
	productId: string,
	now: number
): (GrantResult?, string?)
	local product = PRODUCTS[productId]
	if not product then
		return nil, "UNKNOWN_PRODUCT"
	end
	if not product.repeatable and Monetization.owns(ent, productId) then
		return nil, "ALREADY_OWNED"
	end

	local next: Entitlements = {
		owned = {},
		boosts = {},
		luckyCharges = ent.luckyCharges,
	}
	for k, v in pairs(ent.owned) do
		next.owned[k] = v
	end
	for k, v in pairs(ent.boosts) do
		next.boosts[k] = v
	end

	local effect: string? = nil

	if product.kind == "gamepass" then
		next.owned[productId] = true
		effect = "GRANTED_PERMANENT"
	else
		if productId == "DoubleCoins1h" then
			local base = math.max(now, next.boosts[productId] or 0)
			next.boosts[productId] = base + 3600
			effect = "COIN_BOOST"
		elseif productId == "LuckyBoost" then
			next.luckyCharges += 10
			effect = "LUCKY_CHARGES"
		else
			effect = "GRANTED_CONSUMABLE"
		end
	end

	return { entitlements = next, effect = effect }, nil
end

-- Coin multiplier from active boosts. `now` is os.time.
function Monetization.coinMultiplier(ent: Entitlements, now: number): number
	local mult = 1
	if Monetization.owns(ent, "Vip") then
		mult *= Config.Monetization.VipCoinMultiplier
	end
	local until_ = ent.boosts["DoubleCoins1h"]
	if until_ and until_ > now then
		mult *= 2
	end
	return mult
end

function Monetization.xpMultiplier(ent: Entitlements): number
	if Monetization.owns(ent, "Vip") then
		return Config.Monetization.VipXpMultiplier
	end
	return 1
end

function Monetization.walkSpeedBonus(ent: Entitlements): number
	if Monetization.owns(ent, "FastWalk") then
		return 8
	end
	return 0
end

function Monetization.hasZonePass(ent: Entitlements): boolean
	return Monetization.owns(ent, "ZonePass")
end

function Monetization.hasAutoHatch(ent: Entitlements): boolean
	return Monetization.owns(ent, "AutoHatch")
end

-- Consume one lucky charge if available. Returns the luck multiplier to use.
function Monetization.takeLuck(ent: Entitlements): number
	if ent.luckyCharges > 0 then
		ent.luckyCharges -= 1
		return 2
	end
	return 1
end

function Monetization.fromSnapshot(data: any): Entitlements
	local ent = Monetization.newEntitlements()
	if type(data) ~= "table" then
		return ent
	end
	for _, product in ipairs(Monetization.list()) do
		if type(data.owned) == "table" and data.owned[product.id] == true then
			ent.owned[product.id] = true
		end
	end
	if type(data.boosts) == "table" then
		for k, v in pairs(data.boosts) do
			local n = tonumber(v)
			if n and n > 0 and PRODUCTS[k] then
				ent.boosts[k] = math.floor(n)
			end
		end
	end
	ent.luckyCharges = math.max(0, math.floor(tonumber(data.luckyCharges) or 0))
	return ent
end

return Monetization

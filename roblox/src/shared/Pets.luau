--!strict
-- Pet collection, hatching and equipping. Pure Luau.
--
-- Pets are the retention engine: they are the reason a player returns, and
-- the reason a player spends Robux when a hatch does not go their way.

local Config = require("./Config")

local Pets = {}

export type Rarity = string

export type PetDef = {
	id: string,
	name: string,
	rarity: Rarity,
	-- Multipliers applied while the pet is equipped.
	coinMultiplier: number,
	damageMultiplier: number,
}

export type OwnedPet = {
	uid: number,
	petId: string,
	level: number,
}

export type Inventory = {
	pets: { OwnedPet },
	equipped: { number },
	nextUid: number,
	hatches: number,
}

local DEFS: { [string]: PetDef } = {
	Pup = { id = "Pup", name = "Pup", rarity = "Common", coinMultiplier = 1.05, damageMultiplier = 1.02 },
	Kitten = { id = "Kitten", name = "Kitten", rarity = "Common", coinMultiplier = 1.05, damageMultiplier = 1.02 },
	Bunny = { id = "Bunny", name = "Bunny", rarity = "Uncommon", coinMultiplier = 1.15, damageMultiplier = 1.05 },
	Fox = { id = "Fox", name = "Fox", rarity = "Uncommon", coinMultiplier = 1.15, damageMultiplier = 1.05 },
	Wolf = { id = "Wolf", name = "Wolf", rarity = "Rare", coinMultiplier = 1.4, damageMultiplier = 1.15 },
	Panda = { id = "Panda", name = "Panda", rarity = "Rare", coinMultiplier = 1.4, damageMultiplier = 1.15 },
	Dragon = { id = "Dragon", name = "Dragon", rarity = "Epic", coinMultiplier = 2.2, damageMultiplier = 1.4 },
	Phoenix = { id = "Phoenix", name = "Phoenix", rarity = "Epic", coinMultiplier = 2.2, damageMultiplier = 1.4 },
	Unicorn = { id = "Unicorn", name = "Unicorn", rarity = "Legendary", coinMultiplier = 4.0, damageMultiplier = 1.8 },
	Voidling = { id = "Voidling", name = "Voidling", rarity = "Mythic", coinMultiplier = 8.0, damageMultiplier = 2.5 },
}

local PET_ORDER = {
	"Pup", "Kitten", "Bunny", "Fox", "Wolf",
	"Panda", "Dragon", "Phoenix", "Unicorn", "Voidling",
}

-- Egg definitions. `weight` is the relative drop chance of each pet.
export type EggDef = {
	id: string,
	name: string,
	cost: number,
	-- Minimum level required to open this egg.
	levelRequirement: number,
	weights: { { petId: string, weight: number } },
}

local EGGS: { [string]: EggDef } = {
	Basic = {
		id = "Basic",
		name = "Basic Egg",
		cost = 100,
		levelRequirement = 1,
		weights = {
			{ petId = "Pup", weight = 40 },
			{ petId = "Kitten", weight = 35 },
			{ petId = "Bunny", weight = 15 },
			{ petId = "Fox", weight = 8 },
			{ petId = "Wolf", weight = 2 },
		},
	},
	Spotted = {
		id = "Spotted",
		name = "Spotted Egg",
		cost = 1200,
		levelRequirement = 10,
		weights = {
			{ petId = "Bunny", weight = 30 },
			{ petId = "Fox", weight = 28 },
			{ petId = "Wolf", weight = 20 },
			{ petId = "Panda", weight = 14 },
			{ petId = "Dragon", weight = 6 },
			{ petId = "Phoenix", weight = 2 },
		},
	},
	Mythic = {
		id = "Mythic",
		name = "Mythic Egg",
		cost = 25000,
		levelRequirement = 35,
		weights = {
			{ petId = "Panda", weight = 30 },
			{ petId = "Dragon", weight = 26 },
			{ petId = "Phoenix", weight = 24 },
			{ petId = "Unicorn", weight = 15 },
			{ petId = "Voidling", weight = 5 },
		},
	},
}

local EGG_ORDER = { "Basic", "Spotted", "Mythic" }

function Pets.getDef(petId: string): PetDef?
	return DEFS[petId]
end

function Pets.listDefs(): { PetDef }
	local out: { PetDef } = {}
	for _, id in ipairs(PET_ORDER) do
		table.insert(out, DEFS[id])
	end
	return out
end

function Pets.getEgg(eggId: string): EggDef?
	return EGGS[eggId]
end

function Pets.listEggs(): { EggDef }
	local out: { EggDef } = {}
	for _, id in ipairs(EGG_ORDER) do
		table.insert(out, EGGS[id])
	end
	return out
end

function Pets.new(): Inventory
	return { pets = {}, equipped = {}, nextUid = 1, hatches = 0 }
end

function Pets.maxEquipped(vip: boolean?): number
	return Config.Pets.MaxEquipped + (vip and Config.Monetization.VipExtraPetSlots or 0)
end

-- Roll one pet from an egg. Returns nil for an unknown egg.
function Pets.roll(rng, eggId: string): PetDef?
	local egg = EGGS[eggId]
	if not egg then
		return nil
	end
	local picked = rng:pickWeighted(egg.weights)
	if not picked then
		return nil
	end
	return DEFS[picked.petId]
end

-- Open an egg, spending coins. Returns (pet, remainingCoins) or (nil, reason).
function Pets.hatch(
	inv: Inventory,
	rng,
	eggId: string,
	coins: number,
	level: number
): (PetDef?, number?, string?)
	local egg = EGGS[eggId]
	if not egg then
		return nil, nil, "UNKNOWN_EGG"
	end
	if level < egg.levelRequirement then
		return nil, nil, "LEVEL_TOO_LOW"
	end
	if coins < egg.cost then
		return nil, nil, "INSUFFICIENT_COINS"
	end
	if #inv.pets >= Config.Pets.MaxInventory then
		return nil, nil, "PET_INVENTORY_FULL"
	end

	local def = Pets.roll(rng, eggId)
	if not def then
		return nil, nil, "ROLL_FAILED"
	end

	table.insert(inv.pets, { uid = inv.nextUid, petId = def.id, level = 1 })
	inv.nextUid += 1
	inv.hatches += 1

	return def, coins - egg.cost, nil
end

function Pets.count(inv: Inventory, petId: string): number
	local total = 0
	for _, pet in ipairs(inv.pets) do
		if pet.petId == petId then
			total += 1
		end
	end
	return total
end

function Pets.find(inv: Inventory, uid: number): OwnedPet?
	for _, pet in ipairs(inv.pets) do
		if pet.uid == uid then
			return pet
		end
	end
	return nil
end

-- Equip a pet by uid. Returns (ok, reason).
function Pets.equip(inv: Inventory, uid: number, vip: boolean?): (boolean, string?)
	local pet = Pets.find(inv, uid)
	if not pet then
		return false, "NOT_OWNED"
	end
	for _, existing in ipairs(inv.equipped) do
		if existing == uid then
			return true, nil
		end
	end
	if #inv.equipped >= Pets.maxEquipped(vip) then
		return false, "NO_SLOTS"
	end
	table.insert(inv.equipped, uid)
	return true, nil
end

function Pets.unequip(inv: Inventory, uid: number): boolean
	for i, existing in ipairs(inv.equipped) do
		if existing == uid then
			table.remove(inv.equipped, i)
			return true
		end
	end
	return false
end

-- Combine multipliers from every equipped pet.
-- Returns (coinMultiplier, damageMultiplier).
function Pets.equippedMultipliers(inv: Inventory): (number, number)
	local coin, damage = 1, 1
	for _, uid in ipairs(inv.equipped) do
		local pet = Pets.find(inv, uid)
		if pet then
			local def = DEFS[pet.petId]
			if def then
				coin *= def.coinMultiplier
				damage *= def.damageMultiplier
			end
		end
	end
	return coin, damage
end

function Pets.snapshot(inv: Inventory): { pets: any, equipped: any, hatches: number }
	return {
		pets = inv.pets,
		equipped = inv.equipped,
		hatches = inv.hatches,
	}
end

-- Rebuild from persisted data, dropping unknown pets and stale equips.
function Pets.fromSnapshot(data: any): Inventory
	local inv = Pets.new()
	if type(data) ~= "table" then
		return inv
	end

	local used: { [number]: boolean } = {}
	local maxUid = 0

	-- Assign a uid that no other pet already holds. A save with a missing or
	-- duplicated uid would otherwise give two pets the same identity, and
	-- equipping one would silently equip the other.
	local function claimUid(preferred: any): number
		local uid = math.floor(tonumber(preferred) or 0)
		if uid < 1 or used[uid] then
			uid = maxUid + 1
			while used[uid] do
				uid += 1
			end
		end
		used[uid] = true
		if uid > maxUid then
			maxUid = uid
		end
		return uid
	end

	for _, pet in ipairs(data.pets or {}) do
		if type(pet) == "table" and DEFS[pet.petId] then
			table.insert(inv.pets, {
				uid = claimUid(pet.uid),
				petId = pet.petId,
				level = math.max(1, math.floor(tonumber(pet.level) or 1)),
			})
		end
	end
	inv.nextUid = math.max(math.floor(tonumber(data.nextUid) or 1), maxUid + 1)

	for _, uid in ipairs(data.equipped or {}) do
		local n = math.floor(tonumber(uid) or -1)
		if n >= 0 and Pets.find(inv, n) and #inv.equipped < Config.Pets.MaxEquipped then
			table.insert(inv.equipped, n)
		end
	end

	inv.hatches = math.max(0, math.floor(tonumber(data.hatches) or 0))
	return inv
end

return Pets

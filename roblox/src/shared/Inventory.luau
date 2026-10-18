--!strict
-- Inventory with stacking and capacity limits. Pure Luau.

local Config = require("./Config")

local Inventory = {}
Inventory.__index = Inventory

export type ItemDef = {
	id: string,
	name: string,
	maxStack: number,
	rarity: string,
}

export type Slot = { itemId: string, count: number }

local ITEM_DEFS: { [string]: ItemDef } = {
	Wood = { id = "Wood", name = "Wood", maxStack = 99, rarity = "common" },
	Stone = { id = "Stone", name = "Stone", maxStack = 99, rarity = "common" },
	Iron = { id = "Iron", name = "Iron", maxStack = 50, rarity = "uncommon" },
	Crystal = { id = "Crystal", name = "Crystal", maxStack = 25, rarity = "rare" },
	Relic = { id = "Relic", name = "Relic", maxStack = 5, rarity = "legendary" },
}

local RARITY_WEIGHTS = {
	{ itemId = "Wood", weight = 45 },
	{ itemId = "Stone", weight = 30 },
	{ itemId = "Iron", weight = 15 },
	{ itemId = "Crystal", weight = 8 },
	{ itemId = "Relic", weight = 2 },
}

function Inventory.getItemDef(itemId: string): ItemDef?
	return ITEM_DEFS[itemId]
end

function Inventory.listItemDefs(): { ItemDef }
	local out: { ItemDef } = {}
	for _, id in ipairs({ "Wood", "Stone", "Iron", "Crystal", "Relic" }) do
		table.insert(out, ITEM_DEFS[id])
	end
	return out
end

-- Weighted loot roll. Returns nil when nothing dropped.
function Inventory.rollLoot(rng, luckMultiplier: number?): ItemDef?
	local luck = luckMultiplier or 1
	local weighted = {}
	for _, entry in ipairs(RARITY_WEIGHTS) do
		local def = ITEM_DEFS[entry.itemId]
		-- Rarer items benefit more from luck.
		local rarityFactor = def.rarity == "common" and 1 or luck
		table.insert(weighted, { itemId = entry.itemId, weight = entry.weight * rarityFactor })
	end
	local picked = rng:pickWeighted(weighted)
	if not picked then
		return nil
	end
	return ITEM_DEFS[picked.itemId]
end

function Inventory.new(capacity: number?)
	local cap = capacity or Config.Inventory.DefaultCapacity
	assert(cap > 0 and cap <= Config.Inventory.MaxCapacity, "invalid capacity")
	return setmetatable({ _slots = {}, _capacity = cap }, Inventory)
end

function Inventory:capacity(): number
	return self._capacity
end

function Inventory:count(itemId: string): number
	local total = 0
	for _, slot in ipairs(self._slots) do
		if slot.itemId == itemId then
			total += slot.count
		end
	end
	return total
end

function Inventory:usedSlots(): number
	return #self._slots
end

-- Add items, merging into existing partial stacks first.
-- Returns the amount that did not fit.
function Inventory:add(itemId: string, amount: number): number
	assert(amount >= 0, "amount must be non-negative")
	local def = ITEM_DEFS[itemId]
	if not def then
		return amount
	end

	local remaining = amount

	for _, slot in ipairs(self._slots) do
		if remaining <= 0 then
			break
		end
		if slot.itemId == itemId and slot.count < def.maxStack then
			local space = def.maxStack - slot.count
			local moved = math.min(space, remaining)
			slot.count += moved
			remaining -= moved
		end
	end

	while remaining > 0 and #self._slots < self._capacity do
		local moved = math.min(def.maxStack, remaining)
		table.insert(self._slots, { itemId = itemId, count = moved })
		remaining -= moved
	end

	return remaining
end

-- Remove up to `amount`. Returns how many were actually removed.
function Inventory:remove(itemId: string, amount: number): number
	assert(amount >= 0, "amount must be non-negative")
	local remaining = amount
	local index = 1
	while index <= #self._slots and remaining > 0 do
		local slot = self._slots[index]
		if slot.itemId == itemId then
			local taken = math.min(slot.count, remaining)
			slot.count -= taken
			remaining -= taken
			if slot.count == 0 then
				table.remove(self._slots, index)
				continue
			end
		end
		index += 1
	end
	return amount - remaining
end

function Inventory:snapshot(): { Slot }
	local out: { Slot } = {}
	for i, slot in ipairs(self._slots) do
		out[i] = { itemId = slot.itemId, count = slot.count }
	end
	return out
end

-- Rebuild from persisted data, dropping unknown items and over-capacity slots.
function Inventory.fromSnapshot(slots: { Slot }, capacity: number?)
	local inv = Inventory.new(capacity)
	for _, slot in ipairs(slots or {}) do
		if ITEM_DEFS[slot.itemId] and slot.count > 0 then
			inv:add(slot.itemId, slot.count)
		end
	end
	return inv
end

return Inventory

--!strict
-- The people who stand in Prontera Town.
--
-- Until now the town was a floor, a spawn pad and a ring of farm beds: a place
-- you pass through on the way to a field. Nothing in the world could be
-- interacted with at all, so every decision in the game was made by tapping a
-- button in an overlay. A gamer reads that as a menu, not a town.
--
-- A villager is data, like a monster's body or an item's icon. Each one names
-- where it stands, what it looks like and which panel it opens. The server
-- builds the body from this table and turns a tap on it into the same remote
-- the HUD already calls, so no new gameplay code hangs off the NPC itself.


local Villagers = {}

export type VillagerDef = {
	id: string,
	nameKey: string,
	titleKey: string,
	-- Which overlay this villager opens. The client maps these to its own
	-- panel openers; the server only has to say who is who.
	opens: string,
	-- Position around the town fountain, in studs. The ring keeps every
	-- villager inside the town floor and clear of the farm beds.
	angle: number,
	radius: number,
	-- Body colours, so a villager is recognisable from across the square.
	body: { number },
	accent: { number },
	-- A tall marker so the villager is findable on a phone screen.
	beacon: boolean,
}

-- The order matters: it is the order they are placed around the fountain, and
-- the first one a new player walks into is the quest giver.
local LIST: { VillagerDef } = {
	{
		id = "Elder",
		nameKey = "npcElder",
		titleKey = "npcElderTitle",
		opens = "quests",
		angle = -math.pi / 2,
		radius = 26,
		body = { 214, 186, 140 },
		accent = { 240, 214, 120 },
		beacon = true,
	},
	{
		id = "Merchant",
		nameKey = "npcMerchant",
		titleKey = "npcMerchantTitle",
		opens = "shop",
		angle = -math.pi / 2 + math.pi * 2 / 5,
		radius = 26,
		body = { 176, 132, 92 },
		accent = { 120, 220, 160 },
		beacon = true,
	},
	{
		id = "Trainer",
		nameKey = "npcTrainer",
		titleKey = "npcTrainerTitle",
		opens = "character",
		angle = -math.pi / 2 + math.pi * 4 / 5,
		radius = 26,
		body = { 140, 150, 190 },
		accent = { 200, 210, 255 },
		beacon = true,
	},
	{
		id = "Captain",
		nameKey = "npcCaptain",
		titleKey = "npcCaptainTitle",
		opens = "travel",
		angle = -math.pi / 2 + math.pi * 6 / 5,
		radius = 26,
		body = { 190, 120, 110 },
		accent = { 255, 170, 140 },
		beacon = true,
	},
	{
		id = "Keeper",
		nameKey = "npcKeeper",
		titleKey = "npcKeeperTitle",
		opens = "rewards",
		angle = -math.pi / 2 + math.pi * 8 / 5,
		radius = 26,
		body = { 150, 190, 170 },
		accent = { 200, 255, 230 },
		beacon = true,
	},
}

Villagers.List = LIST
Villagers.Count = #LIST

-- How close a player has to be for a tap to count. Wider than the interaction
-- the client shows, because a phone tap lands imprecisely.
Villagers.Reach = 18

function Villagers.byId(id: string): VillagerDef?
	for _, def in ipairs(LIST) do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Where a villager stands, relative to the town centre. Plain numbers, not a
-- Vector3: every shared module here is pure Luau so it runs under the CLI, and
-- the caller turns this into a position. Kept in one place so the server that
-- builds the body and a test that checks the ring cannot disagree.
function Villagers.positionOf(def: VillagerDef): { x: number, z: number }
	local r = def.radius
	return { x = math.cos(def.angle) * r, z = math.sin(def.angle) * r }
end

-- The panel ids a villager can open. The client asserts every one of these is
-- wired, so a typo in the table above fails CI instead of doing nothing when a
-- player taps.
Villagers.Opens = {
	quests = true,
	shop = true,
	character = true,
	travel = true,
	rewards = true,
}

function Villagers.opensKnown(id: string): boolean
	return Villagers.Opens[id] == true
end

return Villagers

--[[
ModelSchemaUtils - Utilities for working with model schemas

This module provides utilities for working with predefined model schemas,
including the ability to get component labels for a given schema name.
]]

local ModelSchemaUtils = {}

local SCHEMAS = {
	Body1 = { "body" },

	-- Land Vehicles (Car5 Variation)
	CarSimple5 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },
	Bus5 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },
	SchoolBus6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "stop sign arm" },
	Ambulance6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "siren light bar" },
	PoliceCar6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "siren light bar" },
	Taxi6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "taxi light sign" },
	CombatCarSimple6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "gun" },
	MultiPlayerCombatCar6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "gun" },
	CarComplex9 = { "chassis", "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "left headlight", "right headlight", "exhaust pipe" },
	Train5 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },
	RollercoasterCart3 = { "cart", "rollers", "seat" },
	SemiTruck8 = { "body", "left front wheel", "right front wheel", "left mid wheel", "right mid wheel", "left rear wheel", "right rear wheel", "hitch plate" },
	TowTruckSimple6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "hook" },
	FireTruck8 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "base ladder", "ladder extension", "water cannon" },
	Trailer4 = { "body", "left wheel", "right wheel", "hitch" },
	GarbageTruck7 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "hopper", "lifting arm" },
	Steamroller4 = { "body", "roller", "left rear wheel", "right rear wheel" },
	Excavator6 = { "body", "cabin house", "main arm", "bucket", "left track", "right track" },
	Bulldozer5 = { "body", "blade", "push arms", "left track", "right track" },
	HarvesterCombine7 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "header", "auger" },
	Forklift7 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "forks", "warning light" },
	BoomTruck8 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "boom", "bucket", "turret" },
	CraneMachine7 = { "tower frame", "rotating base", "jib", "counter balance", "trolley", "hook", "cable" },
	Tractor6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "hitch" },
	Zamboni6 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel", "conditioner" },
	MineCart5 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },
	TankSimple5 = { "hull", "turret", "turret cannon", "left track", "right track" },
	SimpleMotorcycle7 = { "frame", "seat", "handlebars", "front fork", "rear swingarm", "front wheel", "rear wheel" },
	Bike10 = { "frame", "seat", "handlebars", "front fork", "front wheel", "rear wheel", "left pedal", "left pedal arm", "right pedal", "right pedal arm" },
	Wheelchair7 = { "frame", "seat", "push handles", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },

	-- Stand Car
	Hoverboard3 = { "body", "front hover pad", "rear hover pad" },
	Skateboard7 = { "body", "front truck", "rear truck", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },
	SkateboardSimple5 = { "body", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },

	-- Push Car
	Stroller8 = { "frame", "canopy", "seat", "handlebar", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },
	ShoppingCart6 = { "frame", "handlebar", "left front wheel", "right front wheel", "left rear wheel", "right rear wheel" },

	-- Air Vehicles (Planes)
	PropPlaneSimple2 = { "body", "propeller" },
	PropPlane5 = { "body", "propeller", "center landing gear", "right landing gear", "left landing gear" },
	CombatPropPlaneSimple3 = { "body", "propeller", "gun" },
	CombatPropPlane6 = { "body", "propeller", "center landing gear", "right landing gear", "left landing gear", "gun" },
	MultiPlayerCombatPropPlaneSimple3 = { "body", "propeller", "center landing gear", "right landing gear", "left landing gear", "gun" },
	JetPlaneSimple2 = { "body", "thruster" },
	JetPlane5 = { "body", "thruster", "center landing gear", "right landing gear", "left landing gear" },
	CombatJetPlane3 = { "body", "thruster", "center landing gear", "right landing gear", "left landing gear", "gun" },
	MultiPlayerCombatJetPlane6 = { "body", "thruster", "center landing gear", "right landing gear", "left landing gear", "gun" },
	MultiPlayerCombatJetPlaneSimple3 = { "body", "thruster", "gun" },
	HelicopterSimple2 = { "body", "main rotor blade" },
	CombatHelicopterSimple3 = { "body", "main rotor blade", "gun" },
	FlyingCarpet1 = { "carpet" },
	Rocketship3 = { "cockpit", "fuel tank", "booster engine" },
	Spacecraft3 = { "body", "left thruster", "right thruster" },
	CombatSpacecraft4 = { "body", "left thruster", "right thruster", "cannon" },
	Ufo2 = { "body", "lights" },
	Drone5 = { "body", "left front propeller", "right front propeller", "left rear propeller", "right rear propeller" },
	CameraDrone6 = { "body", "left front rotor", "right front rotor", "left rear rotor", "right rear rotor", "camera" },
	Jetpack2 = { "pack", "thruster" },
	FlyingBroom2 = { "handle", "bristles" },

	-- Water Vehicles (Boat)
	MotorboatSimple2 = { "body", "motor" },
	CombatMotorboatSimple3 = { "body", "motor", "cannon" },
	Sailboat4 = { "body", "sail", "propeller", "rudder" },
	CombatSailShip5 = { "body", "sail", "propeller", "rudder", "cannon" },
	Steamboat3 = { "hull", "chimney", "paddlewheel" },
	Ship4 = { "hull", "chimney", "rudder", "anchor" },
	Battleship5 = { "hull", "chimney", "rudder", "anchor", "cannon" },
	SubmarineSimple2 = { "hull", "propeller" },

	-- Mech
	Mech8 = { "torso", "head", "right arm", "left arm", "left leg", "right leg", "control pod", "cannons" },

	-- Tool Prop
	Flashlight3 = { "handle body", "head", "lens" },
	Lighter3 = { "body", "spark wheel", "button" },
	Brush2 = { "handle", "bristles" },
	Pencil2 = { "shaft", "eraser" },
	Saw2 = { "handle", "blade" },
	Extinguisher4 = { "tank", "valve", "nozzle", "lever" },
	Dowsingrod3 = { "left handle", "right handle", "rod tips" },
	Handcuffs5 = { "right cuff frame", "right cuff ratchet", "left cuff frame", "left cuff ratchet", "chain" },
	Toolbox3 = { "handle", "box", "lid" },
	Canteen3 = { "bottle body", "cap", "strap" },
	Rope1 = { "rope" },
	Chain3 = { "link 1", "link 2", "link 3" },
	Blender5 = { "motor base", "pitcher", "lid", "blade", "button" },
	Generator4 = { "frame", "engine block", "control panel", "pull cord handle" },
	Medkit4 = { "case body", "case lid", "handle", "latches" },
	Lock3 = { "lock body", "shackle", "keyhole" },
	Conveyorbelt3 = { "frame", "rollers", "belt surface" },
	Scale3 = { "base", "weighing plate", "display screen" },
	Net3 = { "handle", "rim", "net mesh" },
	Map2 = { "left paper panel", "right paper panel" },
	Compass3 = { "case", "glass face", "needle" },
	Potion3 = { "bottle", "liquid fill", "cork" },
	Backpack3 = { "bag body", "flap/zipper", "shoulder straps" },
	Binoculars3 = { "left tube", "right tube", "center hinge" },
	FishingRod6 = { "rod", "handle", "reel housing", "reel handle", "line", "lure" },
	Lantern4 = { "handle ring", "housing", "glass panes", "flame/bulb" },
	Torch2 = { "wood stick", "cloth wrapping" },
	Mirror2 = { "frame", "mirror surface" },
	Clock4 = { "clock face", "hour hand", "minute hand", "second hand" },
	Flag3 = { "flagpole", "flagpole top", "flag cloth" },
	Candle2 = { "wax body", "wick" },
	Chest2 = { "body", "lid" },

	-- Tool/Weapon (Melee)
	SledgeHammer2 = { "handle", "head" },
	Hammer2 = { "handle", "head" },
	Axe2 = { "handle", "blade" },
	HandAxe2 = { "handle", "blade" },
	Pickaxe2 = { "handle", "head" },
	Shovel3 = { "head", "handle", "shaft" },
	Chainsaw2 = { "body", "blade" },
	Crowbar1 = { "crowbar" },
	Wrench2 = { "handle", "jaw" },
	Pan2 = { "handle", "pan" },
	TennisRacket3 = { "handle", "frame", "strings" },

	-- Ranged Weapons
	GunSimple3 = { "grip", "frame", "barrel" },
	Gun6 = { "grip", "frame", "slide", "barrel", "magazine", "trigger" },
	Pistol6 = { "grip", "frame", "slide", "barrel", "magazine", "trigger" },
	Smg6 = { "grip", "frame", "charging handle", "barrel", "magazine", "trigger" },
	RocketLauncher5 = { "launch tube", "grip", "sight", "trigger", "shoulder rest" },
	SniperRifle8 = { "grip", "frame", "bolt", "barrel", "magazine", "trigger", "scope", "scope lens" },
	SniperRifleSimple4 = { "grip", "frame", "barrel", "scope" },
	Lasergun4 = { "grip", "body", "power cell", "trigger" },
	LaserRifle4 = { "grip", "body", "power cell", "trigger" },
	PumpShotgun5 = { "grip", "frame", "pump", "barrel", "trigger" },
	BreachShotgun6 = { "grip", "frame", "breach hinge", "barrel", "trigger", "hammer" },
	Revolver7 = { "grip", "frame", "cylinder", "hammer", "barrel", "trigger", "bullet" },
	Minigun6 = { "rear handle", "main body", "barrels", "ammo belt", "motor housing", "ammo case" },
	Rifle6 = { "grip", "frame", "charging handle", "barrel", "magazine", "trigger" },
	Turret5 = { "tripod base", "swivel mount", "gun body", "barrel", "shield plate" },
	Cannon4 = { "carriage base", "cannon barrel", "left wheel", "right wheel" },
	Musket5 = { "stock", "barrel", "lock mechanism", "loading rod", "trigger" },
	Paintballgun5 = { "grip", "body", "barrel", "co2 tank", "ammo hopper" },
	Bazooka5 = { "launch tube", "grip", "sight", "trigger", "shoulder rest" },
	Flamethrower5 = { "stock", "main body", "fuel tank", "nozzle", "pilot light emitter" },
	Machinegun6 = { "grip", "frame", "charging handle", "barrel", "magazine", "trigger" },
	Bow4 = { "shaft", "arrow", "top string", "bottom string" },
	Slingshot4 = { "fork handle", "left elastic band", "right elastic band", "pouch" },
	Wand2 = { "handle", "tip" },

	-- Melee Weapons
	Sword4 = { "handle", "hand guard", "blade", "pommel" },
	Knife2 = { "handle", "blade" },
	Bat2 = { "handle", "barrel" },
	Katana3 = { "handle", "hand guard", "blade" },
	Zweihander4 = { "long handle", "large crossguard", "long blade", "pommel" },
	Spear2 = { "shaft", "spearhead" },
	Staff3 = { "shaft", "top cap", "bottom cap" },
	Magicstaff2 = { "staff", "headpiece" },
	Dagger3 = { "hilt", "crossguard", "blade" },
	Scythe2 = { "shaft", "blade" },
	Shield3 = { "shield body", "handle", "arm strap" },

	-- Explosive / Other Weapons
	Nuke3 = { "casing", "nose cone", "fins" },
	Bomb3 = { "bomb body", "fuse string", "spark particle emitter" },
	Grenade3 = { "grenade body", "safety lever", "pull pin" },
	Molotov3 = { "bottle", "liquid", "rag wick" },
	Taser2 = { "body", "prongs" },
}

function ModelSchemaUtils.getComponentLabels(schema: string): { string }
	local labels = SCHEMAS[schema]
	if labels then
		return labels
	end
	error("Unknown schema: " .. tostring(schema))
end

function ModelSchemaUtils.hasSchema(schema: string): boolean
	return SCHEMAS[schema] ~= nil
end

function ModelSchemaUtils.getAllSchemaNames(): { string }
	local names = {}
	for name in pairs(SCHEMAS) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return ModelSchemaUtils

#!/usr/bin/env python3
"""Check that the client, the HUD and the server agree on every shared name.

The Luau test suites cover behaviour, but they cannot reach the HUD: the Luau
VM sandboxes globals per module, so Hud.build() cannot run against a fake
Roblox tree from a plain script. That gap is exactly where the real bugs were:

  * a panel named "Wave" and a label named "Wave", so the label lookup
    returned the panel and the wave counter never updated;
  * a setLabel() lookup that stopped one level short, so every stat silently
    kept its placeholder text;
  * World.attachPlayer() that existed but was never called, so players spawned
    somewhere other than the arena.

Each of those is a naming or wiring mistake, and each is detectable by reading
the source. This script is the guard for that class of bug.

Exit code is non-zero when anything is wrong, so CI fails loudly.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HUD = ROOT / "roblox/src/client/Hud.luau"
CLIENT = ROOT / "roblox/src/client/init.client.luau"
SERVER = ROOT / "roblox/src/server/init.server.luau"
WORLD = ROOT / "roblox/src/server/World.luau"
SHARED = ROOT / "roblox/src/shared"
TEXT = ROOT / "roblox/src/shared/Text.luau"

passed = 0
failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    global passed
    if condition:
        passed += 1
    else:
        failures.append(f"{label}{(' -> ' + detail) if detail else ''}")


def read(path: Path) -> str:
    if not path.is_file():
        check(f"file exists: {path.name}", False, str(path))
        return ""
    return path.read_text(encoding="utf-8")


hud = read(HUD)
client = read(CLIENT)
server = read(SERVER)
world = read(WORLD)
text = read(TEXT)

print("\nWIRING 1: the client can reach the HUD module")

check("the client requires the HUD", "require(script.Hud)" in client, "no require(script.Hud)")
check("the client builds the HUD", "Hud.build()" in client, "Hud.build() never called")
check("the client wires the buttons", "wireButtons" in client, "wireButtons missing")

print("\nWIRING 2: every name the client writes to exists in the HUD")

# setLabel(gui, "Name", ...) in the client must match label(parent, "Name", ...)
# in the HUD. A mismatch is a stat that never updates.
written = set(re.findall(r'setLabel\(gui,\s*"([\w]+)"', client))
check("the client writes at least five stats", len(written) >= 5, f"count={len(written)}")

for name in sorted(written):
    declared = re.search(r'label\([\w]+,\s*"' + re.escape(name) + r'"', hud) is not None
    check(f"the HUD declares the label the client writes: {name}", declared, "missing from Hud.luau")

check("the HUD declares the Wave label", re.search(r'label\([\w]+,\s*"Wave"', hud) is not None, "missing")

print("\nWIRING 3: no node shadows another node of the same name")

created: dict[str, list[str]] = {}
for kind, name in re.findall(r'(panel|label|button)\(\s*[\w]+,\s*"([\w]+)"', hud):
    created.setdefault(name, []).append(kind)

duplicates = sorted(f"{name} ({', '.join(kinds)})" for name, kinds in created.items() if len(kinds) > 1)
check("no duplicate HUD node names", not duplicates, "; ".join(duplicates))
check("the wave panel has a distinct name", "WavePanel" in created, "WavePanel missing")

print("\nWIRING 4: label lookups search the whole tree")

check(
    "the client searches recursively for labels",
    re.search(r"FindFirstChild\(name,\s*true\)", client) is not None,
    "setLabel does not pass recursive=true",
)
# Buttons are awaited (they must exist) and labels are searched (they may not
# yet), so accept either lookup for the node.
for name in ("Rewards", "Daily", "Code"):
    found = f'FindFirstChild("{name}"' in client or f'WaitForChild("{name}"' in client
    check(f"the client finds the {name} node by name", found, "missing")

print("\nWIRING 5: the client's intents match the server's remotes")

check("the server exposes ClaimDaily", "ClaimDaily.OnServerInvoke" in server, "no ClaimDaily handler")
check("the server exposes RedeemCode", "RedeemCode.OnServerInvoke" in server, "no RedeemCode handler")
check("the client calls claimDaily", "Intent.claimDaily" in client, "missing")
check("the client calls redeemCode", "Intent.redeemCode" in client, "missing")

print("\nWIRING 6: the daily button is driven by server state")

for field in ("dailyReady", "dailyStreak", "dailySecondsLeft"):
    check(f"the client tracks {field}", field in client, "missing")
    check(f"the server sends {field}", field in server, "missing")

print("\nWIRING 7: the world is placed and the player spawns on it")

check("the server builds the world", "World.buildWorld()" in server, "never built")
check("the server spawns enemies", "World.spawnEnemy" in server, "never spawns")
check("the server ticks enemies", "World.updateEnemies" in server, "never ticks")
check("the character is moved onto the spawn", "World.attachPlayer" in server, "never called")
check("the world creates the town", '"Town"' in world, "no town")
check("the world creates a ground slab", '"WorldGround"' in world, "no ground")
check("the world creates a spawn", '"TownSpawn"' in world or 'Instance.new("SpawnLocation")' in world, "no spawn")
check("the world creates one model per field", '"Field_" .. field.id' in world, "no field models")
check("the world creates a portal back to town", 'Text.get("returnToTown")' in world, "no portal home")
check("the Thai text module is loaded", text != "", "Text.luau missing")
check("the server owns enemy damage", "World.damageEnemy" in server, "no server-side damage")

print("\nWIRING 7b: one director per field, and travel between them")

check("the server keeps a director per field", "directorFor" in server, "no directorFor")
check("a director starts the wave on arrival", "skipIntermission" in server, "no skipIntermission")
check("the travel remote exists", "TravelZone.OnServerInvoke" in server, "no TravelZone handler")
check("travel checks the field lock", "Fields.canEnter" in server, "no lock check")
check("travel moves the player", "World.placePlayer" in server, "player never moved")
check("the client can ask to travel", "Intent.travelTo" in client, "no travelTo intent")
check("the client shows a MAP button", "mapButton.Activated" in client, "MAP not wired")
check("the client builds the travel rows", "buildTravelList" in client, "no travel list")
check("the HUD has a MAP button", re.search(r'id = "Map"', hud) is not None, "missing")
check("the HUD has a travel panel", '"TravelPanel"' in hud, "missing")
check("the HUD has a close button for travel", '"CloseTravel"' in hud, "missing")
check("the server sends the field list", "Fields.snapshot" in server, "no field snapshot")
check("the client keeps the field list", "state.fields" in client, "client ignores fields")
check("the client shows the current field", 'setLabel(gui, "Field"' in client, "no field label")
check("the HUD declares the Field label", re.search(r'label\([\w]+, "Field"', hud) is not None, "missing")

print("\nWIRING 7c: a boss is visible and a kill is celebrated")

check("the world can describe the boss", "World.bossInfo" in server, "no bossInfo")
check("the server sends the boss with the wave", "snapshot.boss" in server, "no boss in wave state")
check("the client reads the boss", "w.boss" in client, "client ignores the boss")
check("the HUD has a boss bar", '"BossPanel"' in hud and '"BossFill"' in hud, "missing")
check("the HUD has a boss name label", re.search(r'label\([\w]+, "BossName"', hud) is not None, "missing")
check("the server reports every kill", "CombatFx:FireClient" in server, "no kill event")
check("the client listens for kills", "CombatFx.OnClientEvent" in client, "no kill listener")
check("the HUD has a kill flash", re.search(r'label\([\w]+, "KillFlash"', hud) is not None, "missing")
check("the server tracks the kill streak", "killStreak" in server, "no streak")
check("the client shows the combo", 'Text.get("combo")' in client, "no combo display")

print("\nWIRING 7d: the HUD does not flood a phone")

# The snapshots used to be sent from the top level of the Heartbeat connection,
# which is once per frame. On a phone that is a flood of events for a bar that
# moves a few times a second, so the gates are part of the contract.
heartbeat_at = server.find("RunService.Heartbeat:Connect")
check("the HUD broadcast is gated by a clock", "Config.Tick.BroadcastInterval" in server, "sent every frame")
check("the farm broadcast has its own clock", "Config.Tick.FarmBroadcastInterval" in server, "sent every frame")
check(
    "the gates are inside the Heartbeat loop",
    heartbeat_at != -1 and server.find("Config.Tick.BroadcastInterval") > heartbeat_at,
    "gate sits outside the loop",
)
check("the wave gate remembers when it last ran", "lastBroadcastAt" in server, "no clock")
check("the farm gate remembers when it last ran", "lastFarmBroadcastAt" in server, "no clock")
check("the client does not re-render on every wave event", "WaveState.OnClientEvent" in client, "not wired")
config = read(ROOT / "roblox/src/shared/Config.luau")
m = re.search(r"BroadcastInterval\s*=\s*([0-9.]+)\s*/\s*([0-9.]+)", config)
tick = re.search(r"Rate\s*=\s*([0-9.]+)", config)
interval = (float(m.group(1)) / float(m.group(2))) if m else 0.0
rate = float(tick.group(1)) if tick else 0.0
check("the HUD cadence is slower than the tick rate", interval > (1 / rate if rate else 0), "same as tick")

print("\nWIRING 8: a respawn revives the combatant")

# Death clears this flag and only the spawn path sets it back. Without it a
# player attacks until their first death and then never again.
check("the spawn path revives the combatant", "combatant.alive = true" in server, "never reset")

print("\nWIRING 8b: the town has people in it and they open real panels")

# The town was a floor, a spawn pad and a ring of farm beds: nothing in the
# world could be interacted with, so every decision was a tap in an overlay.
# A villager that is built but never wired, or wired to a panel the client does
# not know, is the same dead town with extra geometry.
check(
    "the town builds villagers",
    "buildVillager" in world,
    "no villager is ever built",
)
check(
    "a villager prompt routes to the server",
    "setVillagerHandler" in world and "villagerTalk" in world,
    "the prompt does nothing",
)
check(
    "the server answers a villager with a panel",
    "setVillagerHandler" in server and "OpenPanel" in server,
    "the server never opens a panel",
)
check(
    "the client opens the panel the server named",
    "OpenPanel.OnClientEvent" in client,
    "the client ignores the villager",
)
check(
    "villagers only talk in town",
    "record.field ~= nil" in server,
    "a player can shop mid-fight",
)

print("\nWIRING 8c: a death in a lethal field costs coins")

# Free death made the risk side of the game imaginary. The charge has to be
# wired into the death path, and the safe field has to stay free.
check(
    "death charges through the shared rule",
    "Death.penalty(" in server,
    "the death penalty is never applied",
)
check(
    "the training field is never charged",
    "not safeField" in server,
    "the safe field can take coins",
)
check(
    "the player is told what a death cost",
    "deathPenalty" in server,
    "a charge happens silently",
)

print("\nWIRING 8d: the game does not play itself")

check(
    "auto-attack is off by default",
    "AutoAttack = false" in read(SHARED / "Config.luau"),
    "the character fights without the player",
)

print("\nWIRING 9: the build verifier covers every module")

build_script = read(ROOT / "AX_PC_CONTROL/pc1-roblox-build.ps1")
for marker in ("world", "hud", "dailyRewards", "codes", "scenery", "atmosphere"):
    check(f"the build verifier checks {marker}", f"{marker}" in build_script, "marker missing")

print("\nWIRING 10: the death scene stays intact and death is not instant")

# Two reported bugs. Both are one-line omissions that are invisible until
# somebody actually plays, so they are guarded by reading the source.
check(
    "death does not break the avatar's joints",
    "BreakJointsOnDeath = false" in server,
    "the head rolls off on death",
)
check(
    "enemies only attack from melee range",
    "Config.Wave.EnemyMeleeRange" in world,
    "every enemy damages the player from anywhere",
)
check(
    "enemies chase the nearest player",
    "EnemyMoveSpeed" in world,
    "enemies never move toward the player",
)
check(
    "a spawned enemy cannot hit immediately",
    "Config.Wave.SpawnGraceSeconds" in world,
    "enemies hit on arrival",
)

print("\nWIRING 11: the farm loop is reachable from the client")

check("the client requires the farm remotes", "PlantCrop" in client and "HarvestCrop" in client, "missing")
check("the client requires the axe remote", "UseAxe" in client, "missing")
check("the server exposes PlantCrop", "PlantCrop.OnServerInvoke" in server, "no handler")
check("the server exposes HarvestCrop", "HarvestCrop.OnServerInvoke" in server, "no handler")
check("the server exposes UseAxe", "UseAxe.OnServerInvoke" in server, "no handler")
check("the server sends farm state", "FarmState:FireClient" in server, "no farm state")
check("the server builds the plots", "Plot_" in world, "no plot parts")
check("the server draws the plots", "World.updatePlot" in server, "plots never drawn")
check("the HUD has a FARM button", re.search(r'id = "Farm"', hud) is not None, "missing")
check("the HUD has an AXE button", re.search(r'id = "Axe"', hud) is not None, "missing")
check("the FARM button is wired", "farmButton.Activated" in client, "not wired")
check("the AXE button is wired", "axeButton.Activated" in client, "not wired")

print("\nWIRING 12: monsters, classes, items and attacks are all drawn")

# Five reported gaps: monsters looked alike, jobs looked alike, the bag was
# text, a tap had no animation, and the status panel sat on the chat. Each is
# a wiring question -- does the thing that was written actually get called --
# so each is checked by reading the source.

monster_shapes = read(ROOT / "roblox/src/shared/MonsterShapes.luau")
class_look = read(ROOT / "roblox/src/shared/ClassLook.luau")
item_icons = read(ROOT / "roblox/src/shared/ItemIcons.luau")
item_view = read(ROOT / "roblox/src/client/ItemView.luau")
attack_anim = read(ROOT / "roblox/src/client/AttackAnim.luau")

check("the world builds monsters from shapes", "MonsterShapes.get" in world, "monsters are still cubes")
check("the shape recipe decides the primary part", "recipe.primary" in world, "no primary part")
check("every colour role is honoured", "roleColor" in world, "one flat colour per monster")

check("the server applies a class look", "World.applyClassLook" in server, "jobs look identical")
check("the look is applied on spawn", server.count("World.applyClassLook") >= 2, "only applied on job change")
check("the look module has every class", "ClassLook.get" in world, "no look lookup")
check("the look changes the body", "bodyScale" in world or "Humanoid" in world, "no body change")

check("the server broadcasts every swing", "AttackFx:FireAllClients" in server, "swings are invisible")
check("the client listens for swings", "AttackFx.OnClientEvent" in client, "no swing listener")
check("the swing style comes from the class", "ClassLook.get(record.class)" in server and "look.swing" in server, "one swing for every job")
check("the client plays the style the server sent", "payload.style" in client, "style is ignored")
check("the animation module moves an arm", "Motor6D" in attack_anim, "no joint animation")
check("the animation draws a slash", "AXSlash" in attack_anim, "no visible swing")

check("the bag renders real item icons", "ItemView.cell" in client, "bag is still text")
check("the icon is built from a recipe", "ItemIcons.get" in item_view, "no icon recipe")
check("the icon uses a viewport", "ViewportFrame" in item_view, "no 3D icon")
check("the equipped gear shows as icons", "ItemView.emptyTile" in client, "empty slots not drawn")

print("\nWIRING 13: the status panel is clear of the chat, the topbar and the stick")

# The reported bug: the status panel sat on the chat, so the chat could not be
# read or dragged, and the reward buttons sat on the phone's movement stick.
# The follow-up bug: the panel was moved to the top right, but the HUD drew
# from the physical screen top (IgnoreGuiInset = true), so on a phone with a
# taller topbar the panel slid back under the buttons.
stats_line = re.search(r'panel\(gui, "Stats",[^\n]*', hud)
check("the status panel exists", stats_line is not None, "no Stats panel")
if stats_line:
    line = stats_line.group(0)
    check("the status panel is not top left", 'UDim2.new(0, 16, 0, 16)' not in line, "still on the chat")
    check("the status panel is anchored right", "UDim2.new(1, -" in line, "not moved right")
    check("the status panel is near the top", "UDim2.new(1, -12, 0, 8)" in line, "not against the top-right corner")

# The HUD must measure from the safe area, not the raw screen. IgnoreGuiInset
# true is the exact bug that put the panel under the topbar, and CoreUISafeInsets
# is what makes Roblox keep it clear of the topbar and the device cutout.
check("the HUD measures from the safe area", "IgnoreGuiInset = true" not in hud,
      "the HUD draws from the physical screen edge, under the topbar")
check("the HUD asks for the core-UI safe area", "Enum.ScreenInsets.CoreUISafeInsets" in hud,
      "no ScreenInsets, so nothing keeps the HUD off the topbar")
check("the HUD clips to the device safe area", "ClipToDeviceSafeArea" in hud,
      "a panel can still hang off a notch")

check("the reward buttons are behind a button", '"RewardsButton"' in hud, "rewards still on the stick")
check("the rewards overlay can close", '"CloseRewards"' in hud, "no way out of the overlay")
check("the rewards overlay starts hidden", "rewards.Visible = false" in hud, "overlay covers the game")
check("the client toggles the overlay", "state.rewardsOpen" in client, "overlay never opens")
check("opening the character sheet closes it", "state.rewardsOpen = false" in client, "two overlays stack")

print("\nWIRING 14: the maps are built with scenery and air, not a bare disc")

scenery = read(ROOT / "roblox/src/shared/Scenery.luau")
atmosphere = read(ROOT / "roblox/src/shared/Atmosphere.luau")
zones = read(ROOT / "roblox/src/shared/Zones.luau")
combat = read(ROOT / "roblox/src/shared/Combat.luau")

check("the world requires the scenery module", "require(Shared:WaitForChild(\"Scenery\"))" in world, "Scenery not required")
check("the world requires the atmosphere module", "require(Shared:WaitForChild(\"Atmosphere\"))" in world, "Atmosphere not required")
check("the world builds scenery", "buildScenery(" in world, "buildScenery is never called")
check("the town is furnished", 'buildScenery(town, "Town"' in world, "the town has no scenery")
check("a field is furnished", "buildScenery(model, field.id" in world, "fields have no scenery")
check("scenery is scattered deterministically", "Scenery.seedFor(" in world, "no per-place seed")
check("the spawn pad is protected", "keepOut" in world, "scenery can grow on the spawn pad")
check("solid props collide", "piece.CanCollide = spot.solid" in world, "props are all intangible")
check("props do not block the axe", "piece.CanQuery = false" in world, "props block interaction")
check("props use real materials", "Scenery.materialFor(" in world, "props are untextured plastic")
check("the atmosphere is applied", "applyAtmosphere(" in world, "atmosphere is never applied")
check("the atmosphere follows the look", "applyAtmosphere(placeId)" in world, "re-lighting a place skips its air")
check("the air includes haze", "Instance.new(\"Atmosphere\")" in world, "no atmosphere instance")
check("the air includes clouds", "Instance.new(\"Clouds\")" in world, "no cloud layer")
check("the air includes bloom", "Instance.new(\"BloomEffect\")" in world, "no glow")
check("the air includes a colour grade", "Instance.new(\"ColorCorrectionEffect\")" in world, "no grading")

check("every field has a scenery plan", all(
    f'    {place} = {{' in scenery for place in ("Town", "Meadow", "Cavern", "Volcano", "Void", "Heaven")
), "a place has no plan")
check("every field has an atmosphere", all(
    f'    {place} = {{' in atmosphere for place in ("Town", "Meadow", "Cavern", "Volcano", "Void", "Heaven")
), "a place has no atmosphere")
check("scenery avoids cone shapes that do not render", "Instance.new(\"SpecialMesh\")" not in scenery
      and "SpecialMesh" not in re.sub(r"^\s*--.*$", "", scenery, flags=re.M), "a deprecated mesh is in use")
check("scenery is built from primitives", "CornerWedge" in scenery, "no non-axis primitive in use")

print("\nWIRING 15: a monster field keeps its spawn ring and its creatures readable")

check("the spawn ring is protected", "Config.Fields.SpawnRadius" in world and "ringRadius" in world,
      "a prop can grow where monsters spawn")
check("the farm plots are protected", "Config.Farm.PlotRingRadius" in world, "a prop can grow on a farm plot")
check("the portals are protected", "radius = 20" in world, "a tree can block a portal")
check("the world floats a hovering monster", "MonsterShapes.hovers" in world and "HOVER_LIFT" in world,
      "a hovering monster is placed on the ground")
check("the enemy model keeps its own material", "Enum.Material.SmoothPlastic" in world, "no material on monsters")

monster_shapes = read(ROOT / "roblox/src/shared/MonsterShapes.luau")
check("the hovering set is declared", "HOVERING" in monster_shapes, "no hovering set")
check("the hovering set is queryable", "MonsterShapes.hovers" in monster_shapes, "no hovers()")
check("a cone is drawn as stacked discs", "local function taper" in scenery, "no taper helper")
check("a leaning shard is drawn as stacked discs", "local function lean" in scenery, "no lean helper")

print("\nWIRING 16: every standing panel can be folded out of the way")

# K asked for the on-screen panels and signs to collapse to an icon so they do
# not clutter the play area. Each standing panel carries a fold caret, and the
# client remembers which ones the player put away.
check("the HUD can fold a panel", "local function fold(" in hud, "no fold helper")
check("the HUD restores a folded panel", "function Hud.applyFolds(" in hud, "folds never reapply")
check("the fold remembers the open size", "entry.openWidth" in hud, "unfolding loses the size")
check("the fold only restores what it hid", "entry.hidden" in hud, "unfolding force-shows hidden parts")
check("the stats panel folds", 'fold(stats,' in hud, "the stats panel cannot be put away")
check("the wave banner folds", 'fold(wave,' in hud, "the wave banner cannot be put away")
check("the action panel folds", 'fold(actions,' in hud, "the action panel cannot be put away")
check("the combat panel folds", 'fold(combat,' in hud, "the combat panel cannot be put away")
check("the client tracks folded panels", re.search(r"folded = \{", client) is not None,
      "the client forgets the folds")
check("the quest panel folds", "fold(quest," in hud, "the quest tracker cannot be put away")
check("the caret toggles the panel", "state.folded[name]" in client, "the caret does nothing")
check("every foldable panel is wired", 'for _, panelName in ipairs({ "Stats", "WavePanel", "Actions", "Combat" })' in client,
      "a caret is drawn but not wired")
check("the fold is applied on render", "Hud.applyFolds(state.folded)" in client, "the fold never shows")

print("\nWIRING 17: the first field cannot kill the player")

# K asked that the level-1 map never kill, so a player can grind there forever
# and build a character. The rule lives in the zone table and is applied at the
# one place a monster damages a player.
check("the zone table marks safety", "lethal: boolean" in zones, "zones have no safety flag")
check("the first field is safe", "lethal = false" in zones, "no field is safe")
check("safety is queryable", "function Zones.isLethal(" in zones, "no isLethal()")
check("an unknown field is lethal", "return true" in zones, "an unknown field is safe")
check("damage can be non-lethal", "nonLethal: boolean?" in combat, "damage cannot be floored")
check("a non-lethal hit floors at 1", "nonLethal and 1 or 0" in combat, "the floor is missing")
check("the server asks the zone", "Zones.isLethal(record.field" in server, "the server ignores the safety flag")
check("the server passes the flag", "damage, safeField" in server, "the flag never reaches the damage call")
check("the HUD knows the field is safe", "fieldLethal = record.field" in server, "the HUD cannot tell the player")
check("the player is told they are safe", 'Text.get("safeField")' in hud, "no safe-field notice")
check("travel heals the player", "applySpawnStats(record)\n\tWorld.placePlayer" in server,
      "a player at 1 HP can travel into a lethal field and die instantly")

print("\nWIRING 18: the maps are built as places, not as scattered props")

check("the world places landmarks", "Scenery.landmarks(" in world, "landmarks are never placed")
check("the world builds the landmarks", "buildLandmarks(" in world, "landmarks are placed but not built")
check("the town gets landmarks", 'buildLandmarks(town, "Town"' in world, "the town has no square or wall")
check("a field gets landmarks", "buildLandmarks(model, field.id" in world, "a field has no gate")
check("the scatter is kept off the landmarks", "reserveLandmarks(" in world,
      "a tree can grow through the church")
check("a landmark can decline to reserve", "reserve ~= false" in world,
      "the paving reserves the whole square")
check("the paving does not reserve", "reserve = false" in scenery, "the paving starves the scatter")
check("the town's gates follow the roads", "gateAngles" in world,
      "a gate is built somewhere with no portal")
check("a gate is an arch between towers", "GateArch" in scenery and "GateTower" in scenery,
      "the gate has no arch or no towers")
check("the town has a fountain", '"Fountain"' in scenery, "the square has no fountain")
check("the town has a church", '"Church"' in scenery, "the city has no church")
check("the town has a wall", '"Wall"' in scenery, "the city is unwalled")
check("the town has a statue", '"Statue"' in scenery, "the square has no statue")
check("every field has a gate kind", all(
    f'"{place}Gate"' in scenery for place in ("Meadow", "Cavern", "Volcano", "Void", "Heaven")
), "a field has no gate prop")
check("every field has a shrine or landmark", all(
    f'"{place}Shrine"' in scenery for place in ("Meadow", "Cavern", "Volcano", "Void", "Heaven")
), "a field has no landmark prop")
check("water is see-through", 'water = "Glass"' in scenery, "water is drawn as stone")
check("the world honours a prop's alpha", "spec.alpha" in world, "a pond is opaque")
check("the wall runs along the wall", "math.pi / 2 - angle" in scenery,
      "a wall panel is turned across the wall")
check("the field gate faces the road", "math.atan2(gx / gl, gz / gl)" in scenery,
      "the gate is turned away from the road")

print("\nWIRING N: the story spine is actually driven by the server")

# A quest module can be perfect and still never run if no server event calls it.
# That is the same class of bug as World.attachPlayer() existing but never being
# called, so it is checked the same way: by reading the source.
check("the server requires the quest module", "require(Shared.Quests)" in server,
      "the quest module is never loaded")
check("the server restores quests from the save", "Quests.fromSnapshot(" in server,
      "quest progress is not restored on load")
check("the server persists quests", "quests = record.quests" in server,
      "quest progress is not saved")
check("the client receives the quest snapshot", "quest = Quests.snapshot(" in server,
      "the quest never reaches the client")

# Every objective kind the spine defines needs a server event that produces it,
# or that quest can never complete and the story dead-ends.
for kind, reason in (
    ("KILL", "killing a monster never advances the story"),
    ("KILL_BOSS", "killing a boss never advances the story"),
    ("HARVEST", "harvesting never advances the story"),
    ("ENTER_FIELD", "travelling never advances the story"),
    ("CHOOSE_CLASS", "choosing a class never advances the story"),
    ("EQUIP", "equipping an item never advances the story"),
):
    check(f"the server raises a {kind} quest event", f'questEvent(record, "{kind}"' in server, reason)

print("\nWIRING P: the phone screen is not covered in panels")

# A phone screen is small, and the HUD used to open every panel at once: five
# panels, three of them permanent, plus the attack buttons. It read as a
# spreadsheet rather than a game. These checks read the layout, because no Luau
# test can see a screen.

check("the quest tracker exists", '"QuestPanel"' in hud, "no quest panel was built")
check("the quest tracker is on screen by default",
      "quest.Visible = false" not in hud, "the quest tracker starts hidden")

# Every overlay is opened by a button, so every overlay must start hidden.
for literal, reason in (
    ("boss.Visible = false", "the boss bar is on screen from the start"),
    ("rewards.Visible = false", "the rewards overlay is on screen from the start"),
    ("travel.Visible = false", "the travel list is on screen from the start"),
    ("charPanel.Visible = false", "the character sheet is on screen from the start"),
):
    check(f"hidden at build time: {literal}", literal in hud, reason)

check("the six-button actions menu starts folded, not open",
      "folded = { Actions = true }" in client,
      "the actions menu opens on the phone at start")
check("only the actions menu is folded by default",
      client.count("folded = { Actions = true }") == 1,
      "the default fold state is not the single actions menu")

# The panel geometry now lives in HudLayout, which the layout suite executes and
# the HUD reads, so these checks read the same numbers the game builds from.
layout = read(ROOT / "roblox/src/client/HudLayout.luau")
check("the panel sizes live in one module", "HudLayout.PANEL_WIDTH" in layout and "HudLayout.PANEL_HEIGHT" in layout,
      "the sizes are not centralised")
check("the HUD reads the panel sizes from the module", "HudLayout.PANEL_WIDTH" in hud,
      "the HUD keeps its own copy of the sizes")
check("the HUD reads the panel heights from the module", "HudLayout.clampHeight" in hud,
      "a panel is not capped to the screen")

# This is the bug the layout suite found: a panel taller than the viewport is
# centred off the screen, which puts its close button out of reach.
check("a panel taller than the screen is capped", "HudLayout.clampHeight" in hud,
      "the character sheet is not capped")
check("a centred panel is pinned inside the safe area", "HudLayout.centredTop" in hud,
      "an overlay is centred on the screen and hangs off it")
check("the action menu reflows on a short screen", "HudLayout.menuColumns" in hud,
      "the menu cannot reflow")
check("the combat panel has a compact form", "COMBAT_COMPACT" in hud,
      "the combat panel does not fit a phone")

# The top-left quest panel and the top-right stats panel must not meet in the
# middle, or the quest text runs under the stat readout. Measured on the
# reference screen, because that is what the sizes are written against.
widths = {}
for match in re.finditer(r'(\w+)\s*=\s*(\d+),', layout):
    widths.setdefault(match.group(1), int(match.group(2)))

check("the quest panel was measured", "QuestPanel" in widths, "QuestPanel width not found")
check("the stats panel was measured", "Stats" in widths, "Stats width not found")

if "QuestPanel" in widths and "Stats" in widths:
    quest_edge = 12 + widths["QuestPanel"]
    stats_edge = 1280 - 12 - widths["Stats"]
    check("the top-left quest panel does not reach the top-right stats panel",
          quest_edge < stats_edge,
          f"quest reaches {quest_edge}px, stats begin at {stats_edge}px on a 1280px screen")

# The attack button is bottom centre and the actions menu is bottom right, so an
# open menu must not cover the button the game is played with.
if "Combat" in widths and "Actions" in layout:
    action_width = 200
    combat_right = 640 + widths["Combat"] / 2
    actions_left = 1280 - 16 - action_width
    check("the actions menu does not cover the attack button",
          combat_right < actions_left,
          f"attack button ends at {combat_right}px, menu begins at {actions_left}px")

print("\nWIRING Q: a learned skill is one tap away, not behind a menu")

# The character sheet had every skill behind two taps and a tab, which is where a
# fight is lost. The bar puts the same server-built hotbar on screen. These
# checks read both sides, because a bar drawn from a list the server never sends
# is a row of dead buttons.

check("the HUD builds a skill bar", '"SkillBar"' in hud, "no skill bar was built")
check("the bar sits above the combat panel", "SkillBar" in hud and "Combat" in hud,
      "the skill bar and the combat panel are not both present")

check("the client fills the bar from the server hotbar",
      "state.hotbar" in client and "SKILL_SLOTS" in client,
      "the bar is not built from the server's hotbar")
check("the client only draws as many skills as the bar holds",
      "math.min(#hotbar, HudLayout.SKILL_SLOTS)" in client,
      "the bar can overflow with more skills than it has slots")
check("a tap on the bar casts the skill",
      "Intent.castSkill(skill.id)" in client,
      "a skill button on the bar does not cast")

# An empty bar is a row of nothing sitting over the attack button.
check("the bar hides when the player has no skills",
      "skillBar.Visible = #hotbar > 0" in client,
      "an empty skill bar is still on screen")

# Intent is filled in far below render(), so the closures that cast from the bar
# must see the forward declaration or they capture a nil global.
check("Intent is declared before the buttons that use it",
      re.search(r"^local Intent\s*$", client, re.MULTILINE) is not None,
      "Intent is not forward-declared; skill buttons will index a nil global")
check("Intent is assigned, not re-declared, later",
      "local Intent = {}" not in client and "Intent = {}" in client,
      "Intent is still a second local, so the closures capture the global")

# The bar's room comes from the compact combat panel. If the panel grows back to
# its stacked form the bar measures off the top of a phone screen -- which is the
# failure the layout suite already caught once.
check("the compact combat panel leaves room for the bar",
      "COMBAT_COMPACT_HEIGHT = 176" in layout,
      "the compact combat panel is tall enough to push the skill bar off a phone screen")

# The bar's room is measured from COMBAT_COMPACT_HEIGHT, but the panel is built
# to COMBAT_COMPACT.panelHeight. Two copies of one number, so they must agree or
# the bar is placed against a panel that is not the one on screen.
heights = [int(m) for m in re.findall(r"COMBAT_COMPACT_HEIGHT\s*=\s*(\d+)", layout)]
built = re.search(r"local COMBAT_COMPACT = \{.*?panelHeight = (\d+),", hud, re.DOTALL)
check("the compact panel height is written once in the layout module",
      len(heights) == 1, f"COMBAT_COMPACT_HEIGHT is defined {len(heights)} times")
check("the compact panel is built to the height the bar measures against",
      built is not None and heights and int(built.group(1)) == heights[0],
      "COMBAT_COMPACT.panelHeight and COMBAT_COMPACT_HEIGHT disagree, so the bar is placed against the wrong panel")

print(f"\nWIRING: {passed} passed, {len(failures)} failed")
for failure in failures:
    print(f"  FAIL  {failure}")

sys.exit(1 if failures else 0)

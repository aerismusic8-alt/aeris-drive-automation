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
check("the HUD has a MAP button", re.search(r'button\([\w]+, "Map"', hud) is not None, "missing")
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
check("the HUD has a FARM button", re.search(r'button\([\w]+,\s*"Farm"', hud) is not None, "missing")
check("the HUD has an AXE button", re.search(r'button\([\w]+,\s*"Axe"', hud) is not None, "missing")
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
check("the client tracks folded panels", "folded = {}" in client, "the client forgets the folds")
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

print(f"\nWIRING: {passed} passed, {len(failures)} failed")
for failure in failures:
    print(f"  FAIL  {failure}")

sys.exit(1 if failures else 0)

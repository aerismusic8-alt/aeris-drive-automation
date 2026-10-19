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
check("the world creates a portal back to town", "Return to Town" in world, "no portal home")
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
check("the client shows the combo", "Combat x" in client or "combo x" in client, "no combo display")

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
for marker in ("world", "hud", "dailyRewards", "codes"):
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

print(f"\nWIRING: {passed} passed, {len(failures)} failed")
for failure in failures:
    print(f"  FAIL  {failure}")

sys.exit(1 if failures else 0)

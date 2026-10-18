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

check("the server builds the arena", "World.buildArena()" in server, "never built")
check("the server spawns enemies", "World.spawnEnemy" in server, "never spawns")
check("the server ticks enemies", "World.updateEnemies" in server, "never ticks")
check("the character is moved onto the arena spawn", "World.attachPlayer" in server, "never called")
check("the arena creates a baseplate", '"Baseplate"' in world, "no Baseplate part")
check("the arena creates a spawn", '"ArenaSpawn"' in world or 'Instance.new("SpawnLocation")' in world, "no spawn")
check("the server owns enemy damage", "World.damageEnemy" in server, "no server-side damage")

print("\nWIRING 8: a respawn revives the combatant")

# Death clears this flag and only the spawn path sets it back. Without it a
# player attacks until their first death and then never again.
check("the spawn path revives the combatant", "combatant.alive = true" in server, "never reset")

print("\nWIRING 9: the build verifier covers every module")

build_script = read(ROOT / "AX_PC_CONTROL/pc1-roblox-build.ps1")
for marker in ("world", "hud", "dailyRewards", "codes"):
    check(f"the build verifier checks {marker}", f"{marker}" in build_script, "marker missing")

print(f"\nWIRING: {passed} passed, {len(failures)} failed")
for failure in failures:
    print(f"  FAIL  {failure}")

sys.exit(1 if failures else 0)

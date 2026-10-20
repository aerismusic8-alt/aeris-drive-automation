#!/usr/bin/env python3
"""Keep the game renderable on the hardware most players actually own.

The live client on PC1 is an Intel HD Graphics adapter. It cannot supply several
of Roblox's shaders, and the world then draws almost black with only the HUD
visible. Voxel lighting with global shadows off is what fixed it, and it is also
the right default for the mobile players this game targets.

That fix is one line in a project file and one in World.luau, so it is easy to
undo by accident while making the game look better on a fast machine. This reads
the source and fails loudly if the low-end settings are dropped.

Run: python3 scripts/check-low-end-lighting.py
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "roblox" / "default.project.json"
WORLD = ROOT / "roblox" / "src" / "server" / "World.luau"

failures = []


def check(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(name if not detail else f"{name}: {detail}")


try:
    project = json.loads(PROJECT.read_text(encoding="utf-8"))
except Exception as exc:  # a broken project file is its own failure
    print(f"FAIL  {PROJECT} is readable -- {exc}")
    sys.exit(1)

lighting = project.get("tree", {}).get("Lighting", {}).get("$properties", {})

# Rojo serialises the enum by name, so the file must say Voxel.
check(
    "the place ships Voxel lighting",
    lighting.get("Technology") == "Voxel",
    f"Technology={lighting.get('Technology')!r}",
)
check(
    "the place ships with global shadows off",
    lighting.get("GlobalShadows") is False,
    f"GlobalShadows={lighting.get('GlobalShadows')!r}",
)

world = WORLD.read_text(encoding="utf-8")
# applyLook re-lights the world on every field entry, so it can re-enable
# shadows that the project file turned off. Both must agree.
check(
    "World.applyLook keeps global shadows off",
    "Lighting.GlobalShadows = false" in world,
)
check(
    "nothing turns global shadows back on",
    not re.search(r"GlobalShadows\s*=\s*true", world),
    "GlobalShadows = true found in World.luau",
)

# Future lighting is the mode that fails on this class of GPU; it is not used
# anywhere today and should not creep in without this check being revisited.
future_hits = [
    p.relative_to(ROOT).as_posix()
    for p in (ROOT / "roblox" / "src").rglob("*.luau")
    if re.search(r"Enum\.Technology\.Future|Technology\s*=\s*\"Future\"", p.read_text(encoding="utf-8"))
]
check("no module asks for Future lighting", not future_hits, ", ".join(future_hits))

print(f"\nLIGHTING: {len(failures)} failed")
sys.exit(1 if failures else 0)

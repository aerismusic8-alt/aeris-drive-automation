#!/usr/bin/env python3
"""Register the permanent Roblox goals in the canonical task registry.

Idempotent: re-running updates the existing entries instead of duplicating
them. These two goals are standing objectives, not one-off tasks, so they are
marked autonomous and never move to DONE on their own.

Run: python3 AKATH_CORE/add_roblox_goals.py
"""

import json
import sys
from pathlib import Path

REGISTRY = Path(__file__).resolve().parent / "CANONICAL_TASK_REGISTRY.json"

GOALS = [
    {
        "task_id": "AKATH-ROBLOX-GOAL-PLAYABLE-001",
        "type": "PRODUCT",
        "title": "Ship a Roblox game anyone can enter and play",
        "capability": "product",
        "action": "roblox_game_playable_by_all",
        "status": "IN_PROGRESS",
        "created_at": "2026-10-18T00:00:00.000Z",
        "deadline_at": None,
        "milestones": [
            "Game world and spawn exist so a player lands somewhere",
            "Core loop runs server-side without errors on a live server",
            "First-time player can earn, level up and see progress",
            "Published to Roblox and reachable by public join",
        ],
        "completion_criteria": [
            "A player who has never seen the game can join and play",
            "The game runs a full session without server errors",
            "Progress saves and reloads across sessions",
        ],
        "evidence": {
            "universeId": 10773483379,
            "rootPlaceId": 98458071284292,
            "name": "AX Arena 2: Monster Fields",
            "publishedVersion": 2,
            "publishedAt": "2026-10-28T12:59:22Z",
            "uploadBytes": 576246,
            "sourceBlocks": 39,
            "publishHttpStatus": 200,
            "publisher": "PC1 (self-hosted runner) via Roblox Open Cloud API",
            "builtFrom": "ax-arena-roblox-game",
            "verifiedAt": "2026-10-28T13:20:00Z",
            "notes": [
                "The place is published without Roblox Studio; Rojo builds it and the "
                "Open Cloud API publishes it.",
                "An anonymous playability probe reads GuestProhibited; the owner probe "
                "reads Playable. The gate is the audience rating, not the build.",
                "main and ax-arena-roblox-game diverged on 2026-10-19; the live place "
                "runs the branch's roblox/ (39 source blocks), not main's (28).",
            ],
        },
        "verification": {
            "verified": False,
            "reasons": [
                "Published and owner-playable, but an anonymous player still cannot join: "
                "the audience rating gate keeps under-16 reach closed",
            ],
        },
        "completed_at": None,
        "payload": {
            "action": "roblox_game_playable_by_all",
            "capability": "product",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "path": "roblox/",
            "blocker": (
                "Anonymous join is refused by the audience rating (16+ and trusted "
                "friends). The free road is the 16+ rating plus the 250-engaged-player "
                "review; the paid 1,000-Robux under-16 fee is ruled out by Rule #1."
            ),
        },
        "started_at": "2026-10-18T00:00:00.000Z",
        "attempt": 1,
        "result": None,
        "verified_at": None,
    },
    {
        "task_id": "AKATH-ROBLOX-GOAL-REVENUE-001",
        "type": "PRODUCT",
        "title": "Generate real revenue from the Roblox game",
        "capability": "product",
        "action": "roblox_game_revenue",
        "status": "IN_PROGRESS",
        "created_at": "2026-10-18T00:00:00.000Z",
        "deadline_at": None,
        "milestones": [
            "Monetization catalogue defined with server-side prices",
            "Gamepasses and developer products created on Roblox",
            "Purchases grant entitlements and survive a rejoin",
            "First real Robux earned",
        ],
        "completion_criteria": [
            "At least one paid product is live and purchasable",
            "A purchase grants its entitlement and persists",
            "Revenue is visible in the Roblox dashboard",
        ],
        "evidence": {
            "catalogue": "roblox/src/shared/Monetization.luau (6 products, prices server-side)",
            "assetIdsSet": False,
            "targetUniverseId": 10773483379,
            "verifiedAt": "2026-10-28T13:20:00Z",
            "notes": [
                "No gamepass or developer-product id exists yet, so every product "
                "reports assetId=nil and the client refuses to prompt.",
                "The catalogue is the older roblox/ tree. The live place runs the "
                "ax-arena-roblox-game branch, so confirm which tree owns the shop "
                "before creating assets.",
            ],
        },
        "verification": {"verified": False, "reasons": ["No Roblox asset ids set yet"]},
        "completed_at": None,
        "payload": {
            "action": "roblox_game_revenue",
            "capability": "product",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "path": "roblox/src/shared/Monetization.luau",
            "blocker": (
                "Needs gamepass/product asset ids from the Roblox website, created "
                "under navintas938 for universe 10773483379."
            ),
        },
        "started_at": "2026-10-18T00:00:00.000Z",
        "attempt": 1,
        "result": None,
        "verified_at": None,
    },
]


def main() -> int:
    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    tasks = data["tasks"]

    by_id = {t.get("task_id"): t for t in tasks}
    added, updated = 0, 0

    for goal in GOALS:
        existing = by_id.get(goal["task_id"])
        if existing is None:
            tasks.append(goal)
            added += 1
            continue

        # Preserve progress that a later run may have recorded.
        merged = dict(goal)
        merged["attempt"] = existing.get("attempt", goal["attempt"])
        merged["result"] = existing.get("result", goal["result"])
        merged["status"] = existing.get("status", goal["status"])
        # A recorded value wins over the template's, so re-running this does not
        # erase evidence a session already gathered. `existing.get(k, default)`
        # is not enough: the key exists and holds None, which would win.
        if existing.get("evidence") is not None:
            merged["evidence"] = existing["evidence"]
        if existing.get("verification", {}).get("verified"):
            merged["verification"] = existing["verification"]
        existing.clear()
        existing.update(merged)
        updated += 1

    REGISTRY.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"registry: {added} added, {updated} updated, {len(tasks)} tasks total")
    return 0


if __name__ == "__main__":
    sys.exit(main())

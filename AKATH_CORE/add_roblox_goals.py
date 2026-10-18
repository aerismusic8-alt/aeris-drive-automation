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
        "evidence": None,
        "verification": {"verified": False, "reasons": ["Not published to Roblox yet"]},
        "completed_at": None,
        "payload": {
            "action": "roblox_game_playable_by_all",
            "capability": "product",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "path": "roblox/",
            "blocker": "Publishing requires Roblox Studio (desktop only)",
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
        "evidence": None,
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
            "blocker": "Needs gamepass/product asset ids from the Roblox website",
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
        merged["evidence"] = existing.get("evidence", goal["evidence"])
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

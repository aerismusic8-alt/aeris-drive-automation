#!/usr/bin/env python3
"""Park the Roblox standing goals and name the four jobs as the focus.

K, 2026-11-09: "focus the four aeris938-2 jobs; park the rest separately for
now." The four jobs (Facebook, TikTok, YouTube @aerismusicth, Shopee Affiliate)
are the live focus; the four Roblox tasks are set aside.

A standing goal is "never closed as an ordinary task", so parking must not look
like closing. This script sets the Roblox tasks to `PARKED` — a new, reversible
label, not in the runtime's transition table — and records why, keeping every
piece of evidence and history. The runtime only ever claims `PENDING` tasks, so a
parked task is simply ignored: it cannot be executed, completed, or swept to
OVERDUE.

It also writes a `focus` block naming the four jobs, so "what are we working on"
has one explicit answer that does not depend on reading statuses.

Idempotent: re-running keeps the tasks parked and rewrites the same focus block.

Run: python3 AKATH_CORE/park_roblox_goals.py
"""

from __future__ import annotations

import json
import time
from pathlib import Path

REGISTRY = Path(__file__).resolve().parent / "CANONICAL_TASK_REGISTRY.json"

PARK = [
    "AKATH-ROBLOX-GOAL-PLAYABLE-001",
    "AKATH-ROBLOX-GOAL-REVENUE-001",
    "AKATH-ROBLOX-GOAL-REACH-002",
    "AKATH-ROBLOX-MONITOR-HOURLY-003",
]

FOCUS = [
    "AKATH-GROWTH-FACEBOOK-001",
    "AKATH-GROWTH-TIKTOK-001",
    "AKATH-GROWTH-YOUTUBE-001",
    "AKATH-REVENUE-SHOPEE-001",
]

PARK_REASON = (
    "Parked 2026-11-09 by K's instruction: focus the four aeris938-2 jobs "
    "(Facebook, TikTok, YouTube @aerismusicth, Shopee Affiliate) and set the rest "
    "aside for now. This is a standing goal, so it is parked, not closed — all "
    "evidence and history are kept, and it resumes by setting status back to "
    "IN_PROGRESS."
)


def main() -> int:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    by_id = {t["task_id"]: t for t in registry["tasks"]}
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    parked = 0
    for task_id in PARK:
        task = by_id.get(task_id)
        if task is None:
            continue
        if task.get("status") != "PARKED":
            parked += 1
        task["status"] = "PARKED"
        task["parked_at"] = now
        task["parked_reason"] = PARK_REASON

    registry["focus"] = {
        "scope": "aeris938-2",
        "tasks": FOCUS,
        "note": "K 2026-11-09: the four jobs below are the focus; everything else "
        "(Roblox standing goals) is parked.",
        "updated_at": now,
    }

    REGISTRY.write_text(
        json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"parked={parked} focus={len(FOCUS)} updated_at={now}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

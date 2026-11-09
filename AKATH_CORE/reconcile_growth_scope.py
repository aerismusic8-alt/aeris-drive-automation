#!/usr/bin/env python3
"""Reconcile the canonical task registry with the live scope (aeris938-2).

The registry was last written 2026-09-19, so it still describes the September
PC1 control-bridge test programme as the current work. K's scope reduction
(2026-11-02) cut all of that and named exactly four jobs — grow Facebook, grow
TikTok, grow YouTube (@aerismusicth, one channel), Shopee Affiliate revenue —
which live in `aeris938-2/` and were absent from the registry entirely.

This script makes the registry honest again, and only that:

  * adds the four growth surfaces (+ the measurement rail that tracks them) as
    canonical tasks, with the live numbers as evidence,
  * marks the out-of-scope PC1 tasks SUPERSEDED with a reason — they were *cut*
    by K's scope reduction, they did not fail,
  * leaves the four Roblox standing goals untouched,
  * points `current_work` at the live top priority.

It does not invent targets or deadlines: every number below is read from a file
that already exists in the repo, named in the task's evidence.

Idempotent: re-running updates the existing entries instead of duplicating them.

Run: python3 AKATH_CORE/reconcile_growth_scope.py
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

REGISTRY = Path(__file__).resolve().parent / "CANONICAL_TASK_REGISTRY.json"

SCOPE_CUT = (
    "Cut by K's scope reduction 2026-11-02: the work is now exactly four growth "
    "jobs in aeris938-2 (Facebook, TikTok, YouTube @aerismusicth, Shopee "
    "Affiliate). This task is outside that scope; it did not fail. Retained for "
    "the record, superseded rather than deleted."
)

# Stale PC1 programme tasks (PENDING/OVERDUE from 2026-09-17/18) that K's scope
# reduction removed from current work.
SUPERSEDE = [
    "AKATH-PC1-CONTROL-BRIDGE-001",
    "AKATH-AX-PC1-BRIDGE-PROOF-002",
    "AKATH-PC1-LIVE-EXECUTION-GATE-003",
    "AKATH-PC1-CONTROL-BRIDGE-LIVE-004",
    "AKATH-PC1-FIRST-PRODUCTIVE-AI-001",
]

# The four surfaces + the measurement rail. Every value is a live reading from a
# file in the repo (named in `payload.source`), not an estimate.
NEW_TASKS = [
    {
        "task_id": "AKATH-GROWTH-YOUTUBE-001",
        "type": "PRODUCT",
        "title": "Grow the one YouTube channel @aerismusicth",
        "capability": "growth",
        "action": "grow_youtube",
        "status": "IN_PROGRESS",
        "created_at": "2026-11-02T00:00:00.000Z",
        "deadline_at": None,
        "milestones": [
            "Channel brand complete (banner + description); avatar has no API",
            "Steady cadence: daily Shorts for reach + long-form for watch-hours",
            "Reach the YPP gate (1,000 subs + 4,000 public watch-hours)",
        ],
        "completion_criteria": [
            "Subscribers and watch-hours grow week over week",
            "1,000 subscribers and 4,000 public watch-hours reached",
        ],
        "evidence": {
            "channel": "@aerismusicth (ch3)",
            "channelId": "UCm44BjAn03ruOF-WaA3ZRww",
            "subscribers": 7,
            "videos": 31,
            "views": 1214,
            "gate": "1,000 subs + 4,000 public watch-hours in 12 months (YPP)",
            "driver": "aeris938-2/scripts/grow.py youtube",
            "releaseRail": ".github/workflows/ax-music-release.yml",
            "measuredAt": "2026-11-09T03:08:25Z",
            "source": "aeris938-2/work/history.jsonl (latest row)",
            "notes": [
                "One channel only — ch1/ch2/ch4 are explicitly out of scope.",
                "The channel avatar has no API; it is Studio-only.",
                "YPP thresholds rise 2027-02-01 to 8,000 hours or 20M Shorts views.",
            ],
        },
        "verification": {
            "verified": False,
            "reasons": ["7 / 1,000 subscribers; the gate is far off and reach is flat"],
        },
        "completed_at": None,
        "payload": {
            "action": "grow_youtube",
            "capability": "growth",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "scope": "aeris938-2",
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "target": {"subscribers": 1000, "watchHours": 4000},
            "blocker": None,
            "source": "aeris938-2/work/growth-report.md",
        },
    },
    {
        "task_id": "AKATH-GROWTH-FACEBOOK-001",
        "type": "PRODUCT",
        "title": "Grow the AERIS Music Facebook Page",
        "capability": "growth",
        "action": "grow_facebook",
        "status": "IN_PROGRESS",
        "created_at": "2026-11-02T00:00:00.000Z",
        "deadline_at": None,
        "milestones": [
            "Page profile complete (avatar, cover, bio)",
            "Reels/Shorts posted continuously from the committed queue",
            "First non-owner follower and first readable 28-day views",
        ],
        "completion_criteria": [
            "Page has followers > 0 and 28-day views > 0",
            "Reels post continuously from the queue without a pod",
        ],
        "evidence": {
            "pageId": "61595890900382",
            "followers": 1,
            "queue": {"posted": 11, "pending": 100},
            "views28d": None,
            "driver": "aeris938-2/scripts/grow.py facebook",
            "rails": [
                ".github/workflows/ax-music-admin.yml (FB Page watch + draft)",
                ".github/workflows/ax-music-crosspost.yml (FB Reels)",
            ],
            "measuredAt": "2026-11-09T02:39:09Z",
            "source": "aeris938-2/work/admin-log.jsonl (latest row)",
            "notes": [
                "28-day views are only readable inside Business Suite; UNKNOWN here, not guessed.",
                "The Page posts by itself through the crosspost rail; a Meta System User "
                "token would make it API-only (one K action, documented).",
            ],
        },
        "verification": {
            "verified": False,
            "reasons": ["1 follower and 0 readable views; the Page has not started growing"],
        },
        "completed_at": None,
        "payload": {
            "action": "grow_facebook",
            "capability": "growth",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "scope": "aeris938-2",
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "target": {"followers": 1, "views28d": 1},
            "blocker": "A Meta System User token is the one K action that removes the browser fallback.",
            "source": "aeris938-2/work/growth-report.md",
        },
    },
    {
        "task_id": "AKATH-GROWTH-TIKTOK-001",
        "type": "PRODUCT",
        "title": "Grow the AERIS Music TikTok account",
        "capability": "growth",
        "action": "grow_tiktok",
        "status": "IN_PROGRESS",
        "created_at": "2026-11-02T00:00:00.000Z",
        "deadline_at": None,
        "milestones": [
            "Profile complete (avatar + bio)",
            "Shorts posted continuously from the queue",
            "First follower and first readable 7-day views",
        ],
        "completion_criteria": [
            "Followers > 0 and 7-day views > 0",
            "1,000 followers reached so TikTok Shop Affiliate unlocks",
        ],
        "evidence": {
            "account": "@aeris.music4",
            "followers": 0,
            "views7d": 447,
            "queue": {"posted": 16, "pending": 63},
            "gate": "1,000 followers + age/identity check (TikTok Shop Affiliate, pays in TH)",
            "driver": "aeris938-2/scripts/grow.py tiktok",
            "rail": ".github/workflows/ax-music-crosspost.yml",
            "measuredAt": "2026-11-09T03:08:25Z",
            "source": "aeris938-2/work/growth-report.md",
        },
        "verification": {
            "verified": False,
            "reasons": ["0 followers despite 447 7-day views; views are not converting to follows"],
        },
        "completed_at": None,
        "payload": {
            "action": "grow_tiktok",
            "capability": "growth",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "scope": "aeris938-2",
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "target": {"followers": 1000},
            "blocker": "TikTok Content Posting API needs a one-time app review for API posting.",
            "source": "aeris938-2/work/growth-report.md",
        },
    },
    {
        "task_id": "AKATH-REVENUE-SHOPEE-001",
        "type": "PRODUCT",
        "title": "Earn the first Shopee Affiliate commission",
        "capability": "revenue",
        "action": "grow_shopee",
        "status": "IN_PROGRESS",
        "created_at": "2026-11-02T00:00:00.000Z",
        "deadline_at": None,
        "milestones": [
            "Affiliate account onboarded and per-surface tracking links minted",
            "Every video description carries the right surface's link",
            "First click, then first order",
        ],
        "completion_criteria": [
            "Orders > 0 and commission > 0",
            "Accumulated commission reaches the $500 goal (THB 16,780)",
        ],
        "evidence": {
            "account": "navintas",
            "clicks": 0,
            "orders": 0,
            "commissionThb": 0.0,
            "targetThb": 16780,
            "links": {
                "youtube": "https://s.shopee.co.th/8pn3G4alfI",
                "tiktok": "https://s.shopee.co.th/60SrsstoP6",
                "facebook": "https://s.shopee.co.th/2qVq75ACtW",
            },
            "driver": "aeris938-2/scripts/grow.py shopee",
            "rail": ".github/workflows/ax-music-dashboard.yml",
            "measuredAt": "2026-11-09T03:08:25Z",
            "source": "aeris938-2/work/growth-report.md",
            "notes": [
                "Shopee is the only surface that pays immediately, with no follower gate.",
                "The 2026-11-09 fix put the CTA + link into the top compilation's "
                "description (the only long-form video whose link is above the fold); "
                "read the click count again after ~7 days.",
            ],
        },
        "verification": {
            "verified": False,
            "reasons": ["0 clicks, 0 orders, THB 0 commission — the funnel has no traffic yet"],
        },
        "completed_at": None,
        "payload": {
            "action": "grow_shopee",
            "capability": "revenue",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "scope": "aeris938-2",
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "target": {"commissionThb": 16780, "orders": 1},
            "blocker": None,
            "source": "aeris938-2/work/growth-report.md",
        },
    },
    {
        "task_id": "AKATH-GROWTH-MEASURE-001",
        "type": "OPS",
        "title": "Track the four surfaces daily and name the bottleneck",
        "capability": "ops",
        "action": "growth_measure_daily",
        "status": "IN_PROGRESS",
        "created_at": "2026-11-02T00:00:00.000Z",
        "deadline_at": None,
        "milestones": [
            "A reporter that reads all four surfaces and writes one report",
            "A daily watcher that names the one constraint blocking revenue",
            "A schedule that runs with no sandbox and no K",
        ],
        "completion_criteria": [
            "A reading is recorded every day without manual action",
            "The report distinguishes a real number from an unreadable one (UNKNOWN)",
        ],
        "evidence": {
            "report": "aeris938-2/scripts/report.py -> aeris938-2/work/growth-report.md",
            "watch": "aeris938-2/scripts/goal_watch.py -> aeris938-2/work/goal-watch.md",
            "series": "aeris938-2/work/history.jsonl",
            "rail": ".github/workflows/ax-music-dashboard.yml",
            "schedule": "30 8,14,20 * * * (UTC)",
            "latestBottleneck": "reach",
            "measuredAt": "2026-11-09T03:08:25Z",
            "source": "aeris938-2/work/growth-report.md",
        },
        "verification": {
            "verified": False,
            "reasons": [
                "The report runs and commits, but Facebook/TikTok/Shopee read only "
                "through the desktop, so a surface is UNKNOWN whenever it is down."
            ],
        },
        "completed_at": None,
        "payload": {
            "action": "growth_measure_daily",
            "capability": "ops",
            "canonical": True,
            "autonomous": True,
            "standing_goal": True,
            "scope": "aeris938-2",
            "repo": "aerismusic8-alt/aeris-drive-automation",
            "blocker": None,
            "source": "aeris938-2/work/growth-report.md",
        },
    },
]

CURRENT_WORK_TASK = "AKATH-GROWTH-YOUTUBE-001"


def main() -> int:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    tasks = registry["tasks"]
    by_id = {t["task_id"]: t for t in tasks}
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    superseded = 0
    for task_id in SUPERSEDE:
        task = by_id.get(task_id)
        if task is None or task.get("status") == "SUPERSEDED":
            continue
        task["status"] = "SUPERSEDED"
        task["correction"] = SCOPE_CUT
        task["superseded_at"] = now
        superseded += 1

    added = updated = 0
    for new in NEW_TASKS:
        existing = by_id.get(new["task_id"])
        if existing is None:
            tasks.append(new)
            by_id[new["task_id"]] = new
            added += 1
        else:
            existing.update(new)
            updated += 1

    registry["current_work"] = {
        "active": True,
        "task_id": CURRENT_WORK_TASK,
        "updated_at": now,
    }

    REGISTRY.write_text(
        json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"reconciled: superseded={superseded} added={added} updated={updated} "
        f"current_work={CURRENT_WORK_TASK}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

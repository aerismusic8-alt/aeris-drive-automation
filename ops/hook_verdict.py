"""Read the hook experiment: does opening on the chorus beat opening on the intro?

The experiment file (`music938-1/work/hook-experiment.json`) lists the six videos
and where each clip starts. This reads their live view counts and reports views per
day per arm.

The bar is the same 20% that decides every other test on this channel: a gap under
it is a direction, not a winner, and the honest answer is "run it again".

    python3 ops/hook_verdict.py            # read live numbers, print the verdict
    python3 ops/hook_verdict.py --write    # ... and record work/hook-verdict.json
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))

EXPERIMENT = ROOT / "music938-1" / "work" / "hook-experiment.json"
VERDICT = ROOT / "music938-1" / "work" / "hook-verdict.json"
MIN_GAP_PCT = 20.0
SETTLE_DAYS = 3


def _views_per_day(videos: dict[str, dict], ids: list[str],
                   now: datetime) -> dict[str, float | None]:
    out: dict[str, float | None] = {}
    for vid in ids:
        v = videos.get(vid)
        if not v:
            out[vid] = None
            continue
        pub = datetime.fromisoformat(v["published"].replace("Z", "+00:00"))
        age = max((now - pub).total_seconds() / 86400.0, 1 / 24)
        out[vid] = round(v["views"] / age, 2)
    return out


def verdict(per_day: dict[str, dict[str, float | None]], now: datetime,
            ages: dict[str, float]) -> dict:
    medians = {}
    for arm, rows in per_day.items():
        vals = [v for v in rows.values() if v is not None]
        medians[arm] = round(statistics.median(vals), 2) if vals else None
    intro, chorus = medians.get("intro"), medians.get("chorus")
    gap = None
    if intro and chorus:
        gap = round((chorus - intro) / intro * 100.0, 1)
    settled = all(a >= SETTLE_DAYS for a in ages.values()) if ages else False
    if not settled:
        call = "not settled yet — every video needs 72 h"
    elif gap is None:
        call = "no numbers yet"
    elif abs(gap) < MIN_GAP_PCT:
        call = "no clear winner — rerun on another song before changing the default"
    elif gap > 0:
        call = f"chorus-first wins by {gap}% — make it the default"
    else:
        call = f"intro-first wins by {abs(gap)}% — keep the intro"
    return {"median_views_per_day": medians, "gap_pct": gap,
            "settled": settled, "verdict": call,
            "read_at": now.strftime("%Y-%m-%dT%H:%MZ")}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--channel", default="ch3")
    a = ap.parse_args(argv)

    exp = json.loads(EXPERIMENT.read_text(encoding="utf-8"))
    ids = [r["youtube"] for arm in exp["arms"].values() for r in arm]
    if not ids:
        print("the experiment lists no videos")
        return 1

    import yt_auth  # noqa: PLC0415
    import yt_audit  # noqa: PLC0415

    tok = yt_auth.access_token(a.channel)
    rows = yt_audit.fetch(tok, ids)
    videos = {r["id"]: r for r in rows}
    now = datetime.now(timezone.utc)
    ages = {r["id"]: (now - datetime.fromisoformat(
        r["published"].replace("Z", "+00:00"))).total_seconds() / 86400.0
        for r in rows}

    per_day = {arm: _views_per_day(videos, [r["youtube"] for r in rs], now)
               for arm, rs in exp["arms"].items()}
    out = verdict(per_day, now, ages)
    out["per_video"] = {arm: {r["slug"]: per_day[arm].get(r["youtube"])
                              for r in rs}
                        for arm, rs in exp["arms"].items()}
    out["oldest_age_days"] = round(max(ages.values()), 2) if ages else 0
    print(json.dumps(out, ensure_ascii=False, indent=1))
    if a.write:
        VERDICT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n",
                           encoding="utf-8")
        print(f"wrote {VERDICT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

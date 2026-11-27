#!/usr/bin/env python3
"""A/B two title shapes on the same song, so the answer is not about the series.

The 2026-11-26 report showed numbered titles ("ท่อนที่ 2") at 1.29 views/day and
hook titles ("ร้องต่อไหม?") at 0.45. That comparison is confounded: a numbered
part belongs to a series with an audience waiting for it, so its views may come
from the series and not from the shape of the words. K asked for the clean test:
same songs, two shapes, seven days apart, measured after fourteen.

One constraint shapes the design. Publishing the *same* chorus twice would ship
identical audio, which `ops/no_repeat.py` refuses by design (audio SHA-256), and
which YouTube can read as a repost. So a pair is two different choruses of the
same song - chorus 1 with one title shape, chorus 2 with the other - seven days
apart. Same song, same mood, same length band; the only free variable left is the
title.

    python3 ops/title_ab.py --plan      # write this round's plan
    python3 ops/title_ab.py --report    # paired verdict, once both arms settle
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "music938-1" / "scripts"))
import release  # noqa: E402
import title_experiment as te  # noqa: E402
import yt_auth  # noqa: E402
import yt_audit  # noqa: E402

PLAN = Path(__file__).resolve().parents[1] / "music938-1" / "work" / "title-ab-plan.json"
SONGS_PER_ROUND = 5
GAP_DAYS = 7
SETTLE_DAYS = 14
ARMS = ("numbered", "hook")


def title_of(slug: str) -> str:
    """The song's Thai title, falling back to the slug when the lyric is absent."""
    try:
        return release.parse_lyrics(slug).get("TITLE") or slug
    except (OSError, KeyError):
        return slug


def plan_round(songs: list[str], start: date, *, gap_days: int = GAP_DAYS,
               per_round: int = SONGS_PER_ROUND) -> list[dict]:
    """One entry per (song, arm): which chorus, which title, which day.

    Arm order alternates by song index so a weekday effect cannot sit on one arm:
    even songs lead with the numbered title, odd songs with the hook.
    """
    entries: list[dict] = []
    for i, slug in enumerate(songs[:per_round]):
        order = ARMS if i % 2 == 0 else ARMS[::-1]
        for j, arm in enumerate(order):
            hook = 1 + j          # chorus 1 for the first arm, chorus 2 for the second
            label = (release.hook_title(hook) if arm == "hook"
                     else f"ท่อนที่ {hook}")
            entries.append({
                "song": slug,
                "arm": arm,
                "hook": hook,
                # The same shape release.short_description() builds for a Short,
                # so the two arms differ only in the words after the bar.
                "title": f"{title_of(slug)} | {label} #Shorts",
                "date": (start + timedelta(days=gap_days * j)).isoformat(),
            })
    return entries


def pair_report(items: list[dict], plan: list[dict], *,
                now: datetime | None = None) -> dict:
    """Median views/day per arm, plus the per-song paired differences.

    Pairing is the whole point: a song that flops in both arms says nothing about
    the titles, and averaging across songs would let one hit decide the result.
    """
    now = now or datetime.now(timezone.utc)
    by_arm: dict[str, list[float]] = {a: [] for a in ARMS}
    pairs: list[dict] = []
    for slug in sorted({e["song"] for e in plan}):
        row = {"song": slug}
        for e in [x for x in plan if x["song"] == slug]:
            match = [i for i in items if e["title"][:28] in i.get("snippet", {}).get("title", "")]
            if not match:
                row[e["arm"]] = None
                continue
            v = match[0]
            pub = datetime.fromisoformat(
                v["snippet"]["publishedAt"].replace("Z", "+00:00"))
            age = max((now - pub).days, 1)
            per_day = round(int(v["statistics"].get("viewCount", 0)) / age, 2)
            row[e["arm"]] = per_day
            row[f"{e['arm']}_age"] = age
            by_arm[e["arm"]].append(per_day)
        if row.get("numbered") is not None and row.get("hook") is not None:
            row["delta"] = round(row["numbered"] - row["hook"], 2)
        pairs.append(row)

    settled = [p for p in pairs
               if p.get("delta") is not None
               and min(p.get("numbered_age", 0), p.get("hook_age", 0)) >= SETTLE_DAYS]
    out = {
        "median_per_day": {a: (round(statistics.median(v), 2) if v else None)
                           for a, v in by_arm.items()},
        "pairs": pairs,
        "settled_pairs": len(settled),
        "median_delta": (round(statistics.median(p["delta"] for p in settled), 2)
                         if settled else None),
    }
    out["verdict"] = _verdict(out)
    return out


def _verdict(r: dict) -> str:
    if r["settled_pairs"] < 3:
        return (f"not yet: {r['settled_pairs']} of {SONGS_PER_ROUND} pairs have "
                f"both arms past {SETTLE_DAYS} days")
    d = r["median_delta"]
    if d is None:
        return "not yet: no paired result"
    if d > 0:
        return (f"numbered wins by {d} views/day across {r['settled_pairs']} "
                f"songs; make it the default for singles")
    return (f"hook wins or ties ({d}); keep hook - it generalises beyond a series")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--songs", nargs="*", default=[])
    ap.add_argument("--start", default=None, help="YYYY-MM-DD, defaults to today")
    a = ap.parse_args(argv)

    if a.plan:
        songs = a.songs
        if not songs:
            import compass  # noqa: PLC0415
            songs = compass.songs("bank") or []
        start = date.fromisoformat(a.start) if a.start else date.today()
        entries = plan_round(songs, start)
        PLAN.parent.mkdir(parents=True, exist_ok=True)
        PLAN.write_text(json.dumps({"start": start.isoformat(), "entries": entries},
                                   ensure_ascii=False, indent=1) + "\n",
                        encoding="utf-8")
        for e in entries:
            print(f"{e['date']}  {e['arm']:8s} {e['song']}  hook {e['hook']}  {e['title']}")
        return 0

    if not PLAN.exists():
        raise SystemExit(f"no plan at {PLAN}; run --plan first")
    plan = json.loads(PLAN.read_text(encoding="utf-8"))["entries"]
    tok = yt_auth.access_token(a.ch)
    st, items = yt_auth.get_videos(tok, yt_auth.all_upload_ids(tok),
                                   part="snippet,statistics")
    if st != 200:
        raise SystemExit(f"videos.list {st}")
    rep = pair_report(items, plan)
    print(json.dumps(rep, ensure_ascii=False, indent=1))
    print(rep["verdict"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

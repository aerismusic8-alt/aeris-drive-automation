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


def label_for(arm: str, hook: int) -> str:
    return release.hook_title(hook) if arm == "hook" else f"ท่อนที่ {hook}"


def used_hooks(slug: str, published: list[str]) -> set[int]:
    """Choruses of this song that already have a clip on the channel.

    Re-releasing a chorus means identical audio, which `no_repeat` refuses and
    YouTube can read as a repost, so a pair is built from choruses not yet used.
    """
    t = title_of(slug)
    used = set()
    for h in (1, 2, 3):
        if any(f"{t} | {label_for(a, h)}" in x for x in published
               for a in ("numbered", "hook")):
            used.add(h)
    return used


def plan_round(songs: list[str], start: date, *, gap_days: int = GAP_DAYS,
               per_round: int = SONGS_PER_ROUND,
               published: list[str] | None = None) -> list[dict]:
    """One entry per (song, arm): which chorus, which title, which day.

    Arm order alternates by song index so a weekday effect cannot sit on one arm:
    even songs lead with the numbered title, odd songs with the hook.
    """
    entries: list[dict] = []
    planned = 0
    for i, slug in enumerate(songs):
        if planned >= per_round:
            break
        free = [h for h in (1, 2, 3) if h not in used_hooks(slug, published or [])]
        if len(free) < 2:
            continue          # no clean pair left in this song
        planned += 1
        order = ARMS if i % 2 == 0 else ARMS[::-1]
        for j, arm in enumerate(order):
            hook = free[j]
            label = label_for(arm, hook)
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
        "gap_pct": None,
        "median_delta": (round(statistics.median(p["delta"] for p in settled), 2)
                         if settled else None),
    }
    out["gap_pct"] = gap_pct(out)
    out["verdict"] = _verdict(out)
    return out


MIN_GAP_PCT = 20.0


def gap_pct(r: dict) -> float | None:
    """The two arms' medians as a percentage of the larger one."""
    m = r["median_per_day"]
    if m.get("numbered") is None or m.get("hook") is None:
        return None
    hi = max(m["numbered"], m["hook"])
    if hi <= 0:
        return None
    return round(abs(m["numbered"] - m["hook"]) / hi * 100.0, 1)


def _verdict(r: dict) -> str:
    """A direction, never a proof: five pairs is a small sample.

    K's rule (2026-11-26): a gap under 20% is not a result - run a second round on
    other songs before changing the default. Reporting a win here at that size
    would be following noise.
    """
    if r["settled_pairs"] < 3:
        return (f"not yet: {r['settled_pairs']} of {SONGS_PER_ROUND} pairs have "
                f"both arms past {SETTLE_DAYS} days")
    d = r["median_delta"]
    if d is None:
        return "not yet: no paired result"
    gap = gap_pct(r)
    n = r["settled_pairs"]
    if gap is None or gap < MIN_GAP_PCT:
        return (f"no clear winner: {gap}% apart across {n} pairs, under K's "
                f"{MIN_GAP_PCT:.0f}% bar; keep the current default and run a "
                f"second round on other songs")
    leader = "numbered" if d > 0 else "hook"
    tail = ("make it the default for singles" if leader == "numbered"
            else "keep hook - it generalises beyond a series")
    return (f"direction ({n} pairs, not proof): {leader} leads by {d} views/day "
            f"({gap}%); {tail}")


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
        published: list[str] = []
        if songs:
            tok = yt_auth.access_token(a.ch)
            st, items = yt_auth.get_videos(tok, yt_auth.all_upload_ids(tok),
                                           part="snippet")
            if st == 200:
                published = [i["snippet"]["title"] for i in items]
        start = date.fromisoformat(a.start) if a.start else date.today()
        entries = plan_round(songs, start, published=published)
        if not entries:
            raise SystemExit("no song has two unused choruses; nothing to plan")
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

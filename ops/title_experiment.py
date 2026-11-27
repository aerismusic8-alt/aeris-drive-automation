#!/usr/bin/env python3
"""Which title shape wins - measured, not assumed.

The 2026-11-26 audit found question hooks in 80% of the top 20 clips and 30% of
the bottom 20, and `#Shorts` in 90% against 40%. That is a correlation on 40
clips, and K's condition for rolling the pattern out was a staged test: run it on
a handful, wait two weeks, compare. This tool is the comparison.

It records every published clip's title style, then reports median views/day per
style for clips old enough to have settled. Nothing is inferred about causation:
if the staged clips do not beat the baseline, the report says so and the pattern
is not rolled out.

    python3 ops/title_experiment.py --record           # log new uploads
    python3 ops/title_experiment.py --report           # staged verdict
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "music938-1" / "scripts"))
import yt_auth  # noqa: E402
import yt_audit  # noqa: E402

STATE = Path(__file__).resolve().parents[1] / "music938-1" / "work" / "title-experiment.json"

# The audit's top-20 median, kept for context only: a staged test compares the
# new pattern with the channel's other clips, not with its best 20.
BASELINE_VIEWS_PER_DAY = 2.09
SETTLE_DAYS = 14


def style_of(title: str) -> str:
    """The title's shape, from the title alone.

    Inferring beats threading a flag through three upload paths: every clip that
    has already shipped can be classified, so the baseline and the staged clips
    are measured by the same rule.
    """
    if "?" in title or "ไหม" in title or "ใคร" in title:
        return "hook"
    if "—" in title or "–" in title:
        return "dash"
    if "ท่อนที่" in title:
        return "numbered"
    return "plain"


def rows(items: list[dict], now: datetime | None = None) -> list[dict]:
    now = now or datetime.now(timezone.utc)
    out = []
    for it in items:
        pub = it.get("snippet", {}).get("publishedAt", "")
        try:
            at = datetime.fromisoformat(pub.replace("Z", "+00:00"))
        except ValueError:
            continue
        age = (now - at).days
        if age < 0:
            continue
        views = int(it.get("statistics", {}).get("viewCount", 0))
        title = it.get("snippet", {}).get("title", "")
        out.append({"id": it.get("id"), "title": title, "style": style_of(title),
                    "views": views, "age_days": age,
                    "per_day": round(views / max(age, 1), 2),
                    "shorts": "#Shorts" in title})
    return out


def summarise(rs: list[dict], settle_days: int = SETTLE_DAYS) -> dict:
    """Median views/day and the `#Shorts` share, per style, among settled clips."""
    settled = [r for r in rs if r["age_days"] >= settle_days]
    out: dict[str, dict] = {}
    for style in sorted({r["style"] for r in settled}):
        group = [r for r in settled if r["style"] == style]
        out[style] = {
            "n": len(group),
            "median_per_day": round(statistics.median(r["per_day"] for r in group), 2),
            "shorts_share": round(sum(r["shorts"] for r in group) / len(group), 2),
            "median_views": int(statistics.median(r["views"] for r in group)),
            "median_age_days": int(statistics.median(r["age_days"] for r in group)),
        }
    return out


def control(table: dict) -> float | None:
    """The median views/day of every settled clip that is not a hook clip.

    The comparison a staged test needs is hook against *the channel as it is*,
    not against the top 20: the top 20 is a selection at the extreme, so beating
    it was never the question. Pooling the other styles gives the control.
    """
    others = [v for k, v in table.items() if k != "hook" and v["n"]]
    if not others:
        return None
    return round(statistics.median(v["median_per_day"] for v in others), 2)


def verdict(table: dict, max_age_gap: int = SETTLE_DAYS,
            min_n: int = 5) -> str:
    """The staged verdict, with the confounds named rather than averaged away.

    Two ways this comparison lies: hook clips can be younger than the control
    (views/day falls as a video ages, so a fresh group looks different for that
    reason alone), and the hook group can be small enough that one video decides
    it. Both are reported as "not yet", never as a pass.
    """
    hook = table.get("hook")
    ctrl = control(table)
    if not hook or ctrl is None:
        return "no settled hook clips yet; the staged test has not started"
    ages = [v["median_age_days"] for v in table.values() if v["n"]]
    if max(ages) - min(ages) > max_age_gap:
        return (f"not yet: the groups' median ages differ by "
                f"{max(ages) - min(ages)} days, so views/day is measuring age, "
                f"not the title (hook {hook['median_per_day']}/day vs "
                f"control {ctrl}/day)")
    if hook["n"] < min_n:
        return f"not yet: only {hook['n']} settled hook clips"
    if hook["median_per_day"] > ctrl:
        return (f"roll out: hook clips run {hook['median_per_day']}/day against "
                f"a {ctrl}/day control (n={hook['n']}); the top-20 median was "
                f"{BASELINE_VIEWS_PER_DAY}, which is a different question")
    return (f"stop: hook clips run {hook['median_per_day']}/day against a "
            f"{ctrl}/day control (n={hook['n']}); do not roll out")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--record", action="store_true")
    a = ap.parse_args(argv)

    tok = yt_auth.access_token(a.ch)
    ids = yt_auth.all_upload_ids(tok)
    st, items = yt_auth.get_videos(tok, ids, part="snippet,statistics")
    if st != 200:
        raise SystemExit(f"videos.list {st}")

    rs = rows(items)
    if a.record or not a.report:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps({
            "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "clips": rs}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"recorded {len(rs)} clips -> {STATE}")

    table = summarise(rs)
    print(json.dumps(table, ensure_ascii=False, indent=1))
    print(verdict(table))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

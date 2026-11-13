#!/usr/bin/env python3
"""A controlled title experiment on clips that are already live.

Why (2026-11-13 review + advisor panel): the channel is not short of clips -- 72
uploads in 13 days earned 1,981 views, a median of 7.5, one comment. The problem
is *reach*, and the one variable the data already separates is the title. Every
clip whose title is a bare description ("... — เพลงเศร้า ที่เข้าใจความเสียใจ")
sits at 0-7 views; every clip carrying a hook marker ("| ร้องต่อไหม?") sits
higher. That is a testable claim, not a conclusion.

The HOLD (K, 2026-11-13) forbids publishing or rendering new clips. Rewriting the
title of a clip that is already live is neither: no new upload, no new render,
and the change is reversible from the backup this tool writes first.

Design: the arms are assigned deterministically by video-id hash, so re-running
`--plan` gives the same split and a reviewer can reproduce it. Only the treated
arm is written; the control arm is left untouched and measured alongside it, so
the experiment has a real comparison instead of a before/after of one group.

    python3 scripts/metadata_ab.py --plan            # pick arms, write the plan
    python3 scripts/metadata_ab.py --apply           # write treated titles (backup first)
    python3 scripts/metadata_ab.py --report          # judge once the window ends
    python3 scripts/metadata_ab.py --revert          # restore every touched title
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ops"))
import yt_auth  # noqa: E402

WORK = Path(__file__).resolve().parent.parent / "work"
PLAN = WORK / "metadata-ab-plan.json"
BACKUP = WORK / "metadata-ab-backup.json"
CHANNEL = "ch3"
WINDOW_DAYS = 10.0

# A title that carries a question or a part marker is one the channel already
# proved it can place; a bare description is the one being tested. Keep this in
# sync with the review so the group definition is auditable.
HOOK_MARKERS = ("ร้องต่อไหม", "คิดถึงใคร", "ท่อนที่", "#Shorts")
QUESTION_SUFFIX = " | ร้องต่อไหม?"
# Format and title are confounded in the current data: the Shorts (median 18
# views) nearly all carry a hook, and the plain-titled clips are songs (median 2).
# A before/after on the plain group would test the song format, not the title. So
# the test holds the format fixed: it works on Shorts only, where the single
# changed variable really is the title. A song is over 65s and is excluded.
SHORT_MAX_SECONDS = 65


def is_plain(title: str) -> bool:
    return not any(m in title for m in HOOK_MARKERS)


def duration_seconds(video: dict) -> int:
    """ISO-8601 duration -> seconds, so the format can be held fixed."""
    d = video.get("contentDetails", {}).get("duration", "")
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", d)
    if not m:
        return 0
    h, mm, s = (int(x) if x else 0 for x in m.groups())
    return h * 3600 + mm * 60 + s


def arm_of(video_id: str) -> str:
    """Deterministic 50/50 split; hash, not random, so a re-run reproduces it."""
    return "treated" if int(hashlib.sha1(video_id.encode()).hexdigest(), 16) % 2 else "control"


def treatment(title: str) -> str:
    """The one changed variable: append the hook phrase the channel already uses."""
    base = re.sub(r"\s*\|.*$", "", title).strip()
    return (base[:52] + QUESTION_SUFFIX) if len(base) > 52 else (base + QUESTION_SUFFIX)


def fetch(tok: str):
    ids = yt_auth.all_upload_ids(tok)
    st, items = yt_auth.get_videos(tok, ids, part="snippet,statistics,contentDetails")
    if st != 200:
        raise SystemExit(f"videos.list HTTP {st} for {len(ids)} uploads")
    return items


def build_plan(items) -> dict:
    arms = {"treated": [], "control": []}
    skipped = 0
    for v in items:
        sn = v["snippet"]
        secs = duration_seconds(v)
        # Format is held fixed: only Shorts are candidates, and only those whose
        # title does not already carry the hook. Anything else would change two
        # variables at once (format, or an already-applied treatment).
        if secs > SHORT_MAX_SECONDS or not is_plain(sn["title"]):
            skipped += 1
            continue
        entry = {"id": v["id"], "title": sn["title"], "seconds": secs,
                 "views": int(v["statistics"].get("viewCount", 0)),
                 "published": sn["publishedAt"][:10]}
        arms[arm_of(v["id"])].append(entry)
    plan = {
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "channel": CHANNEL,
        "variable": "title carries a hook phrase (| ร้องต่อไหม?) vs unchanged",
        "held_fixed": f"format = Short (<= {SHORT_MAX_SECONDS}s)",
        "window_days": WINDOW_DAYS,
        "excluded": skipped,
        "treated": sorted(arms["treated"], key=lambda e: e["views"]),
        "control": sorted(arms["control"], key=lambda e: e["views"]),
    }
    return plan


def cmd_plan(tok: str) -> int:
    items = fetch(tok)
    plan = build_plan(items)
    t, c = plan["treated"], plan["control"]
    print(f"candidates (Short, no hook yet): treated={len(t)} control={len(c)} "
          f"| excluded={plan['excluded']}")
    if not t:
        print("\nNo treated arm exists, so the experiment cannot run without\n"
              "changing two variables at once. Every live Short already carries a\n"
              "hook phrase; the plain-titled clips are songs, not Shorts. The\n"
              "title claim the review made was confounded with the format.\n"
              "Re-run this once new Shorts exist that do not already carry the\n"
              "hook (after the HOLD lifts).")
        PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")
        return 0
    print("\ntreated (will get the hook phrase):")
    for e in t:
        print(f"  {e['views']:>4}v  {e['title']}\n        -> {treatment(e['title'])}")
    print("\ncontrol (left untouched):")
    for e in c:
        print(f"  {e['views']:>4}v  {e['title']}")
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\nplan -> {PLAN}")
    return 0


def cmd_apply(tok: str) -> int:
    if not PLAN.exists():
        raise SystemExit("run --plan first")
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    if BACKUP.exists():
        raise SystemExit(f"{BACKUP} exists — use --revert first, so a run cannot "
                         "overwrite the true originals")
    items = {v["id"]: v for v in fetch(tok)}
    backup, changed = [], 0
    for e in plan["treated"]:
        v = items.get(e["id"])
        if not v:
            print(f"  skip {e['id']}: not in the upload list")
            continue
        sn = v["snippet"]
        new_title = treatment(sn["title"])
        backup.append({"id": e["id"], "title": sn["title"]})
        st, r = yt_auth.api_request(
            "videos", tok,
            {"id": e["id"], "snippet": {
                "title": new_title, "description": sn.get("description", ""),
                "tags": sn.get("tags", []),
                "categoryId": sn.get("categoryId", "10"),
                "defaultLanguage": sn.get("defaultLanguage", "th")}},
            part="snippet")
        ok = st == 200
        changed += ok
        print(f"  {'ok ' if ok else 'ERR'} {e['id']} -> {new_title}"
              + ("" if ok else f"  HTTP {st} {r}"))
    BACKUP.write_text(json.dumps(backup, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\nchanged {changed} titles; originals -> {BACKUP}")
    return 0 if changed else 1


def _delta(items, ids, start_views) -> dict:
    now = {v["id"]: int(v["statistics"].get("viewCount", 0)) for v in items}
    gains = [now.get(i, 0) - s for i, s in start_views.items() if i in now]
    gains.sort()
    med = gains[len(gains) // 2] if gains else 0
    return {"n": len(gains), "median_gain": med, "total_gain": sum(gains)}


def cmd_report(tok: str) -> int:
    if not PLAN.exists():
        raise SystemExit("run --plan first")
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    items = fetch(tok)
    out = {}
    for arm in ("treated", "control"):
        start = {e["id"]: e["views"] for e in plan[arm]}
        out[arm] = _delta(items, [e["id"] for e in plan[arm]], start)
    age = (datetime.now(timezone.utc)
           - datetime.fromisoformat(plan["at"])).total_seconds() / 86400
    verdict = "RUNNING (window not closed)"
    if age >= plan["window_days"]:
        t, c = out["treated"], out["control"]
        if not t["n"] or not c["n"]:
            verdict = "INCONCLUSIVE (an arm is empty)"
        elif t["median_gain"] > c["median_gain"] * 1.5 and t["total_gain"] > 0:
            verdict = "WIN (treated gains more per clip)"
        elif c["median_gain"] >= t["median_gain"]:
            verdict = "FAILED (the hook phrase did not lift reach)"
        else:
            verdict = "INCONCLUSIVE (lift too small to call)"
    print(json.dumps({"age_days": round(age, 1), "arms": out, "verdict": verdict},
                     ensure_ascii=False, indent=1))
    return 0


def cmd_revert(tok: str) -> int:
    if not BACKUP.exists():
        raise SystemExit("no backup to revert from")
    backup = json.loads(BACKUP.read_text(encoding="utf-8"))
    items = {v["id"]: v for v in fetch(tok)}
    restored = 0
    for e in backup:
        v = items.get(e["id"])
        if not v:
            continue
        sn = v["snippet"]
        if sn["title"] == e["title"]:
            continue
        st, _ = yt_auth.api_request(
            "videos", tok,
            {"id": e["id"], "snippet": {
                "title": e["title"], "description": sn.get("description", ""),
                "tags": sn.get("tags", []),
                "categoryId": sn.get("categoryId", "10"),
                "defaultLanguage": sn.get("defaultLanguage", "th")}},
            part="snippet")
        restored += st == 200
        print(f"  {'ok ' if st == 200 else 'ERR'} {e['id']} -> {e['title']}")
    print(f"restored {restored} titles; {BACKUP} kept as the record")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    for name in ("plan", "apply", "report", "revert"):
        g.add_argument(f"--{name}", action="store_true")
    a = ap.parse_args()
    tok = yt_auth.access_token(CHANNEL)
    if a.plan:
        return cmd_plan(tok)
    if a.apply:
        return cmd_apply(tok)
    if a.report:
        return cmd_report(tok)
    return cmd_revert(tok)


if __name__ == "__main__":
    raise SystemExit(main())

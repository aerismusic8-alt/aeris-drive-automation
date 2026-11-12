#!/usr/bin/env python3
"""Audit the LIVE channel against intent, every day — not the code, the product.

Why this exists (K, 2026-11-09: "even when we check 100% the day has not turned
over and errors still appear; we must keep re-auditing every day"). A real bug
survived a fully green test suite: 1555 tests passed, yet the channel's
most-watched video carried no affiliate link and no subscribe ask for weeks, so
the only revenue surface earned 0 clicks. The tests verified the *generator*;
nothing verified the *published artifact*. "Tests pass" and "the product is
right" are different claims, and only the first was checked.

This reads every live upload and diffs it against sources of truth that are NOT
the code that publishes it:

  * the affiliate + subscribe URLs come from `channel/monetization.json`
    (config), not from `release.py`;
  * the chapter expectation comes from `work/compilation-state-*.json`
    (the record of what was uploaded), not from `compile_album.py`.

Checks per video: a non-empty description, the revenue ask (the configured
affiliate link), the subscribe ask, chapters on a compilation, and the losing
title shape (`| AERIS Music`). Deterministic misses (the revenue/subscribe ask)
are repaired by inserting the same block `compile_album` writes; anything else
alerts. Alerts fire only on a *new* failure, so a daily check does not cry wolf.

    python3 scripts/live_audit.py            # read + report (no writes)
    python3 scripts/live_audit.py --repair   # also fix the deterministic misses
    python3 scripts/live_audit.py --json     # machine-readable
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
MUSIC_SCRIPTS = REPO / "music938-1" / "scripts"
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(MUSIC_SCRIPTS))
sys.path.insert(0, str(REPO / "ops"))

import yt_auth  # noqa: E402  (ops/yt_auth.py)
import monetize  # noqa: E402  (music938-1/scripts/monetize.py)

WORK = ROOT / "work"
REPORT = WORK / "live-audit.md"
STATE = WORK / "live-audit-state.json"
BRAND_TAIL = re.compile(r"\|\s*AERIS Music\s*$", re.IGNORECASE)
CHAPTER = re.compile(r"^\d{1,2}:\d{2} ", re.MULTILINE)
MIN_CHAPTERS = 12
# Cap writes per run so one bad day cannot burn the whole quota pool on repairs.
# 25 videos * 50 units (videos.update) is 1,250 of the 10,000-unit pool, so a
# full-backlog repair fits in one fresh-quota run; the cap only stops a runaway.
MAX_REPAIRS = 50


class QuotaError(RuntimeError):
    """The Data API quota is spent; the audit cannot read today."""


def expected() -> dict:
    """The intent, from config — not from the publishing code."""
    c = monetize.config()
    per = c.get("shopee_links") or {}
    return {
        "affiliate": per.get("youtube") or c.get("shopee_affiliate", ""),
        "youtube": c.get("youtube", ""),
    }


def compilation_ids() -> dict[str, int]:
    """video_id -> expected track count, from the upload state records."""
    out: dict[str, int] = {}
    for st in WORK.glob("compilation-state-*.json"):
        try:
            d = json.loads(st.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        vid = d.get("video_id")
        tracks = d.get("tracks") or d.get("count")
        if vid:
            out[vid] = int(tracks) if tracks else MIN_CHAPTERS
    return out


def check_video(v: dict, exp: dict, comps: dict[str, int]) -> list[str]:
    """Return the failed checks for one live video."""
    sn = v["snippet"]
    desc = sn.get("description", "")
    fails = []
    if not desc.strip():
        fails.append("description_empty")
    if exp["affiliate"] and exp["affiliate"] not in desc:
        fails.append("revenue_ask_missing")
    sub = exp["youtube"]
    if sub and "sub_confirmation" not in desc and sub not in desc:
        fails.append("subscribe_ask_missing")
    if v["id"] in comps:
        n = len(CHAPTER.findall(desc))
        if n < min(comps[v["id"]], MIN_CHAPTERS):
            fails.append(f"chapters_missing({n}/{comps[v['id']]})")
    if BRAND_TAIL.search(sn.get("title", "")):
        fails.append("losing_title_shape")
    return fails


def read_live() -> list[dict]:
    """Every live upload, or QuotaError when the pool is spent.

    `all_upload_ids` walks channels.list + playlistItems.list, which index
    `body["items"]` directly; a 403 quota body has no `items`, so that surfaces
    as a KeyError rather than an HTTP status. Treat it as "quota", not a crash.

    `videos.list` takes at most 50 ids per call, so a channel past 50 uploads
    must be read in chunks (ops/yt_auth.get_videos). Joining every id into one
    call returns HTTP 400 "invalid filter parameter" — a bug, not a quota state,
    and it must not be reported as one.
    """
    tok = yt_auth.access_token("ch3")
    try:
        ids = yt_auth.all_upload_ids(tok)
    except KeyError:
        raise QuotaError("channels.list/playlistItems.list returned no items "
                         "(quota spent or API error)")
    if not ids:
        return []
    st, items = yt_auth.get_videos(tok, ids, part="snippet,status")
    if st == 403:
        raise QuotaError(f"videos.list HTTP {st} (quota spent)")
    if st != 200:
        raise RuntimeError(
            f"videos.list HTTP {st} for {len(ids)} uploads — not a quota error, "
            f"investigate (a >50-id call returns 400 'invalid filter parameter')")
    return items


def repair(video: dict, exp: dict) -> bool:
    """Upgrade a live description with the canonical `monetize.refresh_description`.

    That function already replaces the old homepage link, drops the superseded
    page-first CTA block, and inserts the subscribe-first ask — and it is covered
    by music938-1's tests. Reusing it is why this audit does not need its own
    description writer. Returns True when a write happened.
    """
    sn = video["snippet"]
    desc = sn.get("description", "")
    new_desc = monetize.refresh_description(desc, "youtube")
    if new_desc == desc:
        return False
    tok = yt_auth.access_token("ch3")
    st, r = yt_auth.api_request(
        "videos", tok,
        {"id": video["id"], "snippet": {
            "title": sn["title"], "description": new_desc,
            "tags": sn.get("tags", []),
            "categoryId": sn.get("categoryId", "10"),
            "defaultLanguage": sn.get("defaultLanguage", "th")}},
        part="snippet")
    print(f"   repaired {video['id']}: HTTP {st}" + ("" if st == 200 else f" {r}"))
    return st == 200


def load_prev_failures() -> set[str]:
    if not STATE.exists():
        return set()
    try:
        return set(json.loads(STATE.read_text(encoding="utf-8")).get("failing", []))
    except Exception:  # noqa: BLE001
        return set()


def push(text: str, topic: str) -> None:
    try:
        req = urllib.request.Request(
            f"https://ntfy.sh/{topic}", data=text.encode("utf-8"),
            headers={"Title": "AERIS Music — ตรวจของจริง", "Tags": "mag"})
        urllib.request.urlopen(req, timeout=20).read()
        print("ntfy: pushed")
    except Exception as e:  # noqa: BLE001
        print(f"ntfy: failed ({e}) — non-fatal")


def render(fails: dict[str, list[str]], n: int, new: set[str]) -> str:
    lines = ["# ตรวจของจริงบนช่อง — AERIS Music", "",
             f"ตรวจเมื่อ: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}",
             f"ตรวจ {n} วิดีโอ", ""]
    if not fails:
        lines.append("✅ ผ่านทุกข้อ — วิดีโอจริงตรงกับเจตนา (ลิงก์ + ปุ่มติดตาม + บท)")
    else:
        total = sum(len(v) for v in fails.values())
        lines.append(f"⚠️ พบ {total} ข้อบกพร่อง ใน {len(fails)} วิดีโอ")
        for vid, checks in sorted(fails.items()):
            for c in checks:
                flag = "🔴 ใหม่" if f"{vid}:{c}" in new else "  เดิม"
                lines.append(f"- {flag} {vid}: {c}")
    lines.append("")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repair", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-push", action="store_true")
    args = ap.parse_args(argv)

    exp = expected()
    comps = compilation_ids()
    try:
        items = read_live()
    except QuotaError as e:
        text = ("# ตรวจของจริงบนช่อง — AERIS Music\n\n"
                f"ตรวจเมื่อ: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n\n"
                f"⚠️ อ่านไม่ได้วันนี้: {e}\n\n"
                "quota หมด (รีเซ็ตเที่ยงคืน Pacific) — จะตรวจใหม่รอบถัดไป "
                "ไม่ถือว่าเป็นความผิดพลาดของช่อง\n")
        print(text)
        REPORT.write_text(text, encoding="utf-8")
        return 0
    except RuntimeError as e:
        # A non-quota read failure is a bug in this script, not a channel fault.
        # Fail loudly (red rail) instead of writing a reassuring "quota" note.
        text = ("# ตรวจของจริงบนช่อง — AERIS Music\n\n"
                f"ตรวจเมื่อ: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n\n"
                f"❌ ตรวจไม่ได้ (ข้อผิดพลาดของสคริปต์ ไม่ใช่ของช่อง): {e}\n")
        print(text)
        REPORT.write_text(text, encoding="utf-8")
        return 1

    fails: dict[str, list[str]] = {}
    for v in items:
        f = check_video(v, exp, comps)
        if f:
            fails[v["id"]] = f

    repaired = 0
    if args.repair:
        for v in items:
            if repaired >= MAX_REPAIRS:
                break
            if any(c in ("revenue_ask_missing", "subscribe_ask_missing")
                   for c in fails.get(v["id"], [])):
                if repair(v, exp):
                    repaired += 1
                    v["snippet"]["description"] = (monetize.cta("youtube") + "\n\n"
                                                   + v["snippet"].get("description", ""))

    # Recompute the misses that remain after any repair.
    fails = {v["id"]: check_video(v, exp, comps) for v in items}
    fails = {k: v for k, v in fails.items() if v}

    prev = load_prev_failures()
    cur = {f"{vid}:{c}" for vid, cs in fails.items() for c in cs}
    new = cur - prev

    text = render(fails, len(items), new)
    if args.json:
        print(json.dumps({"failing": sorted(cur), "checked": len(items),
                          "new": sorted(new)}, ensure_ascii=False))
    else:
        print(text)
    REPORT.write_text(text, encoding="utf-8")
    STATE.write_text(json.dumps({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                                 "failing": sorted(cur)}, ensure_ascii=False, indent=1),
                     encoding="utf-8")

    if new and not args.no_push:
        import os
        topic = os.environ.get("AX_NTFY_TOPIC", "")
        if topic:
            push(f"ตรวจของจริง: พบข้อบกพร่องใหม่ {len(new)} ข้อ — {sorted(new)[:3]}", topic)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

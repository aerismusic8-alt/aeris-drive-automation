#!/usr/bin/env python3
"""Read the numbers the Data API does not expose, over the signed-in desktop.

Why this exists
---------------
The ch3 token scope is `youtube` only, so the Analytics API answers 404 and the
headline facts -- impressions, CTR, watch-hours, where viewers came from, whether
anyone returns -- were unreadable. They are not secret; Studio has them. With the
desktop signed in (K, 2026-11-13) they can be scraped, and that is the free route:
no paid API, no extra scope.

`parse()` is pure (text -> dict) so it can be tested without a browser; `main()`
does the scraping. Numbers are Thai-formatted ("3.5 พัน"), so they are normalised:
พัน = 1e3, ล้าน = 1e6.

    python3 ops/studio_read.py            # scrape, save work/studio-<date>.json + .txt
"""
from __future__ import annotations

import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "aeris938-2" / "work"
CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"  # ch3 @aerismusith
CDP = "http://127.0.0.1:9222"
UNITS = {"พัน": 1_000, "ล้าน": 1_000_000}


def to_number(s: str) -> float:
    """'3.5 พัน' -> 3500.0 ; '23.5' -> 23.5 ; '+8' -> 8."""
    s = s.strip().replace(",", "").lstrip("+")
    m = re.match(r"^([\d.]+)\s*(พัน|ล้าน)?$", s)
    if not m:
        return 0.0
    return float(m.group(1)) * UNITS.get(m.group(2) or "", 1)


def _after(lines: list[str], label: str, n: int = 1) -> list[str]:
    for i, ln in enumerate(lines):
        if ln.strip() == label:
            return [x.strip() for x in lines[i + 1:i + 1 + n]]
    return []


def parse(text: str) -> dict:
    """Turn a Studio analytics page dump into named numbers."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    out: dict = {}

    subs = _after(lines, "ผู้ติดตามทั้งหมด", 1)
    if subs:
        out["subscribers"] = int(to_number(subs[0]))
    watch = _after(lines, "เวลาในการรับชม (ชั่วโมง)", 1)
    if watch:
        out["watch_hours_28d"] = to_number(watch[0])
    monthly = _after(lines, "ผู้ชมรายเดือน", 1)
    if monthly:
        out["monthly_viewers"] = int(to_number(monthly[0]))

    # Discovery: the three percentages right after the heading.
    disc = {}
    i = next((k for k, ln in enumerate(lines) if "วิธีที่ผู้ชมค้นพบ" in ln), -1)
    if i >= 0:
        pcts = [ln for ln in lines[i + 1:i + 9] if ln.endswith("%")]
        names = ["browse", "suggested", "channel_page", "search", "other",
                 "external", "playlists", "notifications"]
        for name, pct in zip(names, pcts):
            disc[name] = float(pct.rstrip("%"))
    out["discovery"] = disc

    # Returning vs new.
    ret = {}
    for key, label in (("new", "ผู้ชมใหม่"), ("casual", "ผู้ชมทั่วไป"),
                       ("regular", "ผู้ชมขาประจำ")):
        v = _after(lines, label, 1)
        if v:
            ret[key] = float(v[0].rstrip("%"))
    out["returning"] = ret

    top = []
    j = next((k for k, ln in enumerate(lines) if "เนื้อหายอดนิยม" in ln), -1)
    if j >= 0:
        for k in range(j + 1, min(j + 12, len(lines) - 1)):
            if lines[k].startswith("วิธีที่ผู้ชมค้นพบ"):
                break
            if re.match(r"^[\d,]+$", lines[k]):
                top.append({"title": lines[k - 1], "views": int(to_number(lines[k]))})
    out["top_content_28d"] = top[:5]
    return out


def scrape() -> tuple[str, dict]:
    from playwright.sync_api import sync_playwright  # imported late: not needed for parse()
    urls = {
        "overview": f"https://studio.youtube.com/channel/{CHANNEL_ID}"
                    "/analytics/tab-overview/period-default",
        "reach": f"https://studio.youtube.com/channel/{CHANNEL_ID}"
                 "/analytics/tab-reach_content/period-default",
    }
    text = ""
    with sync_playwright() as p:
        ctx = p.chromium.connect_over_cdp(CDP).contexts[0]
        pg = ctx.new_page()
        for url in urls.values():
            pg.goto(url, wait_until="domcontentloaded", timeout=90000)
            pg.wait_for_timeout(9000)
            text += pg.inner_text("body") + "\n"
        # Studio is signed in as K's account only if this did not bounce.
        if "signin" in pg.url and "accounts.google.com" in pg.url:
            raise SystemExit("Studio bounced to the sign-in wall; run check_login")
    return text, parse(text)


def main() -> int:
    text, data = scrape()
    stamp = date.today().isoformat()
    (WORK / f"studio-{stamp}.txt").write_text(text, encoding="utf-8")
    (WORK / f"studio-{stamp}.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(data, ensure_ascii=False, indent=1))
    print(f"\nsaved -> {WORK}/studio-{stamp}.txt + .json")
    return 0


if __name__ == "__main__":
    sys.exit(main())

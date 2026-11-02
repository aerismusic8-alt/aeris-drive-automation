#!/usr/bin/env python3
"""Write one page that answers "is the system running and moving?" for K.

Reads only files that already exist (the market snapshot, the release and
crosspost ledgers, the playlist state) and writes `channel/PROGRESS.md`. No
network, no browser, no secrets: it is the summariser, so it can run anywhere —
including a GitHub Actions job with nothing but a checkout.

Run:  python3 music938-1/scripts/progress.py --root .
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path


def load(path: Path, default):
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return default


def counts_by_platform(queue: list) -> dict:
    out: dict[str, int] = {}
    for it in queue:
        p = it.get("platform", "?")
        out[p] = out.get(p, 0) + 1
    return out


def posted_by_platform(state: dict) -> dict:
    out: dict[str, int] = {}
    for key in (state.get("posted") or {}):
        p = key.split(":", 1)[0]
        out[p] = out.get(p, 0) + 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    work = root / "music938-1" / "work"
    if not work.is_dir():
        work = root / "work"

    snap = load(work / "market-snapshot.json", {})
    rel = load(work / "release-state.json", {})
    cross = load(work / "crosspost-state.json", {})
    queue = load(work / "crosspost-queue.json", [])
    pl = load(work / "playlist-state.json", {})

    cs = snap.get("channel_stats", {})
    released = rel.get("released", []) if isinstance(rel, dict) else []
    by_kind: dict[str, int] = {}
    for r in released:
        k = r.get("kind", "?")
        by_kind[k] = by_kind.get(k, 0) + 1
    posted = posted_by_platform(cross)
    pending = counts_by_platform(queue)

    subs = cs.get("subs", "?")
    views = cs.get("views", "?")
    videos = cs.get("videos", "?")

    def bar(v, goal):
        try:
            pct = min(100, int(float(v) / goal * 100))
        except Exception:
            return "?"
        n = max(0, pct // 5)
        return f"{'#' * n}{'.' * (20 - n)} {pct}%"

    lines = [
        "# AERIS Music — ความคืบหน้า (อัตโนมัติ)",
        "",
        f"อัพเดท: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}",
        "",
        "## เป้าหมาย monetize",
        f"- ผู้ติดตาม: {subs} / 1,000   [{bar(subs, 1000)}]",
        f"- ยอดดูรวม: {views}",
        f"- วิดีโอทั้งหมด: {videos}",
        "",
        "## ระบบที่รันอัตโนมัติ (GitHub Actions, ไม่ใช้ sandbox)",
        "- `ax-music-release` 07:00Z — ปล่อย 6 คลิป/วัน (ตั้งเวลา public กระจาย)",
        "- `ax-rail-watchdog` ทุกชั่วโมง — เฝ้า 4 ช่อง + เตือน ntfy",
        "- `ax-music-dashboard` 07:20Z — เขียนหน้านี้ + รายงาน",
        "",
        "## เนื้อหาที่ปล่อยแล้ว (ledger)",
        f"- รวม {len(released)} รายการ: "
        + ", ".join(f"{k}={v}" for k, v in sorted(by_kind.items())),
        f"- เพลย์ลิสต์: {', '.join(f'{k}={v}' for k, v in pl.items()) or '(ยังไม่มี)'}",
        "",
        "## ครอสโพสต์",
        "- โพสต์แล้ว: " + (", ".join(f"{k}={v}" for k, v in sorted(posted.items())) or "0"),
        "- คิวคงเหลือ: " + (", ".join(f"{k}={v}" for k, v in sorted(pending.items())) or "0"),
        "",
        "## หมายเหตุ",
        "- ตัวเลขจาก YouTube Data API (subs/views/likes/comments).",
        "- ชั่วโมงรับชม/retention ต้องใช้ YouTube Analytics API (token ยังไม่มี scope นี้).",
        "- งานที่ต้องล็อกอิน (ตอบเม้น FB/TikTok, แลกติดตาม) ต้องมี session ของ K.",
        "",
    ]
    out = root / "music938-1" / "channel" / "PROGRESS.md"
    if not (root / "music938-1" / "channel").is_dir():
        out = root / "channel" / "PROGRESS.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {out}")
    print(f"subs={subs} views={views} videos={videos} released={len(released)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

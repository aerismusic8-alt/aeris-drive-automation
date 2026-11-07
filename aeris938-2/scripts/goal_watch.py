#!/usr/bin/env python3
"""Watch the $500 goal daily and name the one constraint that is blocking it.

`report.py` measures; this judges. It reads the history the daily dashboard
writes and answers the only question that matters each day: *what is stopping
revenue right now, and what changes next.* It runs on the same free GitHub
Actions rail as the dashboard, so it never depends on a sandbox being alive.

K's standing rule (2026-11-07): do every free thing, watch it, improve until it
works — missing the month is fine, the next month continues. So this exits 0
even when the news is bad; it is a monitor, not a gate.

    python3 scripts/goal_watch.py            # print the digest, write the file
    python3 scripts/goal_watch.py --no-push  # skip the ntfy alert
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import surfaces  # noqa: E402
import report  # noqa: E402

WATCH = surfaces.WORK / "goal-watch.md"
WINDOW_DAYS = 7.0


def load(path: Path | None = None) -> list[dict]:
    p = path or report.HISTORY
    if not p.exists():
        return []
    rows = []
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def _at(row: dict) -> datetime | None:
    try:
        return datetime.fromisoformat(str(row["at"]).replace("Z", "+00:00"))
    except Exception:  # noqa: BLE001
        return None


def window_delta(rows: list[dict], key: str, days: float = WINDOW_DAYS):
    """Change in `key` over the last `days`, as (delta, span_days) or None.

    The oldest reading at least `days` old is the baseline, so a gap in the
    schedule does not shrink the window and a fresh channel with two hours of
    history does not pretend to a week of movement.
    """
    pts = [( _at(r), r.get(key)) for r in rows
           if isinstance(r.get(key), (int, float)) and _at(r) is not None]
    if len(pts) < 2:
        return None
    latest_at, latest_v = pts[-1]
    base = pts[0]
    for at, v in pts:
        if (latest_at - at).total_seconds() >= days * 86400:
            base = (at, v)
            break
    span = (latest_at - base[0]).total_seconds() / 86400.0
    return latest_v - base[1], span


def diagnose(rows: list[dict]) -> dict:
    """Name the constraint blocking revenue, from the movement that is real.

    Order matters. Money first: a commission is the goal met, whatever else is
    flat. Then the reach question — no views means nothing downstream can work.
    Then the conversion question — views but no followers means the hook does
    not earn the follow. Only then is it a posting problem.
    """
    latest = rows[-1] if rows else {}
    subs = latest.get("yt_subs")
    tkf = latest.get("tk_followers")
    comm = latest.get("sp_commission")
    d_comm = window_delta(rows, "sp_commission")
    d_views = window_delta(rows, "yt_views")
    d_subs = window_delta(rows, "yt_subs")
    d_tkf = window_delta(rows, "tk_followers")
    d_clicks = window_delta(rows, "sp_clicks")

    # The gate that is furthest from open is the channel to push.
    gates = {}
    if isinstance(subs, (int, float)):
        gates["youtube"] = subs / report.YT_GATE_SUBS
    if isinstance(tkf, (int, float)):
        gates["tiktok"] = tkf / report.TT_GATE_FOLLOWERS
    gate = min(gates, key=gates.get) if gates else None

    if d_comm and d_comm[0] > 0:
        constraint, action = "income", "มีค่าคอมแล้ว — เพิ่มปริมาณคลิกที่แปลงได้"
    elif not d_views or d_views[0] <= 0:
        constraint = "reach"
        action = ("reach ไม่ขยับ (ยอดดูไม่โต): คลิปไม่ถูกมองเห็น — "
                  "เปลี่ยนฟอร์แมต/hook และยืนยันว่าโพสต์ออกจริง")
    elif d_subs is not None and d_views[0] > 0 and d_subs[0] == 0:
        constraint = "conversion"
        action = ("มี reach แต่ไม่มีคนติดตาม: hook/เหตุผลติดตามยังไม่พอ — "
                  "นำด้วยเนื้อเพลงร้องตาม + ซีรีส์ประจำ")
    elif d_clicks is not None and d_clicks[0] == 0:
        constraint = "offer"
        action = ("มีคนดูแต่ไม่มีคลิก: ลิงก์/สินค้ายังไม่ตรง — "
                  "การ์ดสินค้าต้องตรงกับคนฟังเพลง")
    else:
        constraint, action = "mixed", "ขยับทุกทางต่อ — วัดผู้ติดตามต่อ 1,000 วิว"

    return {
        "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "constraint": constraint,
        "action": action,
        "gate": gate,
        "yt_subs": subs, "tk_followers": tkf, "commission": comm,
        "d_views": d_views, "d_subs": d_subs, "d_tkf": d_tkf,
        "d_comm": d_comm, "d_clicks": d_clicks,
    }


def render(d: dict) -> str:
    """A Thai digest: the goal, the gap, and the one thing to change."""
    def fmt(delta):
        if not delta:
            return "ยังไม่มีข้อมูลพอ"
        v, span = delta
        sign = "+" if v > 0 else ""
        return f"{sign}{v:g} ใน {span:.1f} วัน"

    comm = d.get("commission")
    comm_s = f"฿{comm:,.2f}" if isinstance(comm, (int, float)) else "UNKNOWN"
    lines = [
        "# เฝ้าเป้า $500 — AERIS Music",
        "",
        f"ตรวจเมื่อ: {d['at']}",
        "",
        f"- ค่าคอมสะสม: {comm_s} (เป้า ฿16,780)",
        f"- YouTube ซับ: {d.get('yt_subs')} / 1,000 — {fmt(d.get('d_subs'))}",
        f"- TikTok ผู้ติดตาม: {d.get('tk_followers')} / 1,000 — {fmt(d.get('d_tkf'))}",
        f"- ยอดดู YouTube: {fmt(d.get('d_views'))}",
        f"- คลิก Shopee: {fmt(d.get('d_clicks'))}",
        "",
        f"**คอขวด: {d['constraint']}** — {d['action']}",
        "",
        "K รับได้ถ้าเดือนนี้ไม่ถึง — ขอแค่ทำเต็มที่ เฝ้าดู และปรับทุกวัน",
        "",
    ]
    return "\n".join(lines)


def headline(d: dict) -> str:
    comm = d.get("commission")
    comm_s = f"฿{comm:,.0f}" if isinstance(comm, (int, float)) else "?"
    return (f"เป้า $500 | ค่าคอม {comm_s} | YT {d.get('yt_subs')}/1000 "
            f"TK {d.get('tk_followers')}/1000 | คอขวด: {d['constraint']}")


def push(text: str, topic: str) -> None:
    body = text.encode("utf-8")
    req = urllib.request.Request(
        f"https://ntfy.sh/{topic}", data=body,
        headers={"Title": "AERIS Music — เฝ้าเป้า", "Tags": "dart"})
    try:
        urllib.request.urlopen(req, timeout=20).read()
        print("ntfy: pushed")
    except Exception as e:  # noqa: BLE001
        print(f"ntfy: failed ({e}) — non-fatal")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--no-push", action="store_true")
    args = ap.parse_args(argv)

    rows = load()
    d = diagnose(rows)
    text = render(d)
    WATCH.write_text(text, encoding="utf-8")
    print(text)
    print(headline(d))
    if not args.no_push:
        topic = os.environ.get("AX_NTFY_TOPIC", "")
        if topic:
            push(headline(d), topic)
        else:
            print("no AX_NTFY_TOPIC set — skipping push")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

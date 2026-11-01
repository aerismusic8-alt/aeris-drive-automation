#!/usr/bin/env python3
"""AR's daily admin pass for AERIS Music, across every surface.

K asked AR to administer the whole channel: YouTube, Facebook, TikTok and the
Shopee link. The cron rails already cover what needs no browser (`AX Music Daily
Release`, `AX Music Market Daily`, `AX YouTube Activity Monitor`, the weekly
strategy pass). What is left is the work that needs a signed-in browser, and this
is the single command that does all of it:

  1. bring the cloud desktop up if it is not already,
  2. answer every open comment in YouTube Studio,
  3. record the channel's analytics numbers,
  4. cross-post the pending Shorts to Facebook Reels and TikTok,
  5. write `work/desk-report.md` — a Thai summary of what happened.

It needs the desktop, so it runs inside a session, not from a cron. Run it once
per session; every step is idempotent and skips what is already done.

    python3 scripts/desk_daily.py                 # the whole pass
    python3 scripts/desk_daily.py --limit 2       # cap cross-posts this run
    python3 scripts/desk_daily.py --no-crosspost  # comments + analytics only
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
sys.path.insert(0, str(ROOT / "scripts"))

REPORT = ROOT / "work" / "desk-report.md"
BOOTSTRAP = REPO / ".agents" / "skills" / "ax-cloud-desktop" / "scripts" / "bootstrap.py"


def run(cmd: list[str], timeout: int = 900) -> tuple[int, str]:
    print(f"$ {' '.join(cmd)}", flush=True)
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    out = (p.stdout or "") + (p.stderr or "")
    print(out.strip()[-1500:], flush=True)
    return p.returncode, out


def desktop_up() -> bool:
    rc, out = run([sys.executable, str(BOOTSTRAP), "--status"], timeout=120)
    return rc == 0 and "UP" in out and "chromium" in out.lower()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=3, help="max cross-posts this run")
    ap.add_argument("--no-crosspost", action="store_true")
    args = ap.parse_args()

    lines = [f"# รายงาน AR — AERIS Music", "",
             f"เวลา: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}", ""]

    if not desktop_up():
        rc, out = run([sys.executable, str(BOOTSTRAP)], timeout=600)
        if not desktop_up():
            lines += ["## สถานะ", "", "เดสก์ท็อปไม่ขึ้น — ต้องให้ K ช่วยตรวจสอบ", ""]
            REPORT.write_text("\n".join(lines), encoding="utf-8")
            print("desktop is down; wrote report", file=sys.stderr)
            return 1
    lines += ["## เดสก์ท็อป", "", "ทำงานปกติ (ลงชื่อเข้าใช้แล้ว)", ""]

    # 1. comments -------------------------------------------------------------
    rc, out = run([sys.executable, str(ROOT / "scripts" / "studio_web.py"), "reply",
                   "--limit", "10"], timeout=900)
    replied = out.strip().splitlines()[-1] if out.strip() else "?"
    lines += ["## ความคิดเห็น", "", f"ตอบกลับ: {replied}", ""]

    # 2. analytics ------------------------------------------------------------
    rc, out = run([sys.executable, str(ROOT / "scripts" / "studio_web.py"),
                   "analytics"], timeout=600)
    views = ""
    for line in out.splitlines():
        if "views_line" in line:
            views = line.split(":", 1)[-1].strip().strip('",')
    lines += ["## ข้อมูลวิเคราะห์", "", views or "(อ่านไม่ได้ในรอบนี้)", ""]

    # 3. cross-post -----------------------------------------------------------
    if args.no_crosspost:
        lines += ["## ครอสโพสต์", "", "ข้ามในรอบนี้ (--no-crosspost)", ""]
    else:
        for platform in ("facebook", "tiktok"):
            rc, out = run([sys.executable, str(ROOT / "scripts" / "crosspost.py"),
                           "--post", "--platform", platform, "--limit", str(args.limit)],
                          timeout=1800)
            tail = out.strip().splitlines()[-1] if out.strip() else "?"
            lines += [f"### {platform}", "", tail, ""]

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nwrote {REPORT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

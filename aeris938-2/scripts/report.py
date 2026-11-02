#!/usr/bin/env python3
"""Read all four surfaces and write `work/growth-report.md`.

`grow.py` acts; this measures. It is the one place that answers "did the four
surfaces move?" — the question K's scope is about.

  * YouTube (@aerismusicth) reads from the Data API, so it always works.
  * Facebook / TikTok / Shopee report only inside their own dashboards, behind
    the signed-in desktop, so those are read through `social_stats.py` (CDP). If
    the desktop is down, the surface is written `UNKNOWN` — never guessed.

    python3 report.py            # measure and write work/growth-report.md
    python3 report.py --json     # machine-readable to stdout
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import surfaces

REPORT = surfaces.WORK / "growth-report.md"
YT = surfaces.OPS / "yt_auth.py"


def youtube_stats() -> dict:
    """Subs, videos and views for the one channel this project grows."""
    token = surfaces.config()["youtube"].get("token", "ch3")
    sys.path.insert(0, str(surfaces.OPS))
    import yt_auth  # noqa: E402  (path is set just above)

    tok = yt_auth.access_token(token)
    url = f"{yt_auth.API}/channels?" + urllib.parse.urlencode(
        {"part": "statistics,snippet", "mine": "true"})
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        item = json.load(r)["items"][0]
    st = item["statistics"]
    return {
        "reachable": True,
        "handle": surfaces.config()["youtube"]["handle"],
        "title": item["snippet"]["title"],
        "subs": int(st.get("subscriberCount", 0)),
        "videos": int(st.get("videoCount", 0)),
        "views": int(st.get("viewCount", 0)),
    }


def dashboard_stats() -> dict:
    """FB/TikTok/Shopee via social_stats.py (needs the cloud desktop)."""
    tool = surfaces.tool("social_stats.py")
    try:
        out = subprocess.run([sys.executable, str(tool), "--json"],
                             cwd=str(surfaces.MUSIC), capture_output=True,
                             text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return {"_error": "social_stats timed out"}
    if out.returncode != 0:
        return {"_error": (out.stderr or "social_stats failed").strip()[:300]}
    try:
        return json.loads(out.stdout)
    except ValueError:
        return {"_error": "social_stats returned no JSON (desktop/CDP unavailable?)"}


def _cell(d: dict | None, key: str) -> str:
    if not d or not d.get("reachable"):
        return "UNKNOWN"
    v = d.get(key, "UNKNOWN")
    return "UNKNOWN" if v is None else str(v)


def render(yt: dict, dash: dict) -> str:
    fb = dash.get("facebook") or {}
    tk = dash.get("tiktok") or {}
    sp = dash.get("shopee") or {}
    err = dash.get("_error")
    lines = [
        "# รายงานการปั้น 4 ช่องทาง — AERIS Music (aeris938-2)", "",
        f"วัดเมื่อ: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}", "",
        "> ตัวเลขที่อ่านไม่ได้เขียน UNKNOWN — ไม่เดา", "",
    ]
    if err:
        lines += [f"> หมายเหตุ: อ่าน FB/TikTok/Shopee ไม่ได้ ({err}) — "
                  "YouTube ยังอ่านได้ตามปกติ", ""]
    lines += [
        "| # | ช่องทาง | ตัวชี้วัด | ค่า |", "| ---: | --- | --- | ---: |",
        f"| 3 | YouTube {yt.get('handle', '')} | ผู้ติดตาม | "
        f"{yt.get('subs', 'UNKNOWN')} |",
        f"| | | วิดีโอ | {yt.get('videos', 'UNKNOWN')} |",
        f"| | | ยอดดูรวม | {yt.get('views', 'UNKNOWN')} |",
        f"| 1 | Facebook | ผู้ติดตาม | {_cell(fb, 'followers')} |",
        f"| | | ยอดดู 28 วัน | {_cell(fb, 'views_28d')} |",
        f"| 2 | TikTok | ผู้ติดตาม | {_cell(tk, 'followers_total')} |",
        f"| | | ยอดดู 7 วัน | {_cell(tk, 'views_7d')} |",
        f"| 4 | Shopee | คำสั่งซื้อ | {_cell(sp, 'orders')} |",
        f"| | | ค่าคอมมิชชั่น | {_cell(sp, 'commission')} |",
        "",
    ]
    if sp and not sp.get("reachable"):
        lines += [f"**Shopee:** {sp.get('note', 'อ่านไม่ได้')} "
                  "(ต้อง sign in บนเดสก์ท็อป)", ""]
    elif sp.get("reachable"):
        cfg = surfaces.config()["shopee_affiliate"]
        links = cfg.get("links") or {}
        lines += [
            "## Shopee Affiliate (onboarded)",
            "",
            f"บัญชี: `{cfg.get('account', 'UNKNOWN')}` — "
            "ลิงก์ติดตามต่อผิว (Sub_id) ใช้งานได้:",
            "",
        ]
        for surf, url in links.items():
            lines.append(f"- {surf}: {url}")
        lines.append("")
    lines += [
        "## เป้าหมาย (GOAL.md)", "",
        "- YouTube: 1,000 ซับ + 4,000 ชม. → เปิด monetization",
        "- Facebook / TikTok: ผู้ติดตาม > 0, มียอดดู",
        "- Shopee: คำสั่งซื้อ > 0, ค่าคอมมิชชั่น > 0",
        "",
    ]
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    try:
        yt = youtube_stats()
    except Exception as exc:  # noqa: BLE001
        yt = {"reachable": False, "error": str(exc)[:200]}
    dash = dashboard_stats()

    if args.json:
        print(json.dumps({"youtube": yt, "dashboards": dash},
                         ensure_ascii=False, indent=1))
        return 0
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(render(yt, dash), encoding="utf-8")
    print(f"wrote {REPORT.relative_to(surfaces.REPO)}")
    print(f"YouTube {yt.get('handle','')}: {yt.get('subs','UNKNOWN')} subs, "
          f"{yt.get('views','UNKNOWN')} views")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

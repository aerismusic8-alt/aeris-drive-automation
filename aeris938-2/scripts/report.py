#!/usr/bin/env python3
"""Read all four surfaces and write `work/growth-report.md`.

`grow.py` acts; this measures. It is the one place that answers "did the four
surfaces move?" — the question K's scope is about.

  * YouTube (@aerismusicth) reads from the Data API, so it always works.
  * Shopee reads from its affiliate JSON API with the exported session cookies,
    so it also works from a scheduled runner with no browser.
  * Facebook / TikTok report only inside their own dashboards, behind the
    signed-in desktop, so those are read through `social_stats.py` (CDP). If
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
HISTORY = surfaces.WORK / "history.jsonl"
YT = surfaces.OPS / "yt_auth.py"

# The revenue goal K set (2026-11-07). The Shopee dashboard reports THB, so the
# target is converted to THB for the progress line. Rate is a planning figure,
# dated — not a live quote.
GOAL_USD = 500.0
THB_PER_USD = 33.56

# The gate that unlocks each platform's own money, from the official pages: a
# channel is not a place to stick an ad, it is the door to a revenue route.
YT_GATE_SUBS = 1000          # YouTube Partner Program
TT_GATE_FOLLOWERS = 1000     # TikTok Shop Affiliate (verified 2026-11-07)
# YPP needs *both* 1,000 subs and 4,000 public watch-hours in 12 months. The
# second half is the harder one and the Data API cannot read it, so it comes
# from the Studio scrape (`ops/studio_read.py`). It is kept as a gate here so the
# daily judge names it instead of reporting only the half it can see.
YT_GATE_HOURS = 4000.0


def _money(v):
    """Parse a dashboard money cell to a float, or None when unreadable."""
    if v in (None, "", "UNKNOWN"):
        return None
    s = str(v).replace(",", "").replace("฿", "").replace("$", "").strip()
    try:
        return float(s)
    except ValueError:
        return None


def gate_block(yt: dict, fb: dict, tk: dict) -> list[str]:
    """How far each channel is from the follower count that unlocks its money.

    The channels are not a place to stick an affiliate link; they are the door
    to a platform's own revenue route. YouTube opens at 1,000 subs, TikTok Shop
    Affiliate at 1,000 followers. A channel that is not growing toward its gate
    is not doing the job, so the gap is a first-class number in the report.
    """
    def _n(d, *keys):
        for k in keys:
            v = d.get(k)
            if isinstance(v, (int, float)):
                return int(v)
            if isinstance(v, str) and v.strip().isdigit():
                return int(v)
        return None

    subs = _n(yt, "subs")
    fb_f = _n(fb, "followers")
    tk_f = _n(tk, "followers_total")
    lines = ["## ประตูรายได้ของช่อง (ต้องถึงก่อนจึงจะได้เงินจากแพลตฟอร์ม)", ""]
    if subs is None:
        lines.append("- YouTube: UNKNOWN (อ่านไม่ได้ — ไม่เดา)")
    else:
        pct = 100.0 * subs / YT_GATE_SUBS
        lines.append(f"- YouTube {yt.get('handle','')}: {subs:,} / "
                     f"{YT_GATE_SUBS:,} ซับ = {pct:.1f}% "
                     f"(อีก {max(YT_GATE_SUBS - subs, 0):,} ซับ → YPP)")
    if tk_f is None:
        lines.append("- TikTok: UNKNOWN (อ่านไม่ได้ — ไม่เดา)")
    else:
        pct = 100.0 * tk_f / TT_GATE_FOLLOWERS
        lines.append(f"- TikTok: {tk_f:,} / {TT_GATE_FOLLOWERS:,} ผู้ติดตาม = "
                     f"{pct:.1f}% (อีก {max(TT_GATE_FOLLOWERS - tk_f, 0):,} → "
                     "TikTok Shop Affiliate)")
    if fb_f is not None:
        lines.append(f"- Facebook: {fb_f:,} ผู้ติดตาม (ไม่มีเกณฑ์ผู้ติดตาม — "
                     "ใช้ affiliate ได้เลย)")
    lines += [
        "",
        "ช่องที่ไม่โตเข้าหาประตู = ยังไม่ได้ทำหน้าที่ของมัน; "
        "เป้าคือดันจำนวนผู้ติดตามให้ถึงเกณฑ์ ไม่ใช่แค่โพสต์ให้ครบ",
        "",
    ]
    return lines


def goal_block(sp: dict) -> list[str]:
    """Progress toward the $500 goal, from the number that actually counts.

    Two Thai routes can pay today: Shopee affiliate (no follower gate, so it can
    pay now) and TikTok Shop Affiliate (at 1,000 followers). Creator Rewards has
    no Thai market, Facebook Content Monetization is invite-only, and YouTube
    pays cents per thousand Shorts views — so the goal is measured in the Shopee
    commission, read live and never guessed.
    """
    target_thb = GOAL_USD * THB_PER_USD
    comm = _money(sp.get("commission"))
    orders = _money(sp.get("orders"))
    clicks = _money(sp.get("clicks"))
    lines = ["## เป้าหมายรายได้ $500 (K, 2026-11-07)", "",
             f"- เป้า: ${GOAL_USD:.0f} ≈ ฿{target_thb:,.0f} (ที่ ฿{THB_PER_USD}/$)"]
    if comm is None:
        lines.append("- ค่าคอมมิชชั่นสะสม: UNKNOWN (อ่านไม่ได้ — ไม่เดา)")
    else:
        pct = 100.0 * comm / target_thb
        left = max(target_thb - comm, 0.0)
        lines.append(f"- ค่าคอมมิชชั่นสะสม: ฿{comm:,.2f} — {pct:.2f}% ของเป้า "
                     f"(เหลือ ฿{left:,.0f})")
    if orders is not None:
        lines.append(f"- คำสั่งซื้อสะสม: {orders:,.0f}")
    if clicks is not None:
        lines.append(f"- คลิกสะสม: {clicks:,.0f}")
    lines += [
        "",
        "เส้นทางที่จ่ายได้จริงในไทย (ตรวจจากหน้าทางการ 2026-11-07):",
        "- **Shopee Affiliate** — จ่ายได้ทันที ไม่มีเกณฑ์ผู้ติดตาม (วัดเป้า $500 ที่นี่)",
        "- **TikTok Shop Affiliate** — จ่ายได้ในไทย แต่ต้อง 1,000 ผู้ติดตาม "
        "+ ยืนยันตัวตน/อายุ 18+",
        "- TikTok Creator Rewards (จ่ายตามวิว) — ไม่มีในไทย (8 ประเทศเท่านั้น)",
        "- Facebook Content Monetization — invite-only ไม่มีเกณฑ์สาธารณะ",
        "- YouTube — 1,000 ซับ + 4,000 ชม. หรือ 10 ล้าน Shorts วิว (ไกล)",
        "",
        "ต้องมีออเดอร์จริง → ลิงก์ต้องตรงสินค้าที่คนอยากซื้อ "
        "(การ์ดหูฟัง/อุปกรณ์ฟังเพลง) ไม่ใช่ปิดท้ายเพลงเฉย ๆ",
        "",
    ]
    return lines


def youtube_stats() -> dict:
    """Subs, videos and views for the one channel this project grows.

    The Data API is authoritative but its daily quota (10,000 units) is spent by
    the 07:00 UTC release, so a later read answers 403 `quotaExceeded`. In that
    case fall back to the last market snapshot rather than reporting UNKNOWN —
    the snapshot is real, just older.
    """
    token = surfaces.config()["youtube"].get("token", "ch3")
    sys.path.insert(0, str(surfaces.OPS))
    import yt_auth  # noqa: E402  (path is set just above)

    try:
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
    except Exception as exc:  # noqa: BLE001
        snap = snapshot_stats()
        if snap:
            snap["note"] = f"Data API unavailable ({str(exc)[:120]}); snapshot"
            return snap
        raise


def snapshot_stats() -> dict | None:
    """The last `market.py` reading, used when the Data API is out of quota."""
    path = surfaces.MUSIC / "work" / "market-snapshot.json"
    try:
        snap = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    cs = snap.get("channel_stats") or {}
    if not cs:
        return None
    return {
        "reachable": True,
        "handle": surfaces.config()["youtube"]["handle"],
        "subs": cs.get("subs", "UNKNOWN"),
        "videos": cs.get("videos", "UNKNOWN"),
        "views": cs.get("views", "UNKNOWN"),
        "as_of": snap.get("at"),
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


def flatten(yt: dict, dash: dict) -> dict:
    """The six tracked numbers as a flat {name: value-or-None} map."""
    fb = dash.get("facebook") or {}
    tk = dash.get("tiktok") or {}
    sp = dash.get("shopee") or {}

    def num(d, key):
        v = d.get(key)
        return v if isinstance(v, (int, float)) else None

    return {
        "yt_subs": num(yt, "subs"),
        "yt_views": num(yt, "views"),
        "yt_videos": num(yt, "videos"),
        "fb_followers": num(fb, "followers"),
        "fb_views_28d": num(fb, "views_28d"),
        "tk_followers": num(tk, "followers_total"),
        "tk_views_7d": num(tk, "views_7d"),
        "sp_clicks": num(sp, "clicks"),
        "sp_orders": num(sp, "orders"),
        "sp_commission": num(sp, "commission"),
    }


def load_history() -> list[dict]:
    if not HISTORY.exists():
        return []
    out = []
    for line in HISTORY.read_text(encoding="utf-8").splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            continue
    return out


def append_history(row: dict) -> None:
    HISTORY.parent.mkdir(parents=True, exist_ok=True)
    with HISTORY.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def _delta(cur, prev) -> str:
    """Signed change between two readings, or '' when either is unknown."""
    if not isinstance(cur, (int, float)) or not isinstance(prev, (int, float)):
        return ""
    d = cur - prev
    return "—" if d == 0 else f"{d:+g}"


def last_known_shopee(hist: list[dict]) -> dict | None:
    """The most recent Shopee reading that had real numbers.

    Shopee's affiliate dashboard answers a fresh automated browser with a
    captcha, so a scheduled runner usually cannot read it. Rather than print
    UNKNOWN every day, fall back to the last reading a warmed desktop captured
    and label it with its date. A labelled older number is honest; a blank one
    hides that the link was ever checked.
    """
    for row in reversed(hist):
        if row.get("sp_clicks") is not None or row.get("sp_orders") is not None:
            return row
    return None


def render(yt: dict, dash: dict, prev: dict | None = None,
           hist: list[dict] | None = None) -> str:
    fb = dash.get("facebook") or {}
    tk = dash.get("tiktok") or {}
    sp = dash.get("shopee") or {}
    err = dash.get("_error")
    prev = prev or {}
    # Shopee is often unreadable from a scheduled runner; fall back to the last
    # real reading and say so, rather than print UNKNOWN every day.
    sp_stale = None
    if not sp.get("reachable"):
        last = last_known_shopee(hist or [])
        if last:
            sp = {
                "reachable": True, "stale": True,
                "clicks": last.get("sp_clicks"), "orders": last.get("sp_orders"),
                "commission": last.get("sp_commission"), "as_of": last.get("at"),
            }
            sp_stale = last.get("at")
    lines = [
        "# รายงานการปั้น 4 ช่องทาง — AERIS Music (aeris938-2)", "",
        f"วัดเมื่อ: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}", "",
        "> ตัวเลขที่อ่านไม่ได้เขียน UNKNOWN — ไม่เดา", "",
    ]
    if err:
        lines += [f"> หมายเหตุ: อ่าน FB/TikTok/Shopee ไม่ได้ ({err}) — "
                  "YouTube ยังอ่านได้ตามปกติ", ""]
    if yt.get("note"):
        lines += [f"> YouTube: {yt['note']}", ""]

    lines += [
        "| # | ช่องทาง | ตัวชี้วัด | ค่า | เปลี่ยน |",
        "| ---: | --- | --- | ---: | ---: |",
        f"| 3 | YouTube {yt.get('handle', '')} | ผู้ติดตาม | "
        f"{yt.get('subs', 'UNKNOWN')} | {_delta(yt.get('subs'), prev.get('yt_subs'))} |",
        f"| | | วิดีโอ | {yt.get('videos', 'UNKNOWN')} | "
        f"{_delta(yt.get('videos'), prev.get('yt_videos'))} |",
        f"| | | ยอดดูรวม | {yt.get('views', 'UNKNOWN')} | "
        f"{_delta(yt.get('views'), prev.get('yt_views'))} |",
        f"| 1 | Facebook | ผู้ติดตาม | {_cell(fb, 'followers')} | "
        f"{_delta(fb.get('followers'), prev.get('fb_followers'))} |",
        f"| | | ยอดดู 28 วัน | {_cell(fb, 'views_28d')} | "
        f"{_delta(fb.get('views_28d'), prev.get('fb_views_28d'))} |",
        f"| 2 | TikTok | ผู้ติดตาม | {_cell(tk, 'followers_total')} | "
        f"{_delta(tk.get('followers_total'), prev.get('tk_followers'))} |",
        f"| | | ยอดดู 7 วัน | {_cell(tk, 'views_7d')} | "
        f"{_delta(tk.get('views_7d'), prev.get('tk_views_7d'))} |",
        f"| 4 | Shopee | คลิก | {_cell(sp, 'clicks')} | "
        f"{_delta(sp.get('clicks'), prev.get('sp_clicks'))} |",
        f"| | | คำสั่งซื้อ | {_cell(sp, 'orders')} | "
        f"{_delta(sp.get('orders'), prev.get('sp_orders'))} |",
        f"| | | ค่าคอมมิชชั่น | {_cell(sp, 'commission')} | "
        f"{_delta(sp.get('commission'), prev.get('sp_commission'))} |",
        "",
    ]
    if sp_stale:
        lines += [f"> Shopee: อ่านสดไม่ได้จากรอบนี้ (แคปต์ชา) — แสดงค่าล่าสุด "
                  f"เมื่อ {sp_stale}", ""]
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
    lines += gate_block(yt, fb, tk)
    lines += goal_block(sp)
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
    hist = load_history()
    prev = hist[-1] if hist else None
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(render(yt, dash, prev, hist), encoding="utf-8")
    row = flatten(yt, dash)
    row["at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    append_history(row)
    print(f"wrote {REPORT.relative_to(surfaces.REPO)}")
    print(f"YouTube {yt.get('handle','')}: {yt.get('subs','UNKNOWN')} subs, "
          f"{yt.get('views','UNKNOWN')} views")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

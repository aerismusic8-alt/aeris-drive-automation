#!/usr/bin/env python3
"""Measure the three non-YouTube surfaces and write `work/social-report.md`.

Why this exists: `market.py` measures YouTube from the Data API, so the daily
strategy loop could see the channel's growth on one platform out of four. The
other three report their numbers only inside their own dashboards, behind a
signed-in browser, and nobody was reading them — which is why the first record
of them (`channel/SOCIAL.md`) had to be collected by hand.

This does that pass by hand instead: it drives the signed-in cloud desktop to
each dashboard, reads what the dashboard shows, and writes a Thai report. A
number that cannot be read is written UNKNOWN. Nothing here guesses — a wrong
number is worse than an absent one, because the strategy pass would act on it.

    python3 scripts/social_stats.py            # measure and write the report
    python3 scripts/social_stats.py --json     # machine-readable to stdout
"""
from __future__ import annotations
import os

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / "work" / "social-report.md"
CDP = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222").rstrip("/") + "/json"

# The signed-in dashboards. Each is the page the owner sees, not a public page,
# so the numbers match what the platform reports to K.
# The Page-scoped entry points. `professional_dashboard/insights/` serves the
# numbers but has been seen to answer "Not Found" when navigated to cold, so the
# reader falls back to the Page profile, which always loads signed in and still
# carries the follower count.
FB_PAGE = "https://www.facebook.com/profile.php?id=61595890900382"
FB_INSIGHTS = "https://www.facebook.com/professional_dashboard/insights/"
TIKTOK_ANALYTICS = "https://www.tiktok.com/tiktokstudio/analytics"
SHOPEE_AFFILIATE = "https://affiliate.shopee.co.th/dashboard"


class Desk:
    """A minimal CDP client, in the shape studio_web.py already uses."""

    def __init__(self) -> None:
        import websocket  # noqa: PLC0415  (only needed on a live desktop)
        tabs = json.load(urllib.request.urlopen(CDP, timeout=20))
        page = next(t for t in tabs if t["type"] == "page")
        self.ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=40)
        self.n = 0
        # Chromium throttles a background tab and a lazily-rendered dashboard
        # then reports empty numbers instead of the real ones.
        self.send("Page.bringToFront")

    def send(self, method: str, params: dict | None = None) -> dict:
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                return msg

    def js(self, expr: str):
        r = self.send("Runtime.evaluate",
                      {"expression": expr, "returnByValue": True, "awaitPromise": True})
        return r.get("result", {}).get("result", {}).get("value")

    def goto(self, url: str, settle: float = 12.0) -> None:
        self.send("Page.navigate", {"url": url})
        time.sleep(settle)

    def text(self) -> str:
        return self.js("document.body.innerText") or ""

    def close(self) -> None:
        self.ws.close()


class PlaywrightDesk:
    """The same read interface as `Desk`, but on a browser this process owns.

    GitHub Actions has no cloud desktop to attach to, so the scheduled report
    launches its own headless Chromium and loads the saved session (the same
    `AERIS_STORAGE_STATE_B64` the crosspost rail uses). Every `measure_*`
    function takes a `desk`, so it does not care which one it is handed.
    """

    def __init__(self) -> None:
        import base64  # noqa: PLC0415
        import tempfile  # noqa: PLC0415
        from pathlib import Path  # noqa: PLC0415
        from playwright.sync_api import sync_playwright  # noqa: PLC0415
        b64 = os.environ.get("AERIS_STORAGE_STATE_B64")
        path = os.environ.get("AERIS_STORAGE_STATE")
        if b64 and not path:
            path = str(Path(tempfile.gettempdir()) / "aeris-storage-state.json")
        if b64 and not os.path.exists(path):
            Path(path).write_bytes(base64.b64decode(b64))
        self._pw = sync_playwright().start()
        kwargs = dict(headless=True, args=["--no-sandbox", "--disable-dev-shm-usage"])
        exe = os.environ.get("AERIS_CHROMIUM")
        if exe:
            kwargs["executable_path"] = exe
        self.browser = self._pw.chromium.launch(**kwargs)
        ctx = self.browser.new_context(
            storage_state=path, locale="th-TH",
            viewport={"width": 1280, "height": 900})
        self.page = ctx.new_page()

    def js(self, expr: str):
        return self.page.evaluate(expr)

    def goto(self, url: str, settle: float = 12.0) -> None:
        self.page.goto(url, wait_until="domcontentloaded", timeout=60_000)
        self.page.wait_for_timeout(int(settle * 1000))

    def text(self) -> str:
        return self.page.inner_text("body")

    def close(self) -> None:
        self.browser.close()
        self._pw.stop()


def open_desk():
    """A live cloud-desktop CDP client, or a headless one when running in CI."""
    if os.environ.get("AERIS_STORAGE_STATE_B64") or os.environ.get("AERIS_STORAGE_STATE"):
        return PlaywrightDesk()
    return Desk()


def _first_int(text: str, needles: list[str], lookahead: int = 3):
    """The first number near a line carrying one of `needles`, else UNKNOWN.

    Deliberately conservative: a dashboard is full of numbers, so a line must
    name the metric before any number near it is believed. The value often sits
    on a following line ("Video views" / "--" / "0"), so a few lines are scanned
    after the label as well as the label's own line. Decimals are returned as
    floats — commission and rewards are not whole numbers.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        low = line.lower()
        if any(n.lower() in low for n in needles):
            for cand in lines[i:i + 1 + lookahead]:
                for tok in cand.replace(",", "").split():
                    tok = tok.strip("()[]:·%฿$")
                    try:
                        num = float(tok)
                    except ValueError:
                        continue
                    return int(num) if num.is_integer() else num
    return "UNKNOWN"


def _followers(text: str):
    """The Page's follower total, from the "ผู้ติดตาม N คน" profile line.

    The insights page also contains "ผู้ติดตาม" — as a chart legend beside a
    share like "94.4%", and inside "ไม่ใช่ผู้ติดตาม" (non-followers) — so a plain
    "first number after the word" scan reports the percentage. Only the profile
    states a count with a unit.
    """
    import re
    m = re.search(r"ผู้ติดตาม\s*([\d,]+)\s*คน", text)
    if m:
        return int(m.group(1).replace(",", ""))
    return "UNKNOWN"


def _fb_signed_out(text: str) -> bool:
    """A signed-out Facebook shows the login form and no Page content.

    "เข้าสู่ระบบ" is in the page chrome even when signed in, so the test is the
    absence of the Page's own line ("ผู้ติดตาม N คน"), not the presence of the
    login word.
    """
    head = text[:400]
    return "เข้าสู่ระบบ" in head and "ผู้ติดตาม" not in text


def measure_facebook(desk: Desk) -> dict:
    """The Page numbers, from the insights dashboard with a profile fallback.

    Followers are always read from the Page profile line ("ผู้ติดตาม N คน"),
    because the insights page only states followers as a percentage of views.
    Views (28 days) come from insights.
    """
    # Land on the Page first: the insights route is reached from inside the Page
    # and answers "Not Found" when it is the first URL of a fresh tab.
    desk.goto(FB_PAGE, settle=14)
    profile = desk.text()
    if _fb_signed_out(profile):
        return {"reachable": False, "note": "not signed in"}
    followers = _followers(profile)

    desk.goto(FB_INSIGHTS, settle=16)
    t = desk.text()
    if "Not Found" in t[:200]:
        return {
            "reachable": True,
            "views_28d": "UNKNOWN",
            "followers": followers,
            "note": "insights route unavailable; followers read from the Page",
            "raw": t[:600],
        }
    return {
        "reachable": True,
        "views_28d": _first_int(t, ["ยอดดู", "views"]),
        "followers": followers,
        "raw": t[:600],
    }


def measure_tiktok(desk: Desk) -> dict:
    """Views from the analytics dashboard, total followers from the profile.

    The analytics "Followers" row is the *change* over the period (it reads 0
    while the profile shows 1), so it is not the total and must not be reported
    as one.
    """
    desk.goto(TIKTOK_ANALYTICS, settle=16)
    t = desk.text()
    if "เข้าสู่ระบบ" in t[:400] and "Video views" not in t:
        return {"reachable": False, "note": "not signed in"}
    # Under 100 followers TikTok shows the overview but not the detail; that is
    # itself the finding, so it is recorded rather than treated as an error.
    locked = "reach 100 followers" in t or "Get more insights" in t
    stats = {
        "reachable": True,
        "views_7d": _first_int(t, ["Video views", "ยอดดู"]),
        "followers_change_7d": _first_int(t, ["Followers", "ผู้ติดตาม"]),
        "detail_locked_under_100": locked,
    }
    desk.goto("https://www.tiktok.com/@aeris.music4", settle=12)
    p = desk.text()
    stats["followers_total"] = _first_int(p, ["Followers", "ผู้ติดตาม"])
    stats["raw"] = t[:600]
    return stats


def measure_shopee(desk: Desk) -> dict:
    desk.goto(SHOPEE_AFFILIATE, settle=14)
    t = desk.text()
    url = (desk.js("location.href") or "").lower()
    # `affiliate.shopee.co.th/dashboard` redirects to the public join page only
    # when nobody is signed in; the captcha interstitial is not that, so a
    # signed-in account reads its real numbers. The old check treated the
    # interstitial as "not onboarded" — a false negative.
    if "/login" in url or "เข้าร่วมเลย" in t or "ลงทะเบียนและเป็น Shopee Affiliate" in t:
        return {"reachable": False, "note": "not signed in / not onboarded"}
    # A fresh automated browser is served an anti-bot captcha ("Verify to
    # Continue" / "Drag the missing piece"), not the dashboard. It is not the
    # login page, so without this check it read as reachable with every metric
    # UNKNOWN — which then defeated the last-known fallback. Treat it as
    # unreachable so the caller can fall back to a real, dated reading.
    if "/verify/" in url or "Verify to Continue" in t or "ยืนยันเพื่อดำเนินการต่อ" in t:
        return {"reachable": False, "note": "anti-bot captcha (use the desktop)"}
    # Clicks lead orders by days-to-weeks (someone clicks a link long before they
    # buy), so on a channel with no orders yet the click count is the only number
    # that can move. Orders and commission are kept too — they are the goal — but
    # without clicks the report looks frozen even while the links are working.
    return {
        "reachable": True,
        "clicks": _first_int(t, ["Clicks", "คลิก"]),
        "orders": _first_int(t, ["คำสั่งซื้อ", "Orders"]),
        "commission": _first_int(t, ["ค่าคอมมิชชั่น", "Est. Commission", "commission"]),
        "items_sold": _first_int(t, ["Items Sold", "สินค้าที่ขายได้"]),
        "order_amount": _first_int(t, ["Order Amount", "ยอดคำสั่งซื้อ"]),
        "new_buyers": _first_int(t, ["New Buyers", "ผู้ซื้อใหม่"]),
        "raw": t[:600],
    }


def render(stats: dict) -> str:
    def cell(d: dict, key: str) -> str:
        if not d.get("reachable"):
            return "UNKNOWN"
        return str(d.get(key, "UNKNOWN"))

    lines = ["# รายงานโซเชียล — AERIS Music", "",
             f"วัดเมื่อ: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}", "",
             "> ตัวเลขที่อ่านไม่ได้เขียน UNKNOWN — ไม่เดา", "",
             "| ผิว | สถานะ | ตัวชี้วัด | ค่า |", "| --- | --- | --- | ---: |"]
    fb, tk, sp = stats["facebook"], stats["tiktok"], stats["shopee"]
    lines += [
        f"| Facebook | {'อ่านได้' if fb['reachable'] else 'อ่านไม่ได้'} "
        f"| ยอดดู 28 วัน | {cell(fb, 'views_28d')} |",
        f"| Facebook | | ผู้ติดตาม | {cell(fb, 'followers')} |",
        f"| TikTok | {'อ่านได้' if tk['reachable'] else 'อ่านไม่ได้'} "
        f"| ยอดดู 7 วัน | {cell(tk, 'views_7d')} |",
        f"| TikTok | | ผู้ติดตาม (รวม) | {cell(tk, 'followers_total')} |",
        f"| TikTok | | ผู้ติดตามเปลี่ยน 7 วัน | {cell(tk, 'followers_change_7d')} |",
        f"| Shopee | {'อ่านได้' if sp['reachable'] else 'อ่านไม่ได้'} "
        f"| คลิก | {cell(sp, 'clicks')} |",
        f"| Shopee | | คำสั่งซื้อ | {cell(sp, 'orders')} |",
        f"| Shopee | | ค่าคอมมิชชั่น | {cell(sp, 'commission')} |",
        "",
    ]
    for name, d in stats.items():
        if not d.get("reachable"):
            lines += [f"**{name}:** อ่านไม่ได้ — {d.get('note', 'ไม่ทราบสาเหตุ')}", ""]
    if tk.get("detail_locked_under_100"):
        lines += ["**TikTok:** รายละเอียดยังถูกล็อก (ต้องถึง 100 ผู้ติดตาม) "
                  "— ค่านี้เป็นเหตุผลหนึ่งที่ต้องไปให้ถึง 100", ""]
    lines += ["ดูบันทึกและปัญหาที่พบ: `channel/SOCIAL.md`", ""]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", action="store_true", help="print the numbers, write nothing")
    args = ap.parse_args()

    try:
        desk = open_desk()
    except Exception as exc:  # noqa: BLE001
        print(f"desktop/CDP unavailable: {exc}", file=sys.stderr)
        return 1
    try:
        stats = {
            "facebook": measure_facebook(desk),
            "tiktok": measure_tiktok(desk),
            "shopee": measure_shopee(desk),
        }
    finally:
        desk.close()

    if args.json:
        print(json.dumps(stats, ensure_ascii=False, indent=1))
        return 0
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(render(stats), encoding="utf-8")
    print(f"wrote {REPORT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

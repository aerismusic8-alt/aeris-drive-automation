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

Shopee is the exception. Its dashboard serves a `/verify/traffic/error`
interstitial to any fresh automated browser (headless or headed), but the JSON
report API behind it answers a plain HTTP request carrying the exported session
cookies. So Shopee is read from the API when a storage state is present, and only
falls back to the dashboard scrape otherwise.

    python3 scripts/social_stats.py            # measure and write the report
    python3 scripts/social_stats.py --json     # machine-readable to stdout
"""
from __future__ import annotations
import os
import re

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
FB_INSIGHTS = "https://www.facebook.com/professional_dashboard/profile_insights/views/"
FB_CONTENT = ("https://www.facebook.com/professional_dashboard/content/content_library/"
              "?date_range=LAST_28D&post_type=ALL_CONTENT&sort_by=VIEWS"
              "&sorting_method=METRICS_DESCENDING")
FB_PAGE_ID = "61595890900382"
TIKTOK_ANALYTICS = "https://www.tiktok.com/tiktokstudio/analytics"
SHOPEE_AFFILIATE = "https://affiliate.shopee.co.th/dashboard"
SHOPEE_AFFILIATE_API = "https://affiliate.shopee.co.th"


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


def _acting_as_page(text: str) -> bool:
    """True when the desktop is acting as the Page, not the person.

    The profile dashboard says "สถานะโปรไฟล์" and the switch banner
    ("สลับไปใช้เพจ") is present; the Page dashboard says neither. Reading the
    Page's insights while still acting as the person silently reports the
    *person's* numbers — that is how the Page looked like it had 0 views for
    four days when it really had 861 in 28 days.
    """
    head = text[:1500]
    if "สถานะโปรไฟล์" in head:
        return False
    return "สลับไปใช้เพจ" not in head


def _switch_to_page(desk) -> bool:
    """Make the Page the acting identity, and prove it stuck.

    Same three clicks `profile_setup` / `outreach` proved out: the profile
    switcher, "สลับ" in its menu, then "ใช้เพจ" in the welcome dialog. The banner
    click alone does not switch identity. `desk` may be the CDP client or the
    Playwright client; both expose `.page.evaluate` only for the latter, so the
    CDP client goes through `.js`.
    """
    page = getattr(desk, "page", None)
    run = page.evaluate if page is not None else desk.js
    if _acting_as_page(desk.text()):
        return True
    try:
        run("""() => {
          const b = document.querySelector('div[role=button][aria-label="สลับ"]');
          if (b) b.click();
        }""")
        time.sleep(3.5)
        run("""() => {
          for (const m of document.querySelectorAll('div[role=dialog]'))
            for (const el of m.querySelectorAll('div[role=button],a,span'))
              if ((el.innerText || '').trim() === 'สลับ') { el.click(); return; }
        }""")
        time.sleep(9)
        run("""() => {
          for (const d of document.querySelectorAll('div[role=dialog]'))
            for (const el of d.querySelectorAll('div[role=button],a,span'))
              if ((el.innerText || '').trim() === 'ใช้เพจ') { el.click(); return; }
        }""")
        time.sleep(5)
    except Exception:  # noqa: BLE001
        return False
    return _acting_as_page(desk.text())


def _fb_page_views(text: str):
    """The Page's 28-day views from the views dashboard, or UNKNOWN.

    The dashboard prints a row of tab labels ("Reels", "โพสต์", "สตอรี่") and
    then, a line later, the numbers for the selected tab. Reading the first
    number after the *first* "ยอดดู" picks up the label list, not the total, so
    this keys on the "28 วันที่ผ่านมา" range line and takes the number that
    follows it — the total for the window.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "วันที่ผ่านมา" in line:
            for cand in lines[i + 1:i + 6]:
                tok = cand.strip().replace(",", "")
                if tok.isdigit():
                    return int(tok)
    return "UNKNOWN"


def _fb_content_rows(text: str) -> list[dict]:
    """Per-post views from the content library, newest/most-viewed first.

    The library lists each post as a block: a date line ("7 พ.ย. เวลา 01:31"),
    then the metric columns in the order the header names them. The first bare
    integer after the date line is views, the second is reach ("ผู้ชม"). A post
    with no text ("ไม่มีเนื้อหาข้อความ") still carries its numbers, so the date
    line — not the caption — is the anchor. Unreadable rows are skipped rather
    than guessed.
    """
    import re
    lines = [ln.strip() for ln in text.splitlines()]
    date_re = re.compile(r"^(\d{1,2}\s+\S+\.?\s+เวลา\s+\d{1,2}:\d{2})$")
    rows: list[dict] = []
    for i, ln in enumerate(lines):
        m = date_re.match(ln)
        if not m:
            continue
        nums: list[int] = []
        j = i + 1
        while j < len(lines) and len(nums) < 2:
            tok = lines[j].replace(",", "").strip()
            if tok.isdigit():
                nums.append(int(tok))
            elif date_re.match(lines[j]):
                break
            j += 1
        if nums:
            rows.append({"at": m.group(1),
                         "views": nums[0],
                         "reach": nums[1] if len(nums) > 1 else "UNKNOWN"})
    return rows


def measure_facebook(desk: Desk) -> dict:
    """The Page numbers, read as the Page (never as the person).

    Followers come from the Page profile line ("ผู้ติดตาม N คน"). Views come from
    the Page-scoped views dashboard. The identity switch is the whole point: the
    insights route serves the *acting* account's numbers, so without the switch
    it reported the person's figures (0-49) and the Page's real reach (861 in 28
    days, 99.9% from non-followers) was invisible.
    """
    # Land on the Page first: the insights route answers "Not Found" when it is
    # the first URL of a fresh tab, and the switch needs the Page open anyway.
    desk.goto(FB_PAGE, settle=12)
    profile = desk.text()
    if _fb_signed_out(profile):
        return {"reachable": False, "note": "not signed in"}
    followers = _followers(profile)

    if not _acting_as_page(profile) and not _switch_to_page(desk):
        return {
            "reachable": True,
            "views_28d": "UNKNOWN",
            "followers": followers,
            "note": "could not switch to the Page identity; numbers withheld",
            "raw": profile[:600],
        }

    desk.goto(FB_INSIGHTS, settle=14)
    t = desk.text()
    if "Not Found" in t[:200]:
        return {
            "reachable": True,
            "views_28d": "UNKNOWN",
            "followers": followers,
            "note": "insights route unavailable; followers read from the Page",
            "raw": t[:600],
        }
    # Per-post views live on a second page. A failure there must not lose the
    # window total, so it is best-effort and reported as an empty list.
    posts: list[dict] = []
    try:
        desk.goto(FB_CONTENT, settle=16)
        posts = _fb_content_rows(desk.text())
    except Exception:  # noqa: BLE001
        posts = []
    return {
        "reachable": True,
        "views_28d": _fb_page_views(t),
        "followers": followers,
        "posts": posts,
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


def _shopee_cookie_header() -> str | None:
    """The affiliate cookies out of the exported storage state, or None.

    Shopee's anti-fraud only guards the *browser*: a plain HTTP request to the
    affiliate report API with these cookies answers normally. That is what makes
    a scheduled read possible at all — the dashboard page itself serves a
    `/verify/traffic/error` interstitial to any fresh automated browser, headless
    or headed, but the JSON endpoints behind it do not.
    """
    import base64
    b64 = os.environ.get("AERIS_STORAGE_STATE_B64")
    path = os.environ.get("AERIS_STORAGE_STATE")
    raw = None
    if b64:
        try:
            raw = base64.b64decode(b64)
        except (ValueError, TypeError):
            return None
    elif path and os.path.exists(path):
        raw = Path(path).read_bytes()
    if not raw:
        return None
    try:
        state = json.loads(raw)
    except ValueError:
        return None
    pairs = [f"{c['name']}={c['value']}" for c in state.get("cookies", [])
             if "shopee" in c.get("domain", "") and c.get("name")]
    return "; ".join(pairs) if pairs else None


def _shopee_api(path: str, cookie: str) -> dict:
    req = urllib.request.Request(SHOPEE_AFFILIATE_API + path, headers={
        "Cookie": cookie,
        "Accept": "application/json, text/plain, */*",
        "Affiliate-Program-Type": "1",
        "Referer": SHOPEE_AFFILIATE + "/dashboard",
        "User-Agent": ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                       "(KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36"),
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def measure_shopee_api(days: int = 30) -> dict | None:
    """Shopee clicks/orders/commission straight from the affiliate JSON API.

    Returns None when no session is available or the API refuses, so the caller
    can fall back to the (desktop-only) scrape. This path needs no browser, so it
    is the one that works inside the scheduled CI rail.
    """
    cookie = _shopee_cookie_header()
    if not cookie:
        return None
    now = int(time.time())
    start = now - days * 86400
    try:
        clicks = _shopee_api(
            f"/api/v1/click_report/list?click_time_s={start}&click_time_e={now}"
            "&page_num=1&page_size=1", cookie)
        conv = _shopee_api(
            f"/api/v3/report/list?page_size=20&page_num=1"
            f"&purchase_time_s={start}&purchase_time_e={now}&version=1", cookie)
        bill = _shopee_api(
            f"/api/v3/payment/billing_list?order_completed_start_time={start}"
            f"&order_completed_end_time={now}&settlement_cycle=4", cookie)
    except Exception:  # noqa: BLE001  (network/JSON — fall back to the desk)
        return None
    if clicks.get("code") != 0 or conv.get("code") != 0:
        return None
    click_n = (clicks.get("data") or {}).get("total_count")
    conv_data = conv.get("data") or {}
    orders = conv_data.get("total_count")
    items = conv_data.get("list") or []
    comm = 0.0
    for it in items:
        for key in ("commission", "total_commission", "est_commission"):
            v = it.get(key)
            if isinstance(v, (int, float)):
                comm += float(v)
                break
    if not items:  # no orders yet — read settled commission from the bill
        for bucket in ("social_medias", "shopee_live"):
            grp = ((bill.get("data") or {}).get("income_breakdown") or {}).get(bucket) or {}
            for sec in ("seller_commission", "shopee_commission", "bonus_commission"):
                d = grp.get(sec) or {}
                for k, v in d.items():
                    if k.endswith("_comm") and isinstance(v, (int, float)):
                        comm += float(v)
    comm = int(comm) if float(comm).is_integer() else round(comm, 2)
    return {
        "reachable": True,
        "source": "api",
        "window_days": days,
        "clicks": click_n if click_n is not None else "UNKNOWN",
        "orders": orders if orders is not None else "UNKNOWN",
        "commission": comm,
    }


def measure_shopee(desk: Desk) -> dict:
    # The API path first: it works headlessly, so a scheduled read gets a real
    # number instead of the captcha page. The desk scrape is the fallback.
    api = measure_shopee_api()
    if api is not None:
        return api
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
    posts = fb.get("posts") or []
    if posts:
        lines += ["## รายคลิป Facebook (เรียงตามยอดดู)", "",
                  "| เผยแพร่ | ยอดดู | ผู้ชม |", "| --- | ---: | ---: |"]
        lines += [f"| {p['at']} | {p['views']} | {p['reach']} |" for p in posts]
        lines += [""]
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

    # Shopee first, straight from the API: it needs no browser, so a pod without
    # chromium still reports it. The desk is then best-effort for FB/TikTok.
    shopee = measure_shopee_api()
    stats = {"facebook": {"reachable": False, "note": "desktop unavailable"},
             "tiktok": {"reachable": False, "note": "desktop unavailable"},
             "shopee": shopee or {"reachable": False, "note": "no session"}}
    try:
        desk = open_desk()
    except Exception as exc:  # noqa: BLE001
        print(f"desktop/CDP unavailable: {exc}", file=sys.stderr)
        desk = None
    if desk is not None:
        try:
            stats["facebook"] = measure_facebook(desk)
            stats["tiktok"] = measure_tiktok(desk)
            if shopee is None:
                stats["shopee"] = measure_shopee(desk)
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

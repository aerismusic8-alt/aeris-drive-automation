#!/usr/bin/env python3
"""A tap-first sign-in page for a phone.

Why this exists
---------------
noVNC is the only way to reach the cloud desktop from a phone, but it is a
landscape 1600x900 screen shrunk onto a small display: the address bar is a few
pixels tall, so the operator has to pinch, zoom, and type a URL with cold hands.
The desktop can be resized to the phone (x11vnc -xrandr + `resize=remote`), but
typing a URL is still the hard part.

This server removes the typing. It serves one mobile page of large buttons; each
button opens that surface as a new tab in the *already signed-in* desktop
browser and then drops straight into noVNC showing it. So the operator's whole
job on the phone is: tap the surface, sign in with the password manager, done.

    python3 ops/phone_login.py            # serves on 0.0.0.0:12001
    python3 ops/phone_login.py --port 12001

Open it at the session's work-2 host (see below). Nothing here signs in for the
operator and no password is ever typed by the agent.
"""
from __future__ import annotations

import argparse
import json
import os
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CDP = "http://127.0.0.1:9222"
# The surfaces that need a human sign-in. Each is (label, url, hint). The hint is
# K's own experience of what the sign-in actually takes: most surfaces are already
# signed in and open on a tap, Facebook offers the saved password after one tap in
# the field, and only Shopee needs the slide puzzle. Ordered easiest-first so the
# surfaces that "just open" are at the top.
# A tap opens the surface as a tab in the desktop browser. The account hint is
# per surface, because the pack now uses more than one Google account: the
# music/Drive work is `aerismusic8`, while the Shopee affiliate is `kongkeat.p3`.
# The agent must never type a password, so "switch account" only *opens* Google's
# own account chooser — the operator picks the account and the saved password.
CHOOSER = ("https://accounts.google.com/AccountChooser"
           "?continue=https://drive.google.com/drive/my-drive")

SURFACES = {
    "flow": ("Flow Music — เครื่องทำเพลง", "https://www.flowmusic.app/",
             "กดปุ๊บเข้าได้เลย", "aerismusic8@gmail.com"),
    "gemini": ("Gemini web — ภาพประกอบตอน", "https://gemini.google.com/app",
               "กดปุ๊บเข้าได้เลย", "aerismusic8@gmail.com"),
    "youtube": ("YouTube Studio", "https://studio.youtube.com/",
                "กดปุ๊บเข้าได้เลย", "aerismusic8@gmail.com"),
    "tiktok": ("TikTok @aeris.music4", "https://www.tiktok.com/@aeris.music4",
               "กดปุ๊บเข้าได้เลย", ""),
    "facebook": ("Facebook Page", "https://www.facebook.com/",
                 "แตะช่องรหัสผ่าน 1 ครั้ง แล้วเลือกรหัสที่บันทึกไว้", ""),
    "drive": ("Google Drive — โฟลเดอร์เพลง", "https://drive.google.com/drive/my-drive",
              "แตะรหัสที่บันทึกไว้ 1 ครั้ง", "aerismusic8@gmail.com"),
    "shopee": ("Shopee Affiliate", "https://affiliate.shopee.co.th/dashboard",
               "ต้องสไลด์รูปภาพให้ตรงก่อน", "kongkeat.p3@gmail.com"),
    "google": ("Google (ใช้เมื่อข้างบนหลุด)", "https://accounts.google.com/",
               "แตะช่องรหัสผ่าน 1 ครั้ง แล้วเลือกรหัสที่บันทึกไว้", ""),
    "switch": ("สลับบัญชี Google (เลือกอีเมลเอง)", CHOOSER,
               "แตะ แล้วเลือกอีเมลในหน้าจอเครื่อง — ตัวแทนไม่พิมพ์รหัสให้", ""),
}
# Kept for the page footer: the account most surfaces expect.
EXPECTED_ACCOUNT = "aerismusic8@gmail.com"
STATE = Path(os.environ.get("AERIS_STATE_DIR", "/workspace/ax-tools/aeris938-state"))


def novnc_url() -> str:
    """The noVNC URL for this sandbox, matching bootstrap.py."""
    rid = os.environ.get("RUNTIME_ID")
    if not rid:
        return "https://work-1-<work-host>/vnc.html?autoconnect=1&resize=remote"
    return f"https://work-1-{rid}.prod-runtime.all-hands.dev/vnc.html?autoconnect=1&resize=remote"


def cdp_alive() -> bool:
    try:
        urllib.request.urlopen(f"{CDP}/json/version", timeout=4).read()
        return True
    except Exception:  # noqa: BLE001
        return False


def open_surface(url: str) -> bool:
    """Focus the tab for `url` if it is already open, else open a new one.

    The operator works from the bookmark bar, which switches to the existing tab
    rather than stacking a new one. Mirroring that keeps the desktop clean when a
    button is tapped twice, and — more useful — a surface that is *already*
    signed in is brought forward with its session, so nothing has to reload.
    """
    try:
        tabs = json.load(urllib.request.urlopen(f"{CDP}/json", timeout=6))
    except Exception:  # noqa: BLE001
        tabs = []
    base = url.split("?")[0].rstrip("/")
    for t in tabs:
        if t.get("type") == "page" and t.get("url", "").split("?")[0].rstrip("/") == base:
            try:
                urllib.request.urlopen(f"{CDP}/json/activate/{t['id']}", timeout=6).read()
                return True
            except Exception:  # noqa: BLE001
                break
    try:
        req = urllib.request.Request(f"{CDP}/json/new?{urllib.parse.quote(url, safe='')}",
                                     method="PUT")
        urllib.request.urlopen(req, timeout=8).read()
        return True
    except Exception:  # noqa: BLE001
        return False


def vnc_password() -> str:
    p = STATE / "vnc.pass.txt"
    return p.read_text().strip() if p.exists() else ""


PAGE = """<!doctype html><html lang="th"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>AERIS — เข้าสู่ระบบ</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin:0; background:#14121a; color:#f2eef7; font:17px/1.5 system-ui,sans-serif; }}
  header {{ padding:20px 18px 6px; }}
  h1 {{ font-size:20px; margin:0 0 4px; }}
  .sub {{ color:#b9aecb; font-size:14px; }}
  .acct {{ margin:12px 18px; padding:12px 14px; background:#221d2e; border-radius:12px;
           font-size:15px; }}
  .acct b {{ color:#ffd479; }}
  .grid {{ display:grid; grid-template-columns:1fr; gap:12px; padding:8px 18px 26px; }}
  a.btn {{ display:block; padding:18px; background:#2c2440; color:#fff;
           text-decoration:none; border-radius:16px; font-size:19px; font-weight:600;
           border:1px solid #453a5f; }}
  a.btn small {{ display:block; font-weight:500; color:#ffd479; font-size:14px; margin-top:6px; }}
  a.btn em {{ display:block; font-style:normal; font-weight:400; color:#8f85a3;
              font-size:12px; margin-top:3px; word-break:break-all; }}
  a.btn:active {{ background:#3a2f55; }}
  .vnc {{ display:block; text-align:center; margin:0 18px 26px; padding:18px;
          background:#0f6b4f; color:#fff; border-radius:16px; text-decoration:none;
          font-size:19px; font-weight:700; }}
  .note {{ color:#9c92ad; font-size:13px; padding:0 18px 30px; }}
</style></head><body>
<header><h1>AERIS — เข้าสู่ระบบ</h1>
<div class="sub">แตะปุ่ม = เปิดหน้านั้นในเครื่อง แล้วเข้า noVNC อัตโนมัติ</div></header>
<div class="acct">บัญชีที่ใช้บ่อย: <b>{account}</b><br><span style="font-size:13px;color:#b9aecb">
อยากใช้บัญชีอื่น (เช่น <b>kongkeat.p3@gmail.com</b>) กดปุ่ม "สลับบัญชี Google" ล่างสุด
แล้วเลือกอีเมลในหน้าจอเครื่อง · หากรหัสค้างอยู่ กด "ล็อกอิน" ได้เลย</span></div>
<div class="grid">{buttons}</div>
<a class="vnc" href="{vnc}" target="_blank">เปิด noVNC (หน้าจอเครื่อง)</a>
<div class="note">รหัส VNC: <b>{vncpass}</b><br>
desktop: <b>{desktop}</b> · CDP: <b>{cdp}</b><br>
ลิงก์นี้ตายเมื่อ pod recycle — เปิดใหม่ด้วย <code>bootstrap.py --url</code></div>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quieter logs
        pass

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _redirect(self, url: str) -> None:
        self.send_response(302)
        self.send_header("Location", url)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/health":
            body = json.dumps({"cdp": cdp_alive(), "surfaces": list(SURFACES)}).encode()
            return self._send(200, body, "application/json")
        if parsed.path == "/goto":
            key = urllib.parse.parse_qs(parsed.query).get("u", [""])[0]
            surf = SURFACES.get(key)
            if surf:
                open_surface(surf[1])
            # The surface is now the active tab in the desktop; drop the phone
            # straight into noVNC so the operator only has to sign in.
            return self._redirect(novnc_url())
        if parsed.path not in ("/", "/index.html"):
            return self._send(404, b"not found", "text/plain")
        buttons = "".join(
            f'<a class="btn" href="/goto?u={k}">{label}<small>{hint}</small>'
            f'<em>{url}</em>'
            + (f'<em>บัญชี: {acct}</em>' if acct else '')
            + '</a>'
            for k, (label, url, hint, acct) in SURFACES.items())
        html = PAGE.format(account=EXPECTED_ACCOUNT, buttons=buttons,
                           vnc=novnc_url(), vncpass=vnc_password() or "(ไม่มีรหัส)",
                           desktop="up" if cdp_alive() else "down",
                           cdp="up" if cdp_alive() else "down").encode()
        return self._send(200, html, "text/html; charset=utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=12001)
    ap.add_argument("--host", default="0.0.0.0")
    a = ap.parse_args()
    print(f"phone login page on http://{a.host}:{a.port}")
    print(f"  open from the phone at https://work-2-{os.environ.get('RUNTIME_ID','<host>')}"
          f".prod-runtime.all-hands.dev/")
    ThreadingHTTPServer((a.host, a.port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

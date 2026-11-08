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
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CDP = "http://127.0.0.1:9222"
# The repo whose Actions secrets the rail reads. The crosspost workflow runs on
# GitHub's runner, so a token has to live there (not only in this pod) to be used.
REPO = "aerismusic8-alt/aeris-drive-automation"
# A classic PAT with `repo` scope, used only to write the secret. Kept on the
# durable volume; never printed.
GH_TOKEN_FILE = Path("/workspace/ax-tools/ar-identity/gh-workflow-token")
sys.path.insert(0, str(Path(__file__).resolve().parent))
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
    "facebook": ("Facebook — ตั้งค่าครั้งเดียว (2 ด่าน)",
                 "https://developers.facebook.com/async/registration/dialog/",
                 "ลงทะเบียน developer (ต้องยืนยันเบอร์) → สร้าง App → สร้างพอร์ตโฟลิโอ → System User → Token Never", ""),
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


def gh_token() -> str:
    """The PAT used to write the Actions secret. Read-only for everything else."""
    try:
        return GH_TOKEN_FILE.read_text().strip()
    except Exception:  # noqa: BLE001
        return os.environ.get("AX_GH_TOKEN", "").strip()


def _verify_token(token: str) -> dict:
    """Confirm the token really names the AERIS Music Page before storing it.

    A wrong token (personal, expired, wrong Page) must be caught here, while K is
    still looking at the screen — not discovered hours later when a Reel fails.
    """
    page_id = os.environ.get("FB_PAGE_ID", "61595890900382")
    url = (f"https://graph.facebook.com/v21.0/{page_id}?"
           + urllib.parse.urlencode({"fields": "id,name", "access_token": token}))
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            d = json.loads(r.read().decode())
        return {"ok": True, "name": d.get("name", ""), "id": d.get("id", "")}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"{e.code}: {e.read().decode()[:200]}"}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def _set_actions_secret(name: str, value: str) -> dict:
    """Write a repo Actions secret with `gh`. The value goes in on stdin."""
    tok = gh_token()
    if not tok:
        return {"ok": False, "error": "no PAT on the volume to write the secret"}
    env = dict(os.environ, GH_TOKEN=tok)
    try:
        r = subprocess.run(["gh", "secret", "set", name, "-R", REPO],
                           input=value.encode(), env=env, capture_output=True, timeout=60)
        if r.returncode != 0:
            return {"ok": False, "error": (r.stderr.decode()[:200] or "gh failed")}
        return {"ok": True}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def grab_fb_token() -> dict:
    """Read the token K just generated straight off the desktop screen.

    Copying a long token out of noVNC into a phone form is the fiddly part, so the
    agent reads the field instead: it finds the Business Settings tab and pulls any
    value that looks like a Meta token. K's job shrinks to "log in, press Generate
    Token" — no copy, no paste.
    """
    try:
        from playwright.sync_api import sync_playwright  # noqa: PLC0415
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"playwright unavailable: {e}"}
    js = """() => {
        const els = [...document.querySelectorAll('input,textarea,[contenteditable]')];
        for (const e of els) {
            const v = e.value || e.innerText || '';
            if (typeof v === 'string' && v.trim().startsWith('EAA')) return v.trim();
        }
        return '';
    }"""
    try:
        with sync_playwright() as p:
            br = p.chromium.connect_over_cdp(CDP)
            for ctx in br.contexts:
                for pg in ctx.pages:
                    if "business.facebook.com" not in pg.url:
                        continue
                    try:
                        val = pg.evaluate(js)
                    except Exception:  # noqa: BLE001
                        continue
                    if val:
                        return {"ok": True, "token": val, "page": pg.url}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}
    return {"ok": False, "error": "no token found on the desktop — press Generate Token first"}


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
  .tok {{ margin:6px 18px 20px; padding:16px; background:#1c2b22; border:1px solid #2f6b4d;
          border-radius:16px; }}
  .tok h2 {{ font-size:17px; margin:0 0 6px; color:#8ef0c0; }}
  .tokhint {{ color:#b9d9c8; font-size:13px; margin-bottom:10px; }}
  .tok textarea {{ width:100%; box-sizing:border-box; font:14px/1.4 monospace;
                   background:#0f1a14; color:#eafff5; border:1px solid #2f6b4d;
                   border-radius:10px; padding:10px; }}
  .tok button {{ width:100%; margin-top:10px; padding:16px; font-size:17px; font-weight:700;
                 background:#0f6b4f; color:#fff; border:0; border-radius:12px; }}
  a.grab {{ display:block; text-align:center; margin-top:12px; padding:18px; font-size:19px;
            font-weight:800; background:#1f9d63; color:#04140c; border-radius:14px;
            text-decoration:none; }}
</style></head><body>
<header><h1>AERIS — เข้าสู่ระบบ</h1>
<div class="sub">แตะปุ่ม = เปิดหน้านั้นในเครื่อง แล้วเข้า noVNC อัตโนมัติ</div></header>
<div class="acct">บัญชีที่ใช้บ่อย: <b>{account}</b><br><span style="font-size:13px;color:#b9aecb">
อยากใช้บัญชีอื่น (เช่น <b>kongkeat.p3@gmail.com</b>) กดปุ่ม "สลับบัญชี Google" ล่างสุด
แล้วเลือกอีเมลในหน้าจอเครื่อง · หากรหัสค้างอยู่ กด "ล็อกอิน" ได้เลย</span></div>
<div class="grid">{buttons}</div>
<div class="tok">
  <h2>Facebook token — ครั้งเดียว</h2>
  <div class="tokhint">1) กดปุ่ม Facebook ด้านบน → ล็อกอิน → เพิ่มผู้ใช้ระบบ → <b>Generate Token</b> → ตั้ง Never<br>
  2) กลับมาที่หน้านี้ กดปุ่มเขียวด้านล่าง (ไม่ต้อง copy อะไร)</div>
  <a class="grab" href="/fb-grab">ดึง token ให้เลย (ไม่ต้อง copy)</a>
  <form method="POST" action="/fb-token">
    <textarea name="token" rows="2" placeholder="หรือวาง token เอง (EAA...)" autocomplete="off"></textarea>
    <button type="submit">ตรวจสอบ + ตั้งค่าให้เลย</button>
  </form>
</div>
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

    def _result(self, title: str, ok: bool, detail: str) -> None:
        color = "#8ef0c0" if ok else "#ff9d9d"
        html = f"""<!doctype html><html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AERIS — ผลการตั้งค่า</title>
<style>body{{margin:0;background:#14121a;color:#f2eef7;font:17px/1.6 system-ui,sans-serif;
padding:28px 20px}}.b{{padding:18px;border-radius:16px;background:#221d2e;margin:16px 0}}
h1{{font-size:20px;color:{color}}}a{{display:block;padding:16px;margin-top:14px;background:#2c2440;
color:#fff;text-decoration:none;border-radius:14px;text-align:center;font-weight:700}}</style>
</head><body><h1>{title}</h1><div class="b">{detail}</div>
<a href="/">กลับหน้าหลัก</a></body></html>""".encode()
        return self._send(200, html, "text/html; charset=utf-8")

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/fb-token":
            return self._send(404, b"not found", "text/plain")
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n).decode() if n else ""
        token = urllib.parse.parse_qs(raw).get("token", [""])[0].strip()
        if not token:
            return self._result("ยังไม่ได้วาง token", False, "วาง token ในช่องก่อน แล้วกดปุ่มอีกครั้ง")
        v = _verify_token(token)
        if not v.get("ok"):
            return self._result("token ใช้ไม่ได้", False,
                                f"Meta ตอบกลับ: {v.get('error','')}<br><br>"
                                "ตรวจว่าเป็น token ของ <b>ผู้ใช้ระบบ (System User)</b> "
                                "และ assign เพจ <b>AERIS Music</b> แล้ว")
        s = _set_actions_secret("FB_PAGE_TOKEN", token)
        if not s.get("ok"):
            return self._result("ตั้ง secret ไม่สำเร็จ", False,
                                f"ยืนยันเพจได้ ({v.get('name')}) แต่เขียน secret ไม่ได้: "
                                f"{s.get('error','')}")
        return self._result("สำเร็จ — ตั้งค่าครั้งเดียวเสร็จแล้ว ✅", True,
                            f"ยืนยันเพจ: <b>{v.get('name')}</b> (id {v.get('id')})<br>"
                            "ตั้ง secret <b>FB_PAGE_TOKEN</b> ให้ repo เรียบร้อย<br><br>"
                            "จากนี้ Facebook โพสต์ผ่าน API เอง ไม่ต้องล็อกอินอีก "
                            "(คิว Reels ที่ค้างจะไหลออกในรอบถัดไป)")

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
        if parsed.path == "/fb-grab":
            g = grab_fb_token()
            if not g.get("ok"):
                return self._result("ยังไม่พบ token", False,
                                    f"{g.get('error','')}<br><br>กดปุ่ม Facebook ด้านบน "
                                    "ล็อกอินให้เสร็จ แล้วกด Generate Token ก่อน")
            v = _verify_token(g["token"])
            if not v.get("ok"):
                return self._result("เจอ token แต่ใช้ไม่ได้", False,
                                    f"Meta ตอบกลับ: {v.get('error','')}")
            s = _set_actions_secret("FB_PAGE_TOKEN", g["token"])
            if not s.get("ok"):
                return self._result("ตั้ง secret ไม่สำเร็จ", False,
                                    f"ยืนยันเพจ {v.get('name')} ได้ แต่เขียน secret ไม่ได้: "
                                    f"{s.get('error','')}")
            return self._result("สำเร็จ — ตั้งค่าครั้งเดียวเสร็จแล้ว ✅", True,
                                f"ดึง token จากหน้าจอให้เอง · ยืนยันเพจ: <b>{v.get('name')}</b>"
                                f" (id {v.get('id')})<br>ตั้ง secret <b>FB_PAGE_TOKEN</b> เรียบร้อย"
                                "<br><br>จากนี้ Facebook โพสต์ผ่าน API เอง ไม่ต้องล็อกอินอีก")
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

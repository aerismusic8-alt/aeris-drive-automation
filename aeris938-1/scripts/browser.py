"""Shared browser plumbing for the cloud desktop.

The browser is a real, headful Chromium on the sandbox X display, driven over
CDP. That matters because the generation tools (Gemini, Flow Music) are
login-only web apps: the operator signs in once through the noVNC link and the
agent then drives that same already-authenticated session. Nothing here types or
stores a credential.
"""
from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path

CDP_DEFAULT = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222")
NOVNC_PORT = os.environ.get("AERIS_NOVNC_PORT", "12000")


class LoginRequired(RuntimeError):
    """Raised when the target app is showing a sign-in wall."""


def cdp_alive(url: str | None = None) -> bool:
    # Resolved per call, not bound at import: the desktop may be started after
    # this module is loaded.
    url = url or CDP_DEFAULT
    try:
        with urllib.request.urlopen(f"{url}/json/version", timeout=8) as fh:
            json.load(fh)
        return True
    except Exception:
        return False


def login_link() -> str:
    host = os.environ.get("AERIS_PUBLIC_HOST")
    if not host:
        host = "work-1-jhakqeqvkcqlwmjh.prod-runtime.all-hands.dev"
    return f"https://{host}/vnc.html?autoconnect=1&resize=scale"


def login_instructions(app: str) -> str:
    return (
        f"{app} needs a signed-in browser.\n"
        f"  1. Open the cloud desktop: {login_link()}\n"
        f"  2. Sign in to {app} there (the agent never sees your password)\n"
        f"  3. Re-run this command; the session is reused."
    )


def connect(playwright):
    """Attach to the running cloud-desktop Chromium, or fail with a clear reason."""
    if not cdp_alive():
        raise RuntimeError(
            "no cloud desktop found on " + CDP_DEFAULT +
            "\n  start it with: aeris938-1/scripts/desktop.sh up"
        )
    browser = playwright.chromium.connect_over_cdp(CDP_DEFAULT)
    context = browser.contexts[0] if browser.contexts else browser.new_context()
    return browser, context


def page_for(context, url: str, *, reuse_host: str | None = None):
    """Return a page already on the app, else navigate a spare tab to it."""
    pages = context.pages
    if reuse_host:
        for pg in pages:
            if reuse_host in (pg.url or ""):
                return pg
    pg = pages[0] if pages else context.new_page()
    if url not in (pg.url or ""):
        pg.goto(url, wait_until="domcontentloaded", timeout=60_000)
    return pg


SIGNIN_MARKERS = (
    "sign in", "signin", "log in", "login", "เข้าสู่ระบบ",
    "ลงชื่อเข้าใช้", "continue with google", "sign up",
)


def looks_signed_out(text: str) -> bool:
    low = (text or "").lower()
    return any(m in low for m in SIGNIN_MARKERS)


def save_blob(page, blob_url: str, out: Path) -> int:
    """Pull a blob:/data: URL out of the page and write it to disk.

    Blob URLs only resolve inside the page that made them, so the bytes are read
    in page context and handed back as base64.
    """
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    b64 = page.evaluate(
        """async (url) => {
             const r = await fetch(url);
             const buf = new Uint8Array(await r.arrayBuffer());
             let s = '';
             for (let i = 0; i < buf.length; i++) s += String.fromCharCode(buf[i]);
             return btoa(s);
           }""",
        blob_url,
    )
    import base64
    data = base64.b64decode(b64)
    if not data:
        raise RuntimeError(f"blob was empty: {blob_url[:80]}")
    out.write_bytes(data)
    return len(data)

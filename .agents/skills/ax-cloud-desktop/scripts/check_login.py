#!/usr/bin/env python3
"""Report whether the desktop browser is actually signed in to Google.

    python3 check_login.py

Exit 0 only when a real Google session is present. The point is to answer "is the
login there?" with cookies rather than with a page title, because flowmusic.app and
gemini.google.com both render a normal-looking page when signed out.

Verified 2026-10-28: signed out -> 2 cookies, signed in -> ~27 and an account email.
"""
from __future__ import annotations

import re
import sys

CDP = "http://127.0.0.1:9222"


def main() -> int:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright is missing; run bootstrap.py first", file=sys.stderr)
        return 2
    try:
        with sync_playwright() as p:
            b = p.chromium.connect_over_cdp(CDP)
            ctx = b.contexts[0] if b.contexts else None
            if ctx is None:
                print("no browser context; is the desktop up?", file=sys.stderr)
                return 2
            cookies = ctx.cookies()
            google = sorted({c["name"] for c in cookies
                             if "google" in (c.get("domain") or "")})
            flow = sorted({c["name"] for c in cookies
                           if "flowmusic" in (c.get("domain") or "")})
            print(f"google cookies : {len(google)} {google[:8]}")
            print(f"flowmusic      : {flow}")
            signed_in = len(google) >= 5 and "SID" in google
            email = None
            if signed_in:
                pg = ctx.pages[0] if ctx.pages else ctx.new_page()
                pg.goto("https://myaccount.google.com/", wait_until="domcontentloaded",
                        timeout=60000)
                pg.wait_for_timeout(3500)
                m = re.search(r"[\w.+-]+@[\w.-]+\.\w+", pg.inner_text("body"))
                email = m.group(0) if m else None
            if signed_in:
                print(f"RESULT=SIGNED_IN account={email or '(not shown)'}")
                return 0
            print("RESULT=SIGNED_OUT — the operator must sign in via noVNC")
            return 1
    except Exception as exc:
        print(f"could not reach the desktop browser: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Report whether the desktop browser is actually signed in to Google.

    python3 check_login.py

Exit 0 only when a real Google session is present. The point is to answer "is the
login there?" with cookies rather than with a page title, because flowmusic.app and
gemini.google.com both render a normal-looking page when signed out.

Verified 2026-10-28: signed out -> 2 cookies, signed in -> ~27 and an account email.
"""
from __future__ import annotations

import os
import re
import sys

CDP = "http://127.0.0.1:9222"

# K's rule (2026-10-31): Flow Music and Gemini web run on K's own Google account,
# never on a mailbox AR registered. A fresh signup there means the wrong account
# is signed in, so fail loudly instead of quietly generating on it.
EXPECTED_ACCOUNT = os.environ.get("AX_GOOGLE_ACCOUNT", "aerismusic8@gmail.com")


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
            # A SID cookie can be *present and expired*, and a signed-in page still
            # contains the words "sign in" (2026-11-13: the Thai account page has a
            # "ลงชื่อเข้าใช้" link, so a text marker flagged a live session dead).
            # The only reliable evidence is *positive*: a signed-in Google page
            # shows the account's own email, and a signed-in YouTube shows the
            # avatar menu. Read those; do not infer from cookies or from words that
            # appear on both states.
            pg = ctx.pages[0] if ctx.pages else ctx.new_page()
            pg.goto("https://myaccount.google.com/", wait_until="domcontentloaded",
                    timeout=60000)
            pg.wait_for_timeout(3500)
            email = None
            m = re.search(r"[\w.+-]+@[\w.-]+\.\w+", pg.inner_text("body"))
            if m:
                email = m.group(0)
            if not email:
                # The YouTube avatar menu only opens for a signed-in viewer, and
                # only then does it name the account. A bare topbar button is NOT
                # evidence: the logged-out page has one too, which is how this
                # reported SIGNED_IN while the session was actually dead
                # (2026-11-13). Open the menu and read the account out of it.
                pg.goto("https://www.youtube.com/", wait_until="domcontentloaded",
                        timeout=60000)
                pg.wait_for_timeout(3500)
                try:
                    pg.click("#avatar-btn, ytd-topbar-menu-button-renderer", timeout=5000)
                    pg.wait_for_timeout(1500)
                    mm = re.search(r"[\w.+-]+@[\w.-]+\.\w+", pg.inner_text("body"))
                    if mm:
                        email = mm.group(0)
                except Exception:
                    pass
            signed_in = "SID" in google and email is not None
            if signed_in:
                print(f"RESULT=SIGNED_IN account={email}")
                if email and email.lower() != EXPECTED_ACCOUNT.lower():
                    print(f"RESULT=WRONG_ACCOUNT — signed in as {email}, expected "
                          f"{EXPECTED_ACCOUNT}. Flow Music and Gemini must run on "
                          f"K's account, not a mailbox AR registered. Sign out and "
                          f"back in as {EXPECTED_ACCOUNT}.")
                    return 3
                return 0
            print("RESULT=SIGNED_OUT — no account email and no YouTube avatar. First "
                  "recover from the vault: python3 ops/login_vault.py restore "
                  "(never ask K for a Google login — K's rule, 2026-11-13). Only if "
                  "the vault cannot restore it is K needed.")
            return 1
    except Exception as exc:
        print(f"could not reach the desktop browser: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

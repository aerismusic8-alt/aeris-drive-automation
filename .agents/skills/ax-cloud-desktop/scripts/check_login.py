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
            # A SID cookie can be *present and expired*: the presence check used to
            # report SIGNED_IN from a dead session (2026-11-13 — it passed while
            # youtube.com showed no avatar and Studio bounced to the sign-in wall).
            # The evidence is what an authenticated page does, not which cookies
            # exist. Load myaccount.google.com and read where it lands.
            pg = ctx.pages[0] if ctx.pages else ctx.new_page()
            pg.goto("https://myaccount.google.com/", wait_until="domcontentloaded",
                    timeout=60000)
            pg.wait_for_timeout(3500)
            landed = pg.url
            body = pg.inner_text("body")
            # The account chooser renders *at myaccount.google.com* when signed out,
            # so the URL alone is not evidence. The chooser's own words are: it
            # offers to sign in rather than showing the account. Any of these means
            # the session is gone (2026-11-13: Studio and youtube.com both showed
            # signed out while a stale SID cookie was still present).
            signed_out_markers = ("Signed out", "Use another account",
                                  "Choose an account", "Sign in with Google",
                                  "Create an account", "Sign in to",
                                  "ลงชื่อเข้าใช้", "สลับบัญชี", "เพิ่มบัญชี")
            bounced = ("accounts.google.com" in landed and "signin" in landed) \
                or "accountchooser" in landed \
                or any(mk in body for mk in signed_out_markers)
            m = re.search(r"[\w.+-]+@[\w.-]+\.\w+", body)
            email = m.group(0) if m else None
            signed_in = "SID" in google and not bounced
            if signed_in:
                print(f"RESULT=SIGNED_IN account={email or '(not shown)'}")
                if email and email.lower() != EXPECTED_ACCOUNT.lower():
                    print(f"RESULT=WRONG_ACCOUNT — signed in as {email}, expected "
                          f"{EXPECTED_ACCOUNT}. Flow Music and Gemini must run on "
                          f"K's account, not a mailbox AR registered. Sign out and "
                          f"back in as {EXPECTED_ACCOUNT}.")
                    return 3
                return 0
            if "SID" in google and bounced:
                print("RESULT=SIGNED_OUT — a SID cookie is present but the session "
                      "is dead (Google redirected to the sign-in wall). The "
                      "operator must sign in again via noVNC.")
            else:
                print("RESULT=SIGNED_OUT — the operator must sign in via noVNC")
            return 1
    except Exception as exc:
        print(f"could not reach the desktop browser: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

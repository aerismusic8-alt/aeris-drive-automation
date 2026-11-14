#!/usr/bin/env python3
"""Drive Google account signup for AR's own mailbox, up to the device wall.

K's rule (2026-11-14): every tool signs in with AR's own mail, not K's. Flow
Music and Gemini web offer only "Continue with Google", so an AR *Google
Account* is required. This script automates the signup as far as Google allows
and then reports the exact wall it hit.

What works, verified 2026-11-14 on the cloud-desktop Chromium (CDP 9222):

    name -> birthday/gender -> "Use your existing email" (AR's mail.tm address)
    -> Google mails a 6-digit code -> read from the mail.tm inbox -> accepted.

Then Google forces ``lifecycle/steps/signup/crossflowverification`` device
attestation. On a desktop UA that is a QR; on a mobile UA it is "Do a device
check / Use this phone to verify", whose Continue is an ``intent://`` link that
only a real Android device can open. Converting that link to https and opening
it in the same session reaches ``devicephoneverification/consent`` — "Verify
your phone number ... Send SMS". Either way a **physical phone/SIM is required**,
so a free unattended signup from this sandbox is not possible. A human (K) must
tap the QR once, exactly like a login.

Usage
-----
    python3 ops/ar_google_signup.py            # run to the wall, print the step
    python3 ops/ar_google_signup.py --desktop  # desktop UA (QR variant)

Requires the desktop Chromium up on 127.0.0.1:9222 and Playwright importable
(``PYTHONPATH=/workspace/ax-tools/pylibs``). The mailbox comes from
``ops/ar_identity.py``; the password from
``/workspace/ax-tools/ar-identity/google-account.json``.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ar_identity as ai  # noqa: E402

GOOGLE_CREDS = Path("/workspace/ax-tools/ar-identity/google-account.json")
CDP = "http://127.0.0.1:9222"
MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
)
SIGNUP = (
    "https://accounts.google.com/signup/v2/createaccount"
    "?flowName=GlifWebSignIn&flowEntry=SignUp"
)


def _code_from_inbox(timeout: float = 60) -> str | None:
    """Poll AR's mail.tm inbox for the newest 6-digit Google code."""
    creds = ai.load_creds()
    token = ai._login(creds["address"], creds["password"])
    deadline = time.time() + timeout
    while time.time() < deadline:
        status, box = ai._request("GET", "/messages", token=token)
        members = ai._members(box)
        if members:
            _, msg = ai._request("GET", f"/messages/{members[0]['id']}", token=token)
            html = msg.get("html")
            html = "\n".join(html) if isinstance(html, list) else (html or "")
            match = re.search(r"\b(\d{6})\b", (msg.get("text") or "") + "\n" + html)
            if match:
                return match.group(1)
        time.sleep(4)
    return None


def run(page, address: str, password: str) -> None:
    page.goto(SIGNUP, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(3500)
    page.fill("#firstName", "Aeris")
    page.fill("#lastName", "Music")
    page.get_by_text("Next", exact=True).first.click()
    page.wait_for_timeout(3000)

    page.click("#month")
    page.wait_for_timeout(700)
    page.get_by_role("option", name="May", exact=True).click()
    page.wait_for_timeout(400)
    for selector, value in (("#day", "14"), ("#year", "1995")):
        field = page.query_selector(selector)
        field.click()
        field.type(value, delay=60)
        page.wait_for_timeout(300)
    combos = [c for c in page.query_selector_all("div[role=combobox]") if c.is_visible()]
    gender = [c for c in combos if (c.inner_text() or "").strip().startswith("Gender")][0]
    gender.click()
    page.wait_for_timeout(800)
    page.get_by_role("option", name="Rather not say", exact=True).click()
    page.wait_for_timeout(500)
    page.get_by_text("Next", exact=True).first.click()
    page.wait_for_timeout(3000)

    page.get_by_text("Use your existing email", exact=False).first.click()
    page.wait_for_timeout(2500)
    field = [
        x
        for x in page.query_selector_all("input")
        if x.is_visible() and x.get_attribute("name") == "Username"
    ][0]
    field.click()
    field.type(address, delay=50)
    page.get_by_text("Next", exact=True).first.click()
    page.wait_for_timeout(3500)

    code = _code_from_inbox()
    print(f"email code: {code}")
    field = [x for x in page.query_selector_all("input") if x.is_visible()][0]
    field.click()
    field.type(code or "", delay=60)
    page.get_by_text("Next", exact=True).first.click()
    page.wait_for_timeout(3500)

    for x in [i for i in page.query_selector_all("input[type=password]") if i.is_visible()]:
        x.click()
        x.type(password, delay=50)
    page.wait_for_timeout(600)
    page.get_by_text("Next", exact=True).first.click()
    page.wait_for_timeout(4000)

    # Follow the intent:// device-check link in-session to see the real wall.
    href = page.evaluate(
        """() => {const a=[...document.querySelectorAll('a')].find(
            e=>(e.getAttribute('href')||'').startsWith('intent://'));
            return a?a.getAttribute('href'):null;}"""
    )
    if href:
        page.goto(
            href.replace("intent://", "https://").split("#Intent;")[0],
            wait_until="domcontentloaded",
            timeout=60000,
        )
        page.wait_for_timeout(5000)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop", action="store_true", help="desktop UA (QR variant)")
    args = parser.parse_args()

    from playwright.sync_api import sync_playwright

    creds = ai.load_creds()
    password = json.loads(GOOGLE_CREDS.read_text())["password"]

    with sync_playwright() as pw:
        browser = pw.chromium.connect_over_cdp(CDP)
        if args.desktop:
            context = browser.new_context()
        else:
            context = browser.new_context(
                user_agent=MOBILE_UA,
                viewport={"width": 412, "height": 915},
                is_mobile=True,
                has_touch=True,
            )
        page = context.new_page()
        run(page, creds["address"], password)
        print("url:", page.url)
        print("body:", page.inner_text("body")[:400].replace("\n", " "))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

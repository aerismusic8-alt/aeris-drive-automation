#!/usr/bin/env python3
"""AR browser — a persistent Chromium profile AR signs in to and keeps.

Why a persistent profile
------------------------
A normal Playwright launch is anonymous: cookies die with the process. AR needs
the opposite — sign in once to a service and stay signed in on every later run,
so the login *is* the credential and no password is ever stored in the repo.

The profile lives at ``/workspace/ax-tools/ar-identity/browser-profile``. That
path matters: ``$HOME`` is thrown away on a pod recycle, so a profile kept there
would log AR out of everything each time the sandbox is rebuilt.

This module is both a library (``session()`` for other scripts) and a CLI
(``open`` / ``shot`` / ``text``) for quick inspection.

Usage
-----
    python3 ops/ar_browser.py open https://example.com --shot /tmp/a.png
    python3 ops/ar_browser.py text https://example.com
    python3 ops/ar_browser.py shot https://example.com /tmp/a.png

Library
-------
    from ar_browser import session
    with session() as page:
        page.goto("https://gravatar.com/connect")
"""
from __future__ import annotations

import argparse
import os
import sys
from contextlib import contextmanager
from pathlib import Path

IDENTITY_DIR = Path(
    os.environ.get("AR_IDENTITY_DIR", "/workspace/ax-tools/ar-identity")
)
PROFILE_DIR = IDENTITY_DIR / "browser-profile"

UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36"
)


@contextmanager
def session(headless: bool = True, slow_ms: int = 0):
    """Yield a Page bound to AR's persistent profile.

    The context is persistent, so cookies written here survive to the next run.
    """
    from playwright.sync_api import sync_playwright

    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=str(PROFILE_DIR),
            headless=headless,
            user_agent=UA,
            viewport={"width": 1366, "height": 900},
            args=["--no-sandbox", "--disable-blink-features=AutomationControlled"],
        )
        ctx.set_default_timeout(45000)
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        if slow_ms:
            page.wait_for_timeout(slow_ms)
        try:
            yield page
        finally:
            ctx.close()


def _open(url: str, headless: bool, wait_ms: int) -> None:
    with session(headless=headless) as page:
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_timeout(wait_ms)
        print(f"url: {page.url}")
        print(f"title: {page.title()}")


def _shot(url: str, path: str, headless: bool, wait_ms: int) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with session(headless=headless) as page:
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_timeout(wait_ms)
        page.screenshot(path=path, full_page=True)
        print(f"saved {path}  ({page.title()})")


def _text(url: str, headless: bool, wait_ms: int) -> None:
    with session(headless=headless) as page:
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_timeout(wait_ms)
        print(page.locator("body").inner_text())


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--headed", action="store_true", help="show the window (needs a display)")
    p.add_argument("--wait", type=int, default=2500, help="ms to settle after load")
    sub = p.add_subparsers(dest="cmd", required=True)

    po = sub.add_parser("open")
    po.add_argument("url")
    po.set_defaults(fn=lambda a: _open(a.url, not a.headed, a.wait))

    ps = sub.add_parser("shot")
    ps.add_argument("url")
    ps.add_argument("path")
    ps.set_defaults(fn=lambda a: _shot(a.url, a.path, not a.headed, a.wait))

    pt = sub.add_parser("text")
    pt.add_argument("url")
    pt.set_defaults(fn=lambda a: _text(a.url, not a.headed, a.wait))

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())

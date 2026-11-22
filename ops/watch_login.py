#!/usr/bin/env python3
"""Save the vault the moment K finishes signing into a surface that needs him.

K's rule (2026-11-13) is one sign-in, then the vault keeps it — but a sign-in is
only captured when something runs `login_vault.py save` afterwards, and K should
not have to say "done". This watches the surfaces that cannot be revived from the
vault (TikTok, Shopee) and saves each time one turns signed in.

    python3 ops/watch_login.py                 # 4 hours, checks every 90 s
    python3 ops/watch_login.py --minutes 30

Runs against the cloud desktop, so start it there first:
`.agents/skills/ax-cloud-desktop/scripts/bootstrap.py`. Needs OPENHANDS_API_KEY
for the vault write, exactly like `login_vault.py`.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SURFACES = {
    "tiktok": ("https://www.tiktok.com/tiktokstudio/upload",
               lambda url, html: "/login" not in url
               and ("Select video" in html or "/tiktokstudio" in url)),
    "shopee": ("https://affiliate.shopee.co.th/dashboard",
               lambda url, html: "login" not in url and "signin" not in url.lower()),
}


def probe(url: str) -> tuple[str, str]:
    from playwright.sync_api import sync_playwright  # noqa: PLC0415

    with sync_playwright() as pw:
        br = pw.chromium.connect_over_cdp("http://127.0.0.1:9222")
        ctx = br.contexts[0] if br.contexts else br.new_context()
        pg = ctx.new_page()
        try:
            pg.goto(url, wait_until="domcontentloaded", timeout=45000)
            pg.wait_for_timeout(4000)
            return pg.url, pg.content()
        finally:
            pg.close()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--minutes", type=int, default=240)
    ap.add_argument("--every", type=int, default=90)
    ap.add_argument("--only", help="comma-separated subset of tiktok,shopee")
    args = ap.parse_args(argv)

    wanted = set(args.only.split(",")) if args.only else set(SURFACES)
    deadline = time.time() + args.minutes * 60
    seen: set[str] = set()
    while time.time() < deadline:
        for name in sorted(wanted - seen):
            url, test = SURFACES[name]
            try:
                final, html = probe(url)
            except Exception as exc:  # noqa: BLE001
                print(f"{name}: check failed ({str(exc)[:90]})", flush=True)
                continue
            if test(final, html):
                seen.add(name)
                print(f"{name} signed in — saving the vault", flush=True)
                rc = subprocess.call([sys.executable, "ops/login_vault.py", "save"],
                                     cwd=ROOT)
                print(f"login_vault.py save -> rc={rc}", flush=True)
        if seen >= wanted:
            print("every watched surface is saved; done", flush=True)
            return 0
        time.sleep(args.every)
    print(f"stopped after {args.minutes} min; saved: {sorted(seen) or 'none'}", flush=True)
    return 0 if seen >= wanted else 1


if __name__ == "__main__":
    raise SystemExit(main())

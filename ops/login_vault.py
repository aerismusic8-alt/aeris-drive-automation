#!/usr/bin/env python3
"""Persist the cloud-desktop browser session so K signs in once, not every pod.

Why this exists
---------------
The Chrome profile lives on /workspace, which survives a container recycle — but
a *new sandbox* gets a fresh, empty volume, so every sign-in (Google, Facebook,
TikTok) is lost and has to be redone. K has now had to do it more than once, which
is a defect, not a workflow.

What it stores, and what it does not
------------------------------------
Only the browser **session cookies** (the thing that keeps you logged in), read
live over CDP and written to the account-scoped automation KV store that also
backs the knowledge vault. It never touches the account password, so the saved
passwords are deliberately excluded. Cookies are still secrets — treat a snapshot
like a live session, and rotate by signing out.

Why cookies and not the profile directory
-----------------------------------------
Copying the profile's SQLite `Cookies` file is unreliable: Chromium holds it open
and flushes lazily, so a copy can be stale, and the file is encrypted with a key
in `Local State`. Reading the cookies through CDP returns the authoritative set
the browser is actually using, and re-adding them through CDP lets Chromium
re-encrypt them with whatever key the *new* sandbox has. That is why a restore
works on a machine with no keyring at all.

Usage
-----
    python3 ops/login_vault.py save       # after K signs in, capture the session
    python3 ops/login_vault.py restore    # on a fresh sandbox, put it back
    python3 ops/login_vault.py status     # what is stored, and when
"""
from __future__ import annotations

import argparse
import base64
import gzip
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ax_vault  # noqa: E402

CDP = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222")
INDEX_KEY = "axlogin:index"
CHUNK_KEY = "axlogin:d:{i}"
# Leave room for the JSON envelope under the 65536-byte KV value cap.
CHUNK_CHARS = ax_vault.CHUNK_CHARS
# Surfaces worth reporting on, so `status` says something useful.
WATCH = (".google.com", "accounts.google.com", ".facebook.com", ".tiktok.com")
# The cookie that actually proves a session on each surface. A restored cookie is
# not a restored session: the site can still reject it, and reporting "ok" on
# mere presence is how a dead session looked healthy for a whole session.
AUTH = {
    ".google.com": "SID",
    ".facebook.com": "c_user",
    ".tiktok.com": "sessionid",
}
# Where to look, and what a signed-in page shows instead of a login form.
PROBE = {
    ".google.com": ("https://myaccount.google.com/", "บัญชี", "Account"),
    ".facebook.com": ("https://www.facebook.com/", "ค้นหา", "Search"),
    ".tiktok.com": ("https://www.tiktok.com/foryou", "ค้นหา", "Search"),
}


def pack(cookies: list[dict], account: str = "") -> tuple[dict, list[str]]:
    """Return (index, chunks) for a cookie set. Pure, so it can be tested."""
    blob = json.dumps({"account": account, "cookies": cookies}).encode()
    b64 = base64.b64encode(gzip.compress(blob)).decode()
    chunks = [b64[i:i + CHUNK_CHARS] for i in range(0, len(b64), CHUNK_CHARS)] or [""]
    domains = sorted({c.get("domain", "") for c in cookies})
    index = {
        "count": len(chunks),
        "n_cookies": len(cookies),
        "domains": domains,
        "account": account,
        "saved_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "surfaces": {d: sum(1 for c in cookies if c.get("domain") == d) for d in WATCH
                     if any(c.get("domain") == d for c in cookies)},
    }
    return index, chunks


def unpack(index: dict, chunks: list[str]) -> list[dict]:
    """Inverse of pack. Pure, so it can be tested."""
    b64 = "".join(chunks)
    return json.loads(gzip.decompress(base64.b64decode(b64)))["cookies"]


def _context():
    """Attach to the running cloud-desktop browser, or explain how to start it."""
    from playwright.sync_api import sync_playwright
    pw = sync_playwright().start()
    try:
        br = pw.chromium.connect_over_cdp(CDP)
    except Exception as exc:  # noqa: BLE001
        pw.stop()
        raise SystemExit(
            f"no cloud desktop on {CDP} ({exc}).\n"
            "  start it first: python3 .agents/skills/ax-cloud-desktop/scripts/bootstrap.py")
    return pw, br, (br.contexts[0] if br.contexts else br.new_context())


def save() -> int:
    pw, br, ctx = _context()
    try:
        cookies = ctx.cookies()
        account = ""
        try:
            pg = ctx.pages[0] if ctx.pages else ctx.new_page()
            account = pg.evaluate(
                "() => { const m = document.body.innerText.match(/[\\w.+-]+@[\\w-]+\\.[\\w.]+/);"
                " return m ? m[0] : ''; }")
        except Exception:  # noqa: BLE001
            pass
    finally:
        pw.stop()
    if not cookies:
        raise SystemExit("the browser has no cookies to save")
    index, chunks = pack(cookies, account)
    aid = ax_vault.ensure_anchor()
    for i, c in enumerate(chunks):
        ax_vault.kv_put(aid, CHUNK_KEY.format(i=i), c)
    ax_vault.kv_put(aid, INDEX_KEY, index)
    print(f"saved {index['n_cookies']} cookies across {len(chunks)} chunk(s)")
    print(f"  account : {account or '(unknown)'}")
    print(f"  surfaces: {index['surfaces']}")
    print(f"  at      : {index['saved_at']}")
    return 0


def _signed_in(ctx, domain: str) -> bool:
    """True only if the surface actually answers as a signed-in user.

    Presence of the auth cookie is necessary but not sufficient — Facebook kept
    `c_user`/`xs` while serving the logged-out page. So this loads the surface
    and looks for content that only appears when signed in.
    """
    probe = PROBE.get(domain)
    if not probe:
        return False
    url, *markers = probe
    pg = ctx.new_page()
    try:
        pg.goto(url, wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(9000)
        body = pg.inner_text("body")
        if "เข้าสู่ระบบ" in body[:200] and "รหัสผ่าน" in body:
            return False
        return any(m in body for m in markers)
    except Exception:  # noqa: BLE001
        return False
    finally:
        pg.close()


def restore(verify: bool = True) -> int:
    index = ax_vault.kv_get(ax_vault.ensure_anchor(), INDEX_KEY)
    if not index:
        raise SystemExit("no saved session; run `login_vault.py save` after signing in")
    aid = ax_vault.ensure_anchor()
    chunks = [ax_vault.kv_get(aid, CHUNK_KEY.format(i=i)) or "" for i in range(index["count"])]
    cookies = unpack(index, chunks)
    pw, br, ctx = _context()
    try:
        ctx.add_cookies(cookies)
        present = {c["domain"] for c in ctx.cookies()}
        auth = {
            d: any(c["domain"] == d and c["name"] == AUTH[d] for c in ctx.cookies())
            for d in WATCH if d in AUTH
        }
        live = {d: _signed_in(ctx, d) for d in WATCH if d in PROBE} if verify else {}
    finally:
        pw.stop()
    print(f"restored {len(cookies)} cookies (saved {index['saved_at']})")
    for d in sorted(set(index.get("surfaces", {})) | set(WATCH)):
        if d not in present:
            print(f"  {d}: MISSING (cookie not accepted)")
            continue
        bits = ["cookie ok" if auth.get(d) else "auth cookie absent"]
        if d in live:
            bits.append("SIGNED IN" if live[d] else "**SESSION REJECTED — sign in again**")
        print(f"  {d}: {', '.join(bits)}")
    if live and not any(live.values()):
        print("\n[!] cookies restored but no surface accepted them; the saved session is dead.")
    return 0


def status() -> int:
    index = ax_vault.kv_get(ax_vault.ensure_anchor(), INDEX_KEY)
    if not index:
        print("no saved session (login_vault.py save has never run)")
        return 0
    print(f"saved {index['n_cookies']} cookies at {index['saved_at']}")
    print(f"  account : {index.get('account') or '(unknown)'}")
    print(f"  surfaces: {index.get('surfaces')}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["save", "restore", "status"])
    a = ap.parse_args()
    return {"save": save, "restore": restore, "status": status}[a.command]()


if __name__ == "__main__":
    sys.exit(main())

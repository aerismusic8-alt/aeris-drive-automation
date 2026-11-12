#!/usr/bin/env python3
"""Revive the Facebook Page browser session from the vaulted password.

The Facebook rail can lose its session in two ways, and they need different fixes:

  * the Meta Graph token is rejected at the account level ("API access blocked",
    OAuthException 200) — only a *new* token restores the headless route, and only
    the account owner can mint one. The browser route is unaffected by this.
  * the *browser* cookie session is dead — Facebook serves the logged-out page
    while still holding `c_user`/`xs`, so a cookie-presence check reads "ok" for a
    dead session. This script fixes that one, and only that one.

It never prints the password: the value comes out of the KV vault and goes straight
into the login field over CDP, exactly like `ops/phone_login.py`. A single attempt,
no retry loop — looping password attempts is what triggers a checkpoint.

    python3 ops/fb_relogin.py                 # revive and save to the vault
    python3 ops/fb_relogin.py --check         # only report the current state
    python3 ops/fb_relogin.py --push-secret   # also refresh the CI storage-state

After a revive the CI rail still holds the *old* cookie blob, so it keeps failing
until `AERIS_STORAGE_STATE_B64` is refreshed — `--push-secret` does that too, using
the workflow-scoped PAT from the vault. Without it, run
`ops/save_storage_state.py | gh secret set ...` by hand.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

CDP = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222")
REPO = "aerismusic8-alt/aeris-drive-automation"
PW_KEY = "axsecrets:fb-password"
EMAIL_KEY = "axsecrets:fb-email"


def _vault():
    import ax_vault  # noqa: PLC0415

    return ax_vault


def _has_session(ctx) -> bool:
    """A real session needs the `c_user` cookie; the page check is done separately."""
    return any(c["name"] == "c_user" and "facebook" in (c.get("domain") or "")
               for c in ctx.cookies())


def _page_signed_in(ctx) -> bool:
    """True only if Facebook actually answers as the signed-in owner.

    `c_user` can be present while Facebook serves the logged-out page (the trap
    documented in `login_vault`), so a revive must verify the *page*, not the
    cookie — otherwise `relogin` returns "already signed in" for a dead session
    and K is asked to sign in anyway.
    """
    import login_vault  # noqa: PLC0415

    return login_vault._signed_in(ctx, ".facebook.com")


def _click(page, labels) -> bool:
    """Dispatch a click in-page. FB wraps controls so Playwright's click wedges."""
    for label in labels:
        hit = page.evaluate("""(label) => {
          const els = [...document.querySelectorAll('div[role=button],button,a')]
            .filter(e => (e.innerText || '').trim() === label);
          if (!els.length) return 'miss';
          els[els.length - 1].click();
          return 'ok';
        }""", label)
        if hit == "ok":
            return True
    return False


def check() -> int:
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        br = p.chromium.connect_over_cdp(CDP)
        ctx = br.contexts[0] if br.contexts else br.new_context()
        ok = _has_session(ctx)
        print(f"facebook browser session: {'SIGNED IN' if ok else 'SIGNED OUT'}")
        return 0 if ok else 1


def _login(pg, ctx, pw: str) -> int:
    """The chooser -> password -> verify steps, on an already-navigated page.

    Shared by the desktop revive and the headless (CI) revive so both take the
    same path — the one that works on this account.
    """
    pg.goto("https://www.facebook.com/", wait_until="domcontentloaded", timeout=60000)
    pg.wait_for_timeout(3500)
    # The remembered-account chooser asks for the password next; click it
    # so the login form (email + password) is not the path taken.
    if not _click(pg, ("Continue", "ดำเนินการต่อ", "ใช้โปรไฟล์นี้ต่อ")):
        print("no remembered-account chooser; trying the classic login form")
    pg.wait_for_timeout(7000)

    field = pg.locator("input[type=password]")
    if not field.count():
        print("no password field appeared — the login UI may have changed; "
              "not guessing further")
        return 1
    field.first.click(timeout=8000)
    field.first.fill(pw, timeout=8000)
    pg.wait_for_timeout(800)
    if not _click(pg, ("Log in", "เข้าสู่ระบบ", "Continue")):
        print("could not find the submit button")
        return 1
    pg.wait_for_timeout(9000)
    if not _has_session(ctx):
        # A checkpoint page is the likely reason; stop rather than retry.
        body = pg.inner_text("body")[:300].replace("\n", " ")
        print(f"login did not complete (page: {body[:200]})")
        return 1
    return 0


def _password() -> str:
    import ax_vault  # noqa: PLC0415

    return ax_vault.kv_get(ax_vault.ensure_anchor(), PW_KEY) or ""


def relogin() -> int:
    """One supervised login attempt: chooser -> password -> verify."""
    from playwright.sync_api import sync_playwright

    pw = _password()
    if not pw:
        print(f"no Facebook password in the vault ({PW_KEY}); cannot revive")
        return 2

    with sync_playwright() as p:
        br = p.chromium.connect_over_cdp(CDP)
        ctx = br.contexts[0] if br.contexts else br.new_context()
        # Verify the *page*, not the cookie: `c_user` can be present while
        # Facebook serves the logged-out page, and treating that as "signed in"
        # is exactly the bug that sent K to sign in by hand.
        if _has_session(ctx) and _page_signed_in(ctx):
            print("already signed in — nothing to do")
            return 0
        pg = ctx.new_page()
        try:
            rc = _login(pg, ctx, pw)
            if rc:
                return rc
        finally:
            pg.close()
    print("signed in")
    import login_vault  # noqa: PLC0415

    login_vault.save()
    return 0


def revive_headless(state_path: str) -> int:
    """Revive a dead Facebook session on a *headless* Chromium, in CI.

    The desktop route (`relogin`) only runs where a cloud desktop is up. GitHub
    Actions is the always-on free runner, and it holds the vaulted password, so
    the same login can run there against a stored session and write the refreshed
    session back — that is what lets a cron heal Facebook with no pod and no K.
    """
    from playwright.sync_api import sync_playwright

    pw = _password()
    if not pw:
        print(f"no Facebook password in the vault ({PW_KEY}); cannot revive")
        return 2

    launch = dict(headless=True, args=["--no-sandbox", "--disable-dev-shm-usage"])
    exe = os.environ.get("AERIS_CHROMIUM")
    if exe:
        launch["executable_path"] = exe
    with sync_playwright() as p:
        br = p.chromium.launch(**launch)
        ctx = br.new_context(storage_state=state_path, locale="th-TH",
                             viewport={"width": 1280, "height": 900})
        if _has_session(ctx) and _page_signed_in(ctx):
            print("already signed in — nothing to do")
            br.close()
            return 0
        pg = ctx.new_page()
        try:
            rc = _login(pg, ctx, pw)
            if rc:
                return rc
            state = ctx.storage_state()
        finally:
            pg.close()
            br.close()
    import json  # noqa: PLC0415

    Path(state_path).write_text(json.dumps(state, separators=(",", ":")),
                                encoding="utf-8")
    print(f"signed in; refreshed {state_path}")
    return 0


def push_secret() -> int:
    """Refresh the CI `AERIS_STORAGE_STATE_B64` from the now-live desktop session."""
    import ax_vault
    from save_storage_state import main as export  # noqa: PLC0415

    blob = _capture_stdout(export)
    if not blob:
        print("could not export a storage state (is the desktop signed in?)")
        return 1
    tok = ax_vault.kv_get(ax_vault.ensure_anchor(), "axsecrets:gh-workflow-token")
    token = tok.get("token", "") if isinstance(tok, dict) else (tok or "")
    if not token:
        print("no write token in the vault (axsecrets:gh-workflow-token); "
              "set the secret by hand")
        return 1
    env = dict(os.environ, GITHUB_TOKEN=token, AERIS_STORAGE_STATE_B64=blob)
    r = subprocess.run(
        [sys.executable, str(HERE.parent / "scripts" / "gh-put-secrets.py"),
         "--repo", REPO, "AERIS_STORAGE_STATE_B64"],
        env=env, capture_output=True, text=True)
    print((r.stdout or r.stderr).strip())
    return r.returncode


def _capture_stdout(fn) -> str:
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fn()
    return buf.getvalue().strip()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report the session state only")
    ap.add_argument("--push-secret", action="store_true",
                    help="also refresh the CI storage-state secret after a revive")
    args = ap.parse_args(argv)

    if args.check:
        return check()
    rc = relogin()
    if rc == 0 and args.push_secret:
        rc = push_secret() or rc
    return rc


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

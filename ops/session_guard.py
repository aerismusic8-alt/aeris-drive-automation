#!/usr/bin/env python3
"""Keep every browser surface the rails need alive — and heal the ones that can
be healed without K.

Why this exists
---------------
K's complaint, verbatim: "มีช่องทางอื่นไหมที่ไม่ใช่ novnc มันจะล้างคุ๊กกี้ตลอด
ล็อกอินบ่อยแบบนี้จะออโต้ได้ไง" — the cookie keeps getting wiped and the loop
depends on K signing in again. Two things were wrong:

  1. The CI rails read a *frozen* Actions secret, not the durable vault, so a
     live desktop sign-in never reached CI. (Fixed: `vault_session.py` +
     `browser.connect`.)
  2. Nothing revives a dead session on its own, even when the password is sitting
     in the vault. Facebook is the one surface that can be revived headlessly, and
     it was only revived when a human ran `fb_relogin.py`.

This command closes both. It checks each surface, auto-revives Facebook from the
vaulted password, refreshes the vault session so CI reads it, and reports only the
surfaces that genuinely still need K (a Google 2FA prompt, Shopee's slide puzzle).

    python3 ops/session_guard.py            # check, revive what it can, refresh CI
    python3 ops/session_guard.py --check    # report only, change nothing
    python3 ops/session_guard.py --no-push  # revive + refresh vault, skip the secret

Exit 0 when every surface is alive or was revived. Exit 1 when a surface is dead
and only K can fix it — that is the one case that should page K.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

CDP = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222")
# Surfaces the rails read, and whether AR can revive them with no human.
# facebook: yes — a vaulted password and no per-login second factor in this setup.
# flow: yes — it signs in through Google SSO, and the vaulted google-password
#   completes the chooser (verified 2026-11-12: a dead Flow session came back with
#   no K). It must run on the desktop browser, not headless — Google blocks
#   headless logins — so it heals whenever a pod is up.
# the rest: no — a device prompt or a slide puzzle, so a dead session is a K task.
AUTO_REVIVE = {"facebook", "flow"}


def _surfaces() -> dict[str, bool]:
    """Map each watched surface to whether its *page* answers signed in."""
    import login_vault  # noqa: PLC0415
    from playwright.sync_api import sync_playwright  # noqa: PLC0415

    out: dict[str, bool] = {}
    with sync_playwright() as p:
        br = p.chromium.connect_over_cdp(CDP)
        ctx = br.contexts[0] if br.contexts else br.new_context()
        for domain in login_vault.WATCH:
            if domain not in login_vault.PROBE:
                continue
            out[domain] = login_vault._signed_in(ctx, domain)
    return out


def _domain(name: str) -> str:
    return {"facebook": ".facebook.com", "tiktok": ".tiktok.com",
            "google": ".google.com", "flow": ".flowmusic.app"}[name]


def run(check_only: bool = False, push: bool = True) -> int:
    try:
        state = _surfaces()
    except Exception as exc:  # noqa: BLE001
        print(f"cannot reach the cloud desktop: {str(exc)[:120]}")
        return 0  # no desktop is not a failure of this job

    dead = [d for d, ok in state.items() if not ok]
    for d, ok in sorted(state.items()):
        print(f"  {d:22} {'alive' if ok else 'DEAD'}")

    if not dead:
        print("all surfaces alive")
        if not check_only:
            _refresh(False)  # keep the vault current; no need to re-push the secret
        return 0

    if check_only:
        return 1 if dead else 0

    revived = False
    if ".facebook.com" in dead:
        import fb_relogin  # noqa: PLC0415
        print("facebook is dead — reviving from the vaulted password")
        if fb_relogin.relogin() == 0:
            revived = True
            state[".facebook.com"] = True
    if ".flowmusic.app" in dead:
        if _revive_flow():
            revived = True
            state[".flowmusic.app"] = True

    # Always refresh the vault session (that is what CI reads). Push the CI secret
    # only after a revive, so the fallback is refreshed exactly when it changed.
    _refresh(push and revived)

    still_dead = [d for d, ok in state.items() if not ok]
    if still_dead:
        need_k = [d for d in still_dead
                  if d.lstrip(".").split(".")[0] not in AUTO_REVIVE]
        print(f"still dead: {', '.join(still_dead)} — these need K")
        return 1 if need_k else 0
    print("all surfaces alive after the revive" if revived else "all surfaces alive")
    return 0


def _revive_flow() -> bool:
    """Sign Flow Music back in through Google SSO, with the vaulted password.

    Flow has no password of its own: it signs in through Google. The desktop
    Google session still holds the account tile, so the whole revive is chooser ->
    password -> back to Flow. Verified 2026-11-12: a dead Flow session returned
    with no K. Runs only on the desktop — Google refuses a headless login — so it
    is best-effort whenever a pod is up.
    """
    import ax_vault  # noqa: PLC0415
    from playwright.sync_api import sync_playwright  # noqa: PLC0415

    pw = ax_vault.kv_get(ax_vault.ensure_anchor(), "axsecrets:google-password")
    if not pw:
        print("no google-password in the vault; cannot revive Flow Music")
        return False
    email = "aerismusic8@gmail.com"

    def _click_text(pg, text: str) -> bool:
        try:
            pg.evaluate("""(t) => {const e=[...document.querySelectorAll(
                'a,button,[role=button]')].find(x=>(x.innerText||'').trim()===t);
                if(e) e.click();}""", text)
            return True
        except Exception:  # noqa: BLE001
            return False

    with sync_playwright() as p:
        br = p.chromium.connect_over_cdp(CDP)
        ctx = br.contexts[0] if br.contexts else br.new_context()
        pg = ctx.new_page()
        try:
            pg.goto("https://www.flowmusic.app/", wait_until="domcontentloaded",
                    timeout=60000)
            pg.wait_for_timeout(5000)
            _click_text(pg, "Log in")
            pg.wait_for_timeout(4000)
            _click_text(pg, "Continue with Google")
            pg.wait_for_timeout(7000)
            pg.get_by_text(email).first.click(timeout=8000)
            pg.wait_for_timeout(5000)
            field = pg.locator("input[type=password]").first
            field.click(timeout=8000)
            field.fill(pw, timeout=8000)
            pg.wait_for_timeout(800)
            for lbl in ("Next", "ถัดไป"):
                try:
                    pg.get_by_role("button", name=lbl).first.click(timeout=5000)
                    break
                except Exception:  # noqa: BLE001
                    continue
            pg.wait_for_timeout(12000)
            pg.goto("https://www.flowmusic.app/", wait_until="domcontentloaded",
                    timeout=60000)
            pg.wait_for_timeout(5000)
            import login_vault  # noqa: PLC0415
            ok = login_vault._signed_in(ctx, ".flowmusic.app")
        finally:
            pg.close()
    print("flow music " + ("revived" if ok else "still signed out"))
    return ok


def _refresh(push: bool) -> None:
    """Store the live session in the vault and, optionally, push the CI secret."""
    try:
        import save_storage_state  # noqa: PLC0415
        import contextlib  # noqa: PLC0415
        import io  # noqa: PLC0415
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = save_storage_state.main()
        if rc == 0:
            print("vault session refreshed from the live desktop")
    except Exception as exc:  # noqa: BLE001
        print(f"vault session refresh skipped: {str(exc)[:100]}")
        return
    if push:
        try:
            import fb_relogin  # noqa: PLC0415
            fb_relogin.push_secret()
        except Exception as exc:  # noqa: BLE001
            print(f"secret push skipped: {str(exc)[:100]}")


def run_headless() -> int:
    """The CI half: check every surface on a headless Chromium and heal Facebook.

    No cloud desktop exists on a GitHub runner, so this loads the vaulted session
    into a headless Chromium, checks each surface, revives Facebook with the
    vaulted password when it is dead, and writes the refreshed session back to the
    vault. That is the loop that runs with no pod and no K.
    """
    import json  # noqa: PLC0415
    import tempfile  # noqa: PLC0415
    import login_vault  # noqa: PLC0415
    import vault_session  # noqa: PLC0415
    from playwright.sync_api import sync_playwright  # noqa: PLC0415

    state = vault_session.load_state()
    if not state:
        print("vault has no session — nothing to heal (K has not signed in yet)")
        return 0
    tmp = Path(tempfile.mkdtemp()) / "state.json"
    tmp.write_text(json.dumps(state, separators=(",", ":")), encoding="utf-8")

    launch = dict(headless=True, args=["--no-sandbox", "--disable-dev-shm-usage"])
    exe = os.environ.get("AERIS_CHROMIUM")
    if exe:
        launch["executable_path"] = exe

    # Only the surfaces the CI rails post to, and only Facebook is revivable
    # headlessly. Google refuses a headless login and Flow is desktop-only, so
    # checking them here would report a false "needs K".
    watched = (".facebook.com", ".tiktok.com")
    alive: dict[str, bool] = {}
    with sync_playwright() as p:
        br = p.chromium.launch(**launch)
        ctx = br.new_context(storage_state=str(tmp), locale="th-TH",
                             viewport={"width": 1280, "height": 900})
        for d in watched:
            alive[d] = login_vault._signed_in(ctx, d)
        br.close()

    for d, ok in sorted(alive.items()):
        print(f"  {d:22} {'alive' if ok else 'DEAD'}")

    revived = False
    if alive.get(".facebook.com") is False:
        import fb_relogin  # noqa: PLC0415
        print("facebook is dead — reviving headlessly from the vaulted password")
        if fb_relogin.revive_headless(str(tmp)) == 0:
            revived = True
            alive[".facebook.com"] = True

    if revived:
        vault_session.save_state(json.loads(tmp.read_text(encoding="utf-8")))
        print("vault session refreshed from the headless revive")

    dead = [d for d, ok in alive.items() if not ok]
    need_k = [d for d in dead if d.lstrip(".").split(".")[0] not in AUTO_REVIVE]
    if dead:
        print(f"still dead: {', '.join(dead)}"
              + (" — these need K" if need_k else " (auto-revivable)"))
    return 1 if need_k else 0


def watch(interval: int = 600, push: bool = False) -> int:
    """Keep the vault session fresh while a pod is up.

    A pod recycle can take a session with it before anything has saved the fresh
    cookies, and then the next pod has only the last snapshot. Running the check
    on a loop means a surface that dies is caught within `interval` — while the
    revive path can still fix it — and the vault is refreshed every round, so a
    recycle loses at most one interval of session life instead of everything.
    """
    import time  # noqa: PLC0415
    while True:
        try:
            run(check_only=False, push=push)
        except Exception as exc:  # noqa: BLE001
            print(f"watch round failed: {str(exc)[:120]}")
        time.sleep(interval)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report only, change nothing")
    ap.add_argument("--no-push", action="store_true", help="skip the CI secret push")
    ap.add_argument("--headless", action="store_true",
                    help="run on a headless Chromium (CI), not the cloud desktop")
    ap.add_argument("--watch", type=int, metavar="SECONDS", default=0,
                    help="keep checking and refreshing the vault on a loop")
    args = ap.parse_args(argv)
    if args.headless:
        return run_headless()
    if args.watch:
        return watch(args.watch, push=not args.no_push)
    return run(check_only=args.check, push=not args.no_push)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

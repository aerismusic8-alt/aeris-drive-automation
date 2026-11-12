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
# the rest: no — Google asks for a device prompt and Shopee a slide puzzle, so a
# dead session there is a real K task.
AUTO_REVIVE = {"facebook"}


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

    alive: dict[str, bool] = {}
    with sync_playwright() as p:
        br = p.chromium.launch(**launch)
        ctx = br.new_context(storage_state=str(tmp), locale="th-TH",
                             viewport={"width": 1280, "height": 900})
        for d in login_vault.WATCH:
            if d in login_vault.PROBE:
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


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report only, change nothing")
    ap.add_argument("--no-push", action="store_true", help="skip the CI secret push")
    ap.add_argument("--headless", action="store_true",
                    help="run on a headless Chromium (CI), not the cloud desktop")
    args = ap.parse_args(argv)
    if args.headless:
        return run_headless()
    return run(check_only=args.check, push=not args.no_push)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Bring up the persistent cloud desktop. Idempotent; safe to run after a recycle.

    python3 bootstrap.py            # install what is missing, start everything
    python3 bootstrap.py --status   # report only, change nothing

Why this file exists: the desktop is Xvfb + openbox + x11vnc + websockify + headful
Chromium, all of which are lost when the pod recycles, and the chrome profile has to
live on /workspace or the Google login dies with it. Doing this by hand each session
was the actual cost, so it is a script.

Verified 2026-10-28 on this sandbox: all five come up, CDP answers, noVNC connects.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

STATE = Path(os.environ.get("AERIS_STATE_DIR", "/workspace/ax-tools/aeris938-state"))
REPO = Path(__file__).resolve().parents[4]  # .agents/skills/ax-cloud-desktop/scripts/ -> repo root
DISPLAY = ":99"
SCREEN = "1600x900x24"
VNC_PORT = 5900
NOVNC_PORT = 12000
CDP_PORT = 9222
NOVNC_WEB = "/usr/share/novnc"

APT_PACKAGES = ["xvfb", "openbox", "x11vnc", "websockify", "novnc"]
PIP_PACKAGES = ["playwright", "websocket-client"]


def sh(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def sudo(cmd: list[str]) -> subprocess.CompletedProcess:
    return sh(["sudo", *cmd])


def up(pattern: str) -> bool:
    return sh(["pgrep", "-f", pattern]).returncode == 0


def spawn(cmd: list[str], log: Path, env: dict | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    fh = open(log, "ab")
    subprocess.Popen(cmd, stdout=fh, stderr=fh, stdin=subprocess.DEVNULL,
                     start_new_session=True, env=env)


def install() -> None:
    missing = [p for p in APT_PACKAGES if shutil.which(p) is None
               and p not in ("novnc",)]
    if missing or not Path(NOVNC_WEB).is_dir():
        print(f"[+] apt: {missing or ['novnc']}")
        sudo(["apt-get", "update", "-qq"])
        sudo(["apt-get", "install", "-y", "-qq", *APT_PACKAGES])
    need_pip = []
    for mod, pkg in (("playwright", "playwright"), ("websocket", "websocket-client")):
        try:
            __import__(mod)
        except ImportError:
            need_pip.append(pkg)
    if need_pip:
        print(f"[+] pip: {need_pip}")
        sh([sys.executable, "-m", "pip", "install", "-q", *need_pip])


def ensure_thai_fonts() -> None:
    """Install a Thai font, or every Thai glyph renders as a tofu box.

    The image ships 117 fonts and none of them covers Thai, so the Facebook UI
    (which renders in Thai from K's locale) and every Thai caption drew as □□□
    and K could not read the screen at all. `fc-list :lang=th` is the test.

    The font is copied from the repo (music938-1/fonts/NotoSansThai.ttf), not
    apt-installed: apt has no working network here, and the copy is instant. It
    goes to ~/.fonts, which is on the container overlay and is re-created here on
    every recycle. A running Chromium caches the font list, so this reports
    `changed` when it had to install, and the caller restarts Chromium.
    """
    if sh(["fc-list", ":lang=th"]).stdout.strip():
        return False
    src = None
    for cand in (REPO / "music938-1" / "fonts" / "NotoSansThai.ttf",
                 Path("/workspace/ax-tools/fonts/NotoSansThai.ttf")):
        if cand.is_file():
            src = cand
            break
    dest = Path.home() / ".fonts"
    dest.mkdir(parents=True, exist_ok=True)
    if src is None:
        print("[!] no Thai font source found; Thai text will render as boxes")
        return False
    shutil.copy2(src, dest / src.name)
    sh(["fc-cache", "-f", str(dest)])
    print(f"[+] Thai font installed ({src.name})")
    return True


def ensure_x11_socket() -> None:
    """Create /tmp/.X11-unix, which a fresh pod leaves missing.

    `/tmp` is on the container overlay, so every recycle wipes it and Xvfb dies
    with "_XSERVTransmkdir: ERROR: euid != 0" and then reports DOWN forever. The
    dir is owned by root, so this needs sudo; it is the one thing that has to be
    root-owned, and it is what stopped the desktop from starting at all.
    """
    d = Path("/tmp/.X11-unix")
    if d.is_dir():
        return
    sh(["sudo", "mkdir", "-p", str(d)], check=False)
    sh(["sudo", "chmod", "1777", str(d)], check=False)
    if not d.is_dir():
        d.mkdir(parents=True, exist_ok=True)
    print("[+] /tmp/.X11-unix")


def ensure_pylibs() -> None:
    """Re-point Python at the libraries that live on /workspace.

    The wheels (numpy, playwright, websocket-client) are installed under
    /workspace/ax-tools/pylibs so they survive a recycle, but the `.pth` that puts
    them on `sys.path` lives in site-packages on the container overlay, which does
    not. After a recycle every script dies with `ModuleNotFoundError: numpy`, which
    reads as "the code is broken". Re-create the pointer instead.
    """
    libs = Path("/workspace/ax-tools/pylibs")
    if not libs.is_dir():
        return
    try:
        import subprocess
        site = subprocess.run(
            [sys.executable, "-c", "import site; print(site.getusersitepackages())"],
            capture_output=True, text=True).stdout.strip()
        if not site:
            return
        d = Path(site)
        d.mkdir(parents=True, exist_ok=True)
        pth = d / "ax-pylibs.pth"
        if not pth.exists() or pth.read_text().strip() != str(libs):
            pth.write_text(str(libs))
            print(f"[+] ax-pylibs.pth -> {libs}")
    except Exception as exc:  # noqa: BLE001
        print(f"[=] could not restore the pylibs path: {exc}")


def clear_stale_lock(profile: Path) -> None:
    """Remove a SingletonLock left by the pod that owned this volume before.

    The chrome profile lives on /workspace, which survives a recycle, but the
    lock records the *hostname and pid* of the old pod. A new pod sees a foreign
    lock and refuses to start Chrome ("profile appears to be in use ... on
    another computer"), so CDP never comes up. Deleting the lock is safe: it only
    names a process that no longer exists on this machine.
    """
    if not up(f"remote-debugging-port={CDP_PORT}"):
        for name in ("SingletonLock", "SingletonCookie", "SingletonSocket"):
            p = profile / name
            if p.is_symlink() or p.exists():
                p.unlink(missing_ok=True)
                print(f"[+] cleared stale {name}")
        (profile / "Default" / "DevToolsActivePort").unlink(missing_ok=True)


def start() -> None:
    log = STATE / "logs"
    profile = STATE / "chrome-profile"
    profile.mkdir(parents=True, exist_ok=True)
    (STATE / "run").mkdir(parents=True, exist_ok=True)
    ensure_x11_socket()
    ensure_pylibs()
    # Before Chromium, and restart it if the font had to be added: a running
    # Chromium caches the font list, so a late install would not show up until
    # the next recycle — which is exactly how K got a screen of tofu boxes.
    if ensure_thai_fonts() and up(f"remote-debugging-port={CDP_PORT}"):
        print("[+] restarting chromium to pick up the Thai font")
        sh(["pkill", "-f", f"remote-debugging-port={CDP_PORT}"])
        time.sleep(4)
    clear_stale_lock(profile)

    if not up(f"Xvfb {DISPLAY}"):
        spawn(["Xvfb", DISPLAY, "-screen", "0", SCREEN, "-ac", "-nolisten", "tcp"],
              log / "xvfb.log")
        time.sleep(2)
        print("[+] Xvfb", DISPLAY)
    if not up("openbox"):
        env = {**os.environ, "DISPLAY": DISPLAY}
        spawn(["openbox"], log / "openbox.log", env)
        time.sleep(1)
        print("[+] openbox")
    if not up(f"x11vnc -display {DISPLAY}"):
        passfile = STATE / "vnc.pass"
        auth = ["-rfbauth", str(passfile)] if passfile.exists() else ["-nopw"]
        spawn(["x11vnc", "-display", DISPLAY, *auth, "-rfbport", str(VNC_PORT),
               "-forever", "-shared", "-repeat", "-noxdamage", "-xkb",
               # Lets noVNC's `resize=remote` actually resize the framebuffer to
               # the client. Without it a 1600x900 desktop is shrunk onto a phone
               # and the text is unreadable; with it the desktop becomes the
               # phone's shape and the text is native size.
               "-xrandr"],
              log / "x11vnc.log")
        time.sleep(2)
        print("[+] x11vnc", VNC_PORT)
    if not up(f"websockify.*{NOVNC_PORT}"):
        spawn(["websockify", f"--web={NOVNC_WEB}", str(NOVNC_PORT),
               f"localhost:{VNC_PORT}"], log / "novnc.log")
        time.sleep(2)
        print("[+] websockify", NOVNC_PORT)
    if not up(f"remote-debugging-port={CDP_PORT}"):
        env = {**os.environ, "DISPLAY": DISPLAY}
        spawn(["chromium", "--no-sandbox", "--disable-dev-shm-usage",
               "--no-first-run", "--no-default-browser-check",
               "--disable-features=Translate,MediaRouter",
               f"--user-data-dir={profile}",
               "--remote-debugging-address=127.0.0.1",
               f"--remote-debugging-port={CDP_PORT}",
               # Without this Chrome 403s every CDP websocket and Playwright cannot attach.
               "--remote-allow-origins=*",
               "--window-size=1500,860", "--lang=th-TH",
               "https://accounts.google.com/"], log / "chrome.log", env)
        time.sleep(6)
        print("[+] chromium (CDP", CDP_PORT, ")")


def status() -> int:
    ok = True
    for pattern, label in ((f"Xvfb {DISPLAY}", "Xvfb"), ("openbox", "openbox"),
                           (f"x11vnc -display {DISPLAY}", "x11vnc"),
                           (f"websockify.*{NOVNC_PORT}", "websockify"),
                           (f"remote-debugging-port={CDP_PORT}", "chromium")):
        alive = up(pattern)
        ok = ok and alive
        print(f"{'UP  ' if alive else 'DOWN'} {label}")
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/version", timeout=8) as r:
            import json
            print("CDP:", json.load(r).get("Browser"))
    except Exception as exc:
        ok = False
        print("CDP: unreachable —", exc)
    return 0 if ok else 1


def _vault_path() -> Path:
    return Path(__file__).resolve().parents[4] / "ops" / "login_vault.py"


def restore_bookmarks() -> None:
    """Put K's bookmark bar back after Chrome starts. Best-effort, like restore_login.

    Runs *after* Chromium is up on purpose: the restore goes through Chrome's own
    bookmark API over CDP. A hand-written `Bookmarks` file is dropped because
    Chrome verifies a checksum it cannot reproduce from that file, which is what
    silently lost the bar once.
    """
    vault = _vault_path()
    if not vault.exists():
        return
    # Same reasoning as restore_login: the vault authenticates itself, so the
    # OPENHANDS_API_KEY gate that used to sit here only ever skipped a restore
    # that would have worked.
    try:
        r = sh([sys.executable, str(vault), "restore-bookmarks"], timeout=60)
    except Exception as exc:  # noqa: BLE001
        print("[=] bookmark restore skipped:", exc)
        return
    line = (r.stdout or "").strip().splitlines()
    if line and not line[0].startswith("no saved"):
        print("[+] bookmark restore:", line[0])


def show_bookmark_bar() -> None:
    """Make Chrome show the bookmark bar on every tab.

    Chrome's default is to hide the bar on the new-tab page and show it only on
    the bookmarks manager, so K sees an empty bar and reads it as "the bookmarks
    are gone". Best-effort.
    """
    profile = Path(os.environ.get(
        "AERIS_CHROME_PROFILE",
        "/workspace/ax-tools/aeris938-state/chrome-profile/Default"))
    prefs = profile / "Preferences"
    if not prefs.exists():
        return
    try:
        data = json.loads(prefs.read_text(encoding="utf-8"))
        if data.get("bookmark_bar", {}).get("show_on_all_tabs") is True:
            return
        data["bookmark_bar"] = {"show_on_all_tabs": True}
        prefs.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        print("[+] bookmark bar set to always show")
    except Exception as exc:  # noqa: BLE001
        print("[=] bookmark-bar preference skipped:", exc)


def restore_login() -> None:
    """Put the saved session back, so K does not sign in again after a fresh pod.

    Best-effort: a brand-new account with no snapshot, or a CDP hiccup, must not
    stop the desktop from coming up. It only ever adds cookies that were saved
    from this same account.
    """
    vault = _vault_path()
    if not vault.exists():
        return
    # Do NOT gate this on OPENHANDS_API_KEY. The vault resolves its own anchor
    # through ax_vault, which reads the durable KV store with the anchor id in
    # AX_VAULT_BOOTSTRAP; OPENHANDS_API_KEY is not part of that path. Requiring
    # it here meant the saved session was never restored in a normal pod, so K
    # had to sign in again after every recycle even though the snapshot existed
    # (verified 2026-11-06: `login_vault.py restore` works with the key unset).
    try:
        r = sh([sys.executable, str(vault), "restore"], timeout=120)
    except Exception as exc:  # noqa: BLE001
        print("[=] login restore skipped:", exc)
        return
    out = (r.stdout or "").strip().splitlines()
    if r.returncode == 0 and out:
        print("[+] login restored:", out[0])
    elif "no saved session" in (r.stderr or ""):
        print("[=] no saved login yet (sign in once, then: login_vault.py save)")
    else:
        print("[=] login restore FAILED:", (r.stderr or r.stdout or "").strip()[:300])


def operator_url() -> str | None:
    """The noVNC URL for this sandbox, built from the environment.

    The host is `work-1-<RUNTIME_ID>...`; `RUNTIME_ID` is the same string that
    appears in the session's work_hosts block, so it can be built here instead of
    being copied by hand (which is how it was missed before). Returns None when
    the variable is absent, and the caller falls back to the placeholder.
    """
    rid = os.environ.get("RUNTIME_ID")
    if not rid:
        return None
    # `resize=remote` (not `scale`) so the desktop takes the phone's shape and the
    # text is native size instead of shrunk to fit. This needs x11vnc -xrandr,
    # which start() passes.
    return f"https://work-1-{rid}.prod-runtime.all-hands.dev/vnc.html?autoconnect=1&resize=remote"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--status", action="store_true", help="report only")
    ap.add_argument("--url", action="store_true", help="print the operator URL and exit")
    args = ap.parse_args()
    if args.url:
        url = operator_url()
        print(url or "RUNTIME_ID is not set; use https://work-1-<work-host>/vnc.html")
        if (STATE / "vnc.pass.txt").exists():
            print("VNC password:", (STATE / "vnc.pass.txt").read_text().strip())
        return 0
    STATE.mkdir(parents=True, exist_ok=True)
    if args.status:
        return status()
    install()
    # The bar preference must be in place before Chrome reads the profile; it
    # rewrites Preferences on exit, so setting it against a running browser is lost.
    show_bookmark_bar()
    start()
    restore_login()
    restore_bookmarks()
    print()
    rc = status()
    print("\noperator URL (sign in here, inside the desktop):")
    url = operator_url()
    print("  " + (url or "https://work-1-<work-host>/vnc.html?autoconnect=1&resize=scale"))
    if (STATE / "vnc.pass.txt").exists():
        print("  VNC password:", (STATE / "vnc.pass.txt").read_text().strip())
    else:
        print("  VNC password: none set (see scripts/set-vnc-password.sh)")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())

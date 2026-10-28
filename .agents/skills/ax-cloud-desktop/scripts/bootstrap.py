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
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

STATE = Path(os.environ.get("AERIS_STATE_DIR", "/workspace/ax-tools/aeris938-state"))
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


def start() -> None:
    log = STATE / "logs"
    profile = STATE / "chrome-profile"
    profile.mkdir(parents=True, exist_ok=True)
    (STATE / "run").mkdir(parents=True, exist_ok=True)

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
               "-forever", "-shared", "-repeat", "-noxdamage", "-xkb"],
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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--status", action="store_true", help="report only")
    args = ap.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    if args.status:
        return status()
    install()
    start()
    print()
    rc = status()
    print("\noperator URL (sign in here, inside the desktop):")
    print("  https://work-1-<work-host>/vnc.html?autoconnect=1&resize=scale")
    if (STATE / "vnc.pass.txt").exists():
        print("  VNC password:", (STATE / "vnc.pass.txt").read_text().strip())
    else:
        print("  VNC password: none set (see scripts/set-vnc-password.sh)")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""One command that answers "can the agent use the browser right now?".

The desktop is three independent things, and they fail separately:

* the live view (port 12001) — the page K and the agent both look at
* Chromium over CDP (port 9222) — what the agent actually drives
* the login inside that browser — the cookies, which outlive neither a pod
  replacement nor the site's own session lifetime

A check that only reads an HTTP code cannot tell them apart: `vnc.html` answers
200 with no VNC backend at all, and a live view answering 200 while Chromium is
gone still shows a dead picture. So each surface is verified by what it
*says* — the page title, the CDP browser string, the account email — and the
verdict names which one is down.

    python3 ops/desktop_watch.py             # report + verdict, rc 1 if unusable
    python3 ops/desktop_watch.py --heal      # bring the desktop back, then re-check
    python3 ops/desktop_watch.py --json out.json
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOOTSTRAP = ROOT / ".agents/skills/ax-cloud-desktop/scripts/bootstrap.py"
CHECK_LOGIN = ROOT / ".agents/skills/ax-cloud-desktop/scripts/check_login.py"

LIVE_VIEW = "http://127.0.0.1:12001"
CDP = "http://127.0.0.1:9222"
# The page the live view serves names itself. A 200 without this string is some
# other server that took the port, which is exactly the failure a code-only
# check reports as healthy.
LIVE_VIEW_TITLE = "AERIS — Live View"


def _get(url: str, timeout: float = 5.0) -> tuple[int, str]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read(200_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, ""
    except Exception:  # noqa: BLE001 - unreachable is a result, not a crash
        return 0, ""


def live_view() -> dict:
    code, body = _get(LIVE_VIEW + "/")
    titled = LIVE_VIEW_TITLE in body
    health: dict = {}
    hcode, hbody = _get(LIVE_VIEW + "/health")
    if hcode == 200 and hbody.strip().startswith("{"):
        try:
            health = json.loads(hbody)
        except ValueError:
            health = {}
    return {"http": code, "identity": titled, "health": health,
            "ok": code == 200 and titled}


def cdp() -> dict:
    code, body = _get(CDP + "/json/version")
    browser = ""
    if code == 200 and body.strip().startswith("{"):
        try:
            browser = json.loads(body).get("Browser", "")
        except ValueError:
            browser = ""
    lcode, lbody = _get(CDP + "/json/list")
    pages = 0
    if lcode == 200 and lbody.strip().startswith("["):
        try:
            pages = len([p for p in json.loads(lbody) if p.get("type") == "page"])
        except ValueError:
            pages = 0
    return {"http": code, "browser": browser, "pages": pages,
            "ok": code == 200 and bool(browser) and pages > 0}


def login() -> dict:
    if not CHECK_LOGIN.exists():
        return {"state": "unknown", "account": "", "ok": False}
    try:
        r = subprocess.run([sys.executable, str(CHECK_LOGIN)], capture_output=True,
                           text=True, timeout=180, cwd=str(ROOT))
    except Exception as exc:  # noqa: BLE001 - a timeout is "unknown", not healthy
        return {"state": "unknown", "account": "", "ok": False,
                "detail": type(exc).__name__}
    out = (r.stdout or "") + (r.stderr or "")
    m = re.search(r"RESULT=(SIGNED_IN|SIGNED_OUT|WRONG_ACCOUNT)\b(?:[^\n]*?account=([^\s]+))?",
                  out)
    if not m:
        return {"state": "unknown", "account": "", "ok": False,
                "detail": out.strip().splitlines()[-1][:120] if out.strip() else ""}
    state, account = m.group(1).lower(), (m.group(2) or "")
    return {"state": state, "account": account, "ok": state == "signed_in"}


def legacy() -> dict:
    """noVNC/x11vnc are the old route; report them, never rely on them."""
    r = subprocess.run(["bash", "-lc", "ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null"],
                       capture_output=True, text=True)
    ports = r.stdout
    return {"novnc_12000": ":12000" in ports, "x11vnc_5900": ":5900" in ports}


def verdict_of(lv: dict, br: dict, lg: dict) -> str:
    """Name the failure. A dead browser and a dead login are different jobs:
    the first is ours to repair, the second needs K once."""
    if not lv["ok"] or not br["ok"]:
        return "DOWN"
    if lg["state"] == "signed_out":
        return "SIGNED_OUT"
    if lg["state"] == "wrong_account":
        return "WRONG_ACCOUNT"
    if not lg["ok"]:
        return "UNKNOWN_LOGIN"
    return "HEALTHY"


def report() -> dict:
    lv, br, lg = live_view(), cdp(), login()
    return {"verdict": verdict_of(lv, br, lg), "live_view": lv, "chromium": br,
            "login": lg, "legacy": legacy()}


def show(d: dict) -> None:
    lv, br, lg = d["live_view"], d["chromium"], d["login"]
    print(f"live view : {'OK' if lv['ok'] else 'DOWN'} "
          f"(http {lv['http']}, identity {'yes' if lv['identity'] else 'NO'})")
    print(f"chromium  : {'OK' if br['ok'] else 'DOWN'} "
          f"({br['browser'] or 'no CDP'}, {br['pages']} page(s))")
    print(f"login     : {lg['state']}" + (f" ({lg['account']})" if lg.get("account") else ""))
    if lg.get("detail"):
        print(f"            {lg['detail']}")
    print(f"legacy    : noVNC={'on' if d['legacy']['novnc_12000'] else 'off'} "
          f"x11vnc={'on' if d['legacy']['x11vnc_5900'] else 'off'}")
    print(f"verdict   : {d['verdict']}")


def heal() -> int:
    """Bring the desktop up the documented way, then re-check once."""
    print("heal: bootstrap.py (start -> live view -> vault restore)")
    r = subprocess.run([sys.executable, str(BOOTSTRAP)], cwd=str(ROOT),
                       capture_output=True, text=True, timeout=1800)
    tail = (r.stdout or "").strip().splitlines()[-1:] or [""]
    print(f"  bootstrap rc={r.returncode} {tail[0][:100]}")
    d = report()
    show(d)
    return 0 if d["verdict"] == "HEALTHY" else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--heal", action="store_true",
                    help="run bootstrap.py when a surface is down, then re-check")
    ap.add_argument("--json", help="write the full report here")
    args = ap.parse_args()
    d = report()
    if args.json:
        Path(args.json).write_text(json.dumps(d, ensure_ascii=False, indent=2))
    if d["verdict"] != "HEALTHY" and args.heal:
        return heal()
    show(d)
    # A dead login is not a dead desktop: the agent can still drive the browser,
    # so only a broken surface fails the check. K is told about the login.
    return 0 if d["verdict"] in ("HEALTHY", "SIGNED_OUT", "WRONG_ACCOUNT",
                                 "UNKNOWN_LOGIN") else 1


if __name__ == "__main__":
    raise SystemExit(main())

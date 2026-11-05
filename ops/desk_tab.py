#!/usr/bin/env python3
"""Run a JS snippet in a named cloud-desktop tab over CDP.

A thin probe so the agent can read what a tab actually shows (logged in or not)
without a Playwright round trip. Read-only by default; `--click` exists for the
one case where a click is the point (focusing a password field so Chrome offers
the operator's saved password).

    python3 ops/desk_tab.py list
    python3 ops/desk_tab.py eval --match facebook --js "document.title"
    python3 ops/desk_tab.py eval --match facebook --js "..." --click "input[type=password]"
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request

CDP = "http://127.0.0.1:9222"


def pages() -> list[dict]:
    return [t for t in json.load(urllib.request.urlopen(f"{CDP}/json", timeout=10))
            if t.get("type") == "page"]


def connect(match: str):
    import websocket  # noqa: PLC0415

    page = next((t for t in pages() if match in t.get("url", "").lower()
                 or match in t.get("title", "").lower()), None)
    if page is None:
        raise SystemExit(f"no tab matching {match!r}")
    return websocket.create_connection(page["webSocketDebuggerUrl"], timeout=60), page


def run(ws, expr: str, await_: bool = False):
    ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                        "params": {"expression": expr, "returnByValue": True,
                                   "awaitPromise": await_}}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("id") == 1:
            return msg.get("result", {}).get("result", {}).get("value")


def open_tab(url: str) -> None:
    req = urllib.request.Request(f"{CDP}/json/new?{urllib.parse.quote(url, safe='')}",
                                 method="PUT")
    urllib.request.urlopen(req, timeout=10).read()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    sub.add_parser("open").add_argument("url")
    ev = sub.add_parser("eval")
    ev.add_argument("--match", required=True)
    ev.add_argument("--js", required=True)
    ev.add_argument("--click", default="")
    ev.add_argument("--wait", type=float, default=0.0)
    a = ap.parse_args()

    if a.cmd == "list":
        for t in pages():
            print(f"{t.get('title','')[:44]:44} | {t.get('url','')[:80]}")
        return 0
    if a.cmd == "open":
        open_tab(a.url)
        print("opened", a.url)
        return 0

    ws, page = connect(a.match)
    try:
        if a.click:
            # Focus the field so Chrome's saved-password dropdown can appear; the
            # click only focuses, it never types a credential.
            run(ws, f"(() => {{ const e = document.querySelector({json.dumps(a.click)});"
                    f" if (!e) return 'no-field'; e.focus(); e.click(); return 'clicked'; }})()")
            import time
            time.sleep(a.wait or 1.2)
        print(run(ws, a.js))
    finally:
        ws.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

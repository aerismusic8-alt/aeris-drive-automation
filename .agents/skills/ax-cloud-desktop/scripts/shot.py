#!/usr/bin/env python3
"""Screenshot the desktop browser over CDP:  python3 shot.py /tmp/desk.png

Playwright has a screenshot API, but this needs only the stdlib plus
websocket-client, so it still works when Playwright is not installed yet.
"""
import base64
import json
import sys
import urllib.request

import websocket

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/desk.png"
tabs = json.load(urllib.request.urlopen("http://127.0.0.1:9222/json"))
page = next(t for t in tabs if t["type"] == "page")
ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=20)
ws.send(json.dumps({"id": 1, "method": "Page.captureScreenshot",
                    "params": {"format": "png"}}))
while True:
    msg = json.loads(ws.recv())
    if msg.get("id") == 1:
        with open(out, "wb") as fh:
            fh.write(base64.b64decode(msg["result"]["data"]))
        print(f"[+] {out}")
        break
ws.close()

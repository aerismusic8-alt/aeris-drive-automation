#!/usr/bin/env python3
"""Upload ax-helper.cs to PC1 and rebuild ax-helper.dll.

The C# is far too large for a single remote command line, so it goes up as base64
in pieces and is decoded on the far side, where csc compiles it into the DLL that
every other script loads.

Run this after editing ax-helper.cs; nothing else needs rebuilding.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CHUNK = 3000


class Channel:
    def __init__(self, base: str, token: str, timeout: float = 60.0):
        self.base = base.rstrip("/") + "/"
        self.token = token
        self.timeout = timeout

    def _req(self, method: str, path: str, payload: dict | None = None) -> dict:
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("X-AX-Token", self.token)
        if data:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            return json.load(resp)

    def call(self, tool: str, args: dict, wait: float = 120.0) -> dict:
        job = self._req("POST", "ax/enqueue", {"tool": tool, "args": args})["job"]
        jid = job["id"]
        deadline = time.time() + wait
        while time.time() < deadline:
            hit = self._req("GET", "ax/state")["results"].get(jid)
            if hit:
                return hit
            time.sleep(2)
        return {"ok": False, "error": f"no result for {jid} within {wait}s"}

    @staticmethod
    def text_of(result: dict) -> str:
        out = []
        for item in result.get("content") or []:
            if item.get("type") == "text":
                out.append(item.get("text", ""))
        return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload and build ax-helper.dll on PC1")
    parser.add_argument("--rendezvous", required=True)
    parser.add_argument("--token", default=None)
    parser.add_argument("--source", default=os.path.join(HERE, "windows", "ax-helper.cs"))
    parser.add_argument("--build-script", default=os.path.join(HERE, "windows", "ax-build-helper.ps1"))
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    token = args.token or os.environ.get("AX_TOKEN")
    if not token:
        token_file = os.path.join(HERE, "ax-results", ".ax-token")
        with open(token_file, encoding="utf-8") as fh:
            token = fh.read().strip()

    ch = Channel(args.rendezvous, token)
    with open(args.source, "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()

    remote = r"C:\AX-Runtime\evidence\ax-helper.cs.b64"
    for i in range(0, len(b64), CHUNK):
        payload = {"path": remote, "content": b64[i : i + CHUNK]}
        if i:
            payload["append"] = True
        res = ch.call("FileWrite", payload, wait=60)
        if not res.get("ok"):
            print(f"upload failed at {i}: {ch.text_of(res)}", file=sys.stderr)
            return 1
    print(f"uploaded {len(b64)} chars")

    # Compile through the same detached-and-poll path used for other scripts,
    # because csc can take longer than the 30 second cap on a remote command.
    import subprocess

    proc = subprocess.run(
        [sys.executable, os.path.join(HERE, "ax-push-script.py"),
         args.build_script, "--rendezvous", args.rendezvous,
         "--timeout", str(args.timeout)],
        capture_output=True, text=True,
    )
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())

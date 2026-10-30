#!/usr/bin/env python3
"""Drive the PC1 desktop directly: see the screen, then use the mouse and keyboard.

This is the route K remembers. PC1's winremote MCP is reachable from the sandbox
over the tailnet, so no GitHub workflow and no GitHub write token are needed:

    https://desktop-rgk6jkb.tail8740ad.ts.net/health   -> 200 {"status":"ok"}
    https://desktop-rgk6jkb.tail8740ad.ts.net/mcp      -> 401 without a key (healthy)

The key is `PC1_MCP_TOKEN_2`. 401 means "answering, wants a token", not "down".

    python3 ops/pc1_live.py doctor
    python3 ops/pc1_live.py tools
    python3 ops/pc1_live.py shot [out.png]
    python3 ops/pc1_live.py call Snapshot '{"max_width":1280}'
    python3 ops/pc1_live.py call Click '{"x":640,"y":400}'
    python3 ops/pc1_live.py call Type '{"text":"hello"}'

Traps this handles, each of which produced a confusing failure first:
  * the reply is an SSE stream (`event: message` / `data: {...}`), not plain JSON;
  * the session id comes back in a header on `initialize` and must be echoed as
    `mcp-session-id` on every later call, or every call answers
    `400 Bad Request: Missing session ID` -- which looks like a bad token;
  * header names must be matched case-insensitively (`Mcp-Session-Id`);
  * `initialize` needs a follow-up `notifications/initialized` before any call.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import struct
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("PC1_MCP_URL", "https://desktop-rgk6jkb.tail8740ad.ts.net")
URL = BASE.rstrip("/") + "/mcp"
HEALTH = BASE.rstrip("/") + "/health"


def key() -> str:
    for name in ("PC1_MCP_TOKEN_2", "PC1_MCP_TOKEN"):
        v = os.environ.get(name)
        if v:
            return v
    raise SystemExit("no PC1_MCP_TOKEN_2 / PC1_MCP_TOKEN in this session")


class PC1:
    def __init__(self, url: str = URL, tok: str | None = None, timeout: int = 120):
        self.url, self.tok, self.timeout = url, tok or key(), timeout
        self.sid: str | None = None
        self._id = 0

    def _post(self, payload: dict) -> tuple[int, dict, str]:
        h = {"Authorization": f"Bearer {self.tok}",
             "Content-Type": "application/json",
             "Accept": "application/json, text/event-stream"}
        if self.sid:
            h["mcp-session-id"] = self.sid
        req = urllib.request.Request(self.url, data=json.dumps(payload).encode(),
                                     method="POST", headers=h)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as f:
                return f.status, {k.lower(): v for k, v in f.headers.items()}, f.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read().decode()

    @staticmethod
    def _unwrap(body: str) -> dict:
        """SSE frames arrive as `event: message` then `data: {json}`."""
        for line in body.splitlines():
            line = line.strip()
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        return json.loads(body or "{}")

    def connect(self):
        self._id += 1
        st, h, b = self._post({"jsonrpc": "2.0", "id": self._id, "method": "initialize",
                               "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                          "clientInfo": {"name": "ax-agent", "version": "1.0"}}})
        if st != 200:
            raise SystemExit(f"initialize failed: {st} {b[:200]}")
        self.sid = h.get("mcp-session-id")
        if not self.sid:
            raise SystemExit("initialize returned no mcp-session-id header")
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return self

    def call(self, tool: str, args: dict | None = None) -> dict:
        if not self.sid:
            self.connect()
        self._id += 1
        st, _, b = self._post({"jsonrpc": "2.0", "id": self._id, "method": "tools/call",
                               "params": {"name": tool, "arguments": args or {}}})
        j = self._unwrap(b)
        if "error" in j:
            raise SystemExit(f"{tool} error: {j['error']}")
        return j.get("result", {})

    def tools(self) -> list[str]:
        if not self.sid:
            self.connect()
        self._id += 1
        _, _, b = self._post({"jsonrpc": "2.0", "id": self._id, "method": "tools/list", "params": {}})
        return [t["name"] for t in self._unwrap(b).get("result", {}).get("tools", [])]


def save_images(result: dict, dest: str) -> list[str]:
    """Write any image content items to disk and return the paths.

    The server sends JPEG even though the content type says image/png, so the
    extension is chosen from the magic bytes rather than trusted from the reply.
    """
    out = []
    content = result.get("content") or []
    images = [c for c in content if c.get("type") == "image"]
    for i, item in enumerate(content, 1):
        if item.get("type") == "image":
            data = base64.b64decode(item["data"])
            ext = ".jpg" if data[:3] == b"\xff\xd8\xff" else ".png"
            p = dest if len(images) == 1 else f"{os.path.splitext(dest)[0]}-{i}{ext}"
            if len(images) == 1 and not p.lower().endswith(ext):
                p = os.path.splitext(p)[0] + ext
            open(p, "wb").write(data)
            dim = ""
            if data[:8] == b"\x89PNG\r\n\x1a\n":
                w, h = struct.unpack(">II", data[16:24]); dim = f"  {w}x{h}"
            elif data[:3] == b"\xff\xd8\xff":
                dim = jpeg_size(data)
            print(f"saved {p}  {len(data):,} B{('  ' + dim) if dim else ''}")
            out.append(p)
        elif item.get("type") == "text":
            print(item.get("text", "")[:1500])
    return out


def jpeg_size(data: bytes) -> str:
    """Walk the JPEG markers to the SOF frame, which carries the dimensions."""
    i = 2
    while i < len(data) - 9:
        if data[i] != 0xFF:
            i += 1
            continue
        m = data[i + 1]
        if m in (0xC0, 0xC1, 0xC2, 0xC3):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return f"{w}x{h}"
        if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7:
            i += 2
            continue
        i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    return ""


def doctor() -> int:
    print("PC1 live control — preconditions\n")
    ok = True
    try:
        with urllib.request.urlopen(HEALTH, timeout=20) as f:
            body = f.read().decode()
        print(f"  /health              : {f.status} {body.strip()[:80]}")
    except Exception as e:
        print(f"  /health              : DOWN ({str(e)[:80]})")
        ok = False
    try:
        p = PC1().connect()
        ts = p.tools()
        print(f"  MCP session          : ok ({len(ts)} tools)")
        for want in ("Snapshot", "Click", "Type", "Move", "Shortcut", "Shell"):
            print(f"  {want:20}: {'yes' if want in ts else 'NO'}")
            ok &= want in ts
        info = p.call("GetSystemInfo")
        for item in info.get("content") or []:
            if item.get("type") == "text":
                print("  GetSystemInfo        :", item["text"][:160])
    except SystemExit as e:
        print(f"  MCP session          : FAILED ({e})")
        ok = False
    print(f"\n  verdict: {'can see and click PC1' if ok else 'NOT READY'}")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="See and drive the PC1 desktop.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("doctor")
    sub.add_parser("tools")
    s = sub.add_parser("shot")
    s.add_argument("out", nargs="?", default="out/pc1-now.png")
    s.add_argument("--width", type=int, default=1600)
    c = sub.add_parser("call")
    c.add_argument("tool")
    c.add_argument("args", nargs="?", default="{}")
    c.add_argument("--save", help="save image content here")
    a = ap.parse_args()

    if a.cmd == "doctor":
        return doctor()
    p = PC1().connect()
    if a.cmd == "tools":
        for t in p.tools():
            print(" ", t)
        return 0
    if a.cmd == "shot":
        os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
        return 0 if save_images(p.call("Snapshot", {"max_width": a.width}), a.out) else 1
    if a.cmd == "call":
        res = p.call(a.tool, json.loads(a.args))
        dest = a.save or "out/pc1-call.png"
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        imgs = save_images(res, dest)
        if not imgs:
            for item in res.get("content") or []:
                if item.get("type") == "text":
                    print(item["text"][:4000])
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())

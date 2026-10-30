#!/usr/bin/env python3
"""Client for the PC1 Windows-remote MCP proxy (task AERIS-PC1-WINREMOTE-MCP-PROXY).

  python3 ops/pc1mcp.py tools
  python3 ops/pc1mcp.py call GetSystemInfo '{}'
  python3 ops/pc1mcp.py shell 'Get-ChildItem C:\\ax-work'

Reaches PC1 (DESKTOP-RGK6JKB) over https://app.all-hands.dev/mcp/mcp with a bearer
token. Traps this module handles, all of which produced FALSE SUCCESS before:
  * the proxy replies with an SSE stream, not plain JSON, so parse `data:` lines;
  * replies are prefixed `[task:<id>] ` so `startswith` parsing reads 0;
  * a 30 s call cap kills long work - run those detached and poll instead;
  * PowerShell 5.1 mangles Thai unless the script is written as UTF-8 WITH a BOM.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

URL = "https://app.all-hands.dev/mcp/mcp"


def token():
    for name in ("PC1_MCP_TOKEN_2", "PC1_MCP_TOKEN"):
        t = os.environ.get(name)
        if t:
            return t
    raise SystemExit("no PC1_MCP_TOKEN(_2) in this session")


class MCP:
    def __init__(self, url=URL, tok=None, timeout=180):
        self.url, self.timeout = url, timeout
        self.tok = tok or token()
        self.sid = None
        self._id = 0
        self._rpc("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "ax-pc1", "version": "1"}})
        self._notify("notifications/initialized")

    def _post(self, payload):
        h = {"Content-Type": "application/json",
             "Accept": "application/json, text/event-stream",
             "Authorization": f"Bearer {self.tok}"}
        if self.sid:
            h["Mcp-Session-Id"] = self.sid
        req = urllib.request.Request(self.url, data=json.dumps(payload).encode(),
                                     headers=h, method="POST")
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as f:
                    if f.headers.get("Mcp-Session-Id"):
                        self.sid = f.headers["Mcp-Session-Id"]
                    return f.read().decode(errors="replace")
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                    time.sleep(2 * (attempt + 1) ** 2)
                    continue
                raise
        raise RuntimeError("unreachable")

    @staticmethod
    def _parse(raw):
        """The proxy answers as SSE; the payload is on the `data:` line."""
        out = None
        for line in raw.splitlines():
            line = line.strip()
            if line.startswith("data:"):
                try:
                    out = json.loads(line[5:].strip())
                except Exception:
                    pass
        if out is None:
            try:
                out = json.loads(raw)
            except Exception:
                out = {"raw": raw}
        return out

    def _rpc(self, method, params=None):
        self._id += 1
        d = self._parse(self._post({"jsonrpc": "2.0", "id": self._id,
                                    "method": method, "params": params or {}}))
        if "error" in d:
            raise RuntimeError(f"{method} -> {d['error']}")
        return d.get("result", d)

    def _notify(self, method, params=None):
        self._post({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def tools(self):
        return self._rpc("tools/list").get("tools", [])

    def call(self, name, args=None):
        res = self._rpc("tools/call", {"name": name, "arguments": args or {}})
        return _flatten(res)


def _flatten(res):
    """Unwrap MCP content blocks and strip the `[task:<id>] ` reply prefix."""
    if isinstance(res, dict) and "content" in res:
        parts = []
        for c in res["content"]:
            if isinstance(c, dict):
                parts.append(c.get("text") or json.dumps(c, ensure_ascii=False))
            else:
                parts.append(str(c))
        text = "\n".join(parts)
    else:
        text = res if isinstance(res, str) else json.dumps(res, ensure_ascii=False)
    return re.sub(r"^\s*\[task:[^\]]+\]\s*", "", text)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    m = MCP()
    if a[0] == "tools":
        for t in m.tools():
            print(f"  {t['name']:28s} {t.get('description','')[:80]}")
    elif a[0] == "call":
        args = json.loads(a[2]) if len(a) > 2 else {}
        print(m.call(a[1], args))
    elif a[0] == "shell":
        print(m.call("Shell", {"command": a[1]}))
    elif a[0] == "sysinfo":
        print(m.call("GetSystemInfo", {}))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()

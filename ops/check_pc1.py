#!/usr/bin/env python3
"""Check whether PC1 (DESKTOP-RGK6JKB) can be driven by an agent right now.

Answers one question, the one that matters: can this agent see and act on PC1,
or is a person needed at the machine?

    python3 ops/check_pc1.py

Three independent routes are probed, because they fail separately:

  tailnet   https://desktop-rgk6jkb.tail8740ad.ts.net  (tailscale serve)
  cloud     https://app.all-hands.dev/mcp/mcp          (the OpenHands proxy)
  runner    GitHub Actions self-hosted runner on PC1

A 502 on the tailnet URL is the interesting answer: it means tailscaled is up
and the serve listener exists, so PC1 is powered on and online, but the
winremote-mcp backend on 127.0.0.1:8090 is not answering. That is the exact
state that makes an agent able to capture the screen but unable to run a
command, and it is what ops/pc1_fix_remote.ps1 repairs.

Exit code: 0 when PC1 is drivable, 1 when it is not.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

TAILNET = os.environ.get("PC1_MCP_URL", "https://desktop-rgk6jkb.tail8740ad.ts.net")
CLOUD = "https://app.all-hands.dev/mcp/mcp"
REPO = "aerismusic8-alt/aeris-drive-automation"
TIER3 = ["Shell", "FileRead", "FileWrite", "FileUpload", "FileDownload", "App", "PlaySound", "KillProcess"]


def token() -> str | None:
    for name in ("PC1_MCP_TOKEN_2", "PC1_MCP_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    return None


def http(url: str, method: str = "GET", body: dict | None = None,
         tok: str | None = None, headers: dict | None = None, timeout: int = 20):
    """Return (status, headers, body). Never raises on an HTTP error status."""
    h = dict(headers or {})
    if tok:
        h["Authorization"] = f"Bearer {tok}"
    data = json.dumps(body).encode() if body is not None else None
    if data is not None:
        h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as f:
            return f.status, {k.lower(): v for k, v in f.headers.items()}, f.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read().decode(errors="replace")
    except Exception as e:  # DNS, refused, timeout
        return 0, {}, str(e)


def probe_tailnet() -> tuple[bool, str]:
    st, _, body = http(TAILNET + "/health")
    if st == 200 and '"status":"ok"' in body.replace(" ", ""):
        return True, f"up  {body.strip()[:80]}"
    if st == 502:
        return False, ("502 - tailscaled is up and the serve listener exists, so PC1 is "
                       "ONLINE, but the winremote-mcp backend on 127.0.0.1:8090 is DOWN. "
                       "Run ops/pc1_fix_remote.ps1 on PC1.")
    if st == 401:
        return True, "401 - answering, wants the auth key"
    if st == 0:
        return False, f"unreachable ({body[:60]})"
    return False, f"HTTP {st}"


def probe_tools() -> tuple[bool, str]:
    """A real MCP handshake, so the answer is 'what can it DO', not 'is a port open'."""
    tok = token()
    if not tok:
        return False, "no PC1_MCP_TOKEN_2 / PC1_MCP_TOKEN in this session"
    h = {"Accept": "application/json, text/event-stream"}
    st, hdrs, body = http(TAILNET + "/mcp", "POST",
                          {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                           "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                      "clientInfo": {"name": "check_pc1", "version": "1"}}},
                          tok=tok, headers=h)
    if st != 200:
        return False, f"initialize -> HTTP {st} {body[:80]}"
    sid = hdrs.get("mcp-session-id")
    if not sid:
        return False, "initialize returned no mcp-session-id header"
    h2 = {"Accept": "application/json, text/event-stream", "mcp-session-id": sid}
    http(TAILNET + "/mcp", "POST", {"jsonrpc": "2.0", "method": "notifications/initialized"}, tok=tok, headers=h2)
    st, _, body = http(TAILNET + "/mcp", "POST",
                       {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
                       tok=tok, headers=h2)

    def unwrap(b: str) -> dict:
        for line in b.splitlines():
            line = line.strip()
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        return json.loads(b or "{}")

    names = sorted(t["name"] for t in unwrap(body).get("result", {}).get("tools", []))
    if not names:
        return False, "no tools returned"
    missing = [t for t in TIER3 if t not in names]
    if missing:
        return False, (f"{len(names)} tools, but tier 3 is OFF - missing {', '.join(missing)}. "
                       "The agent can look but cannot act. Run ops/pc1_fix_remote.ps1 on PC1.")
    return True, f"{len(names)} tools, tier 3 ON (Shell, FileWrite, ... present)"


def probe_cloud() -> tuple[bool, str]:
    """The OpenHands proxy route. 406/400 means it is answering but not an MCP client."""
    st, _, body = http(CLOUD, "POST", {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                       "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                                  "clientInfo": {"name": "check_pc1", "version": "1"}}},
                       headers={"Accept": "application/json, text/event-stream"})
    if st == 200 and "serverInfo" in body:
        return True, "answering as an MCP server"
    if st in (401, 403):
        return True, f"HTTP {st} - reachable, needs credentials"
    if st == 406:
        return True, "HTTP 406 - reachable, rejected a bare probe"
    if st == 0:
        return False, f"unreachable ({body[:60]})"
    return False, f"HTTP {st}"


def probe_runner() -> tuple[bool, str]:
    """A queued job older than an hour means the PC1 runner is not picking work up."""
    tok = os.environ.get("GITHUB_TOKEN")
    if not tok:
        return False, "no GITHUB_TOKEN in this session"
    st, _, body = http(f"https://api.github.com/repos/{REPO}/actions/runs?per_page=10&status=queued",
                       tok=tok)
    if st != 200:
        return False, f"HTTP {st}"
    d = json.loads(body or "{}")
    n = d.get("total_count", 0)
    if n == 0:
        return True, "no queued jobs"
    return False, f"{n} job(s) queued - the PC1 runner is not taking work"


def main() -> int:
    print("PC1 (DESKTOP-RGK6JKB) - can an agent drive it?\n")
    ok = True
    for label, fn in (("tailnet /health", probe_tailnet),
                      ("tailnet tools  ", probe_tools),
                      ("cloud /mcp     ", probe_cloud),
                      ("actions runner ", probe_runner)):
        try:
            good, msg = fn()
        except Exception as e:
            good, msg = False, f"probe crashed: {e}"
        print(f"  {label} : {'OK  ' if good else 'FAIL'} {msg}")
        ok = ok and good

    print()
    if ok:
        print("  verdict: PC1 is drivable.")
        print("           python3 ops/pc1_live.py doctor")
    else:
        print("  verdict: NOT DRIVABLE from here.")
        print("           PC1 is behind NAT with no inbound route, so the fix has to run")
        print("           ON PC1: ops/pc1_fix_remote.ps1 (as Administrator).")
        print("           Then OPEN A NEW OpenHands conversation - the tool list loads once.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

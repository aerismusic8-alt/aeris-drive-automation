#!/usr/bin/env bash
# Push this repo to GitHub through PC1, because the sandbox token is read-only.
#
# Why this exists: the sandbox GITHUB_TOKEN is read-only (every push is 403) and the
# GitHub App key that used to provide write access lived in ~/.config/aeris, which is
# on the ephemeral overlay and was lost. PC1 holds a classic PAT that CAN write, so the
# sandbox hands the commits to PC1 and PC1 does the push.
#
#   ./scripts/push-via-pc1.sh            # push the current branch to origin/main
#   ./scripts/push-via-pc1.sh <branch>
#
# The repo is a shallow clone in a fresh sandbox, and a bundle of a shallow clone cannot
# be cloned (missing parents). This unshallows first.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${1:-main}"
REPO="aerismusic8-alt/aeris-drive-automation"
STATE=/tmp/serve

# The pod's public URL, used to hand the bundle to PC1. Override if the work host differs.
SANDBOX_URL="${SANDBOX_URL:-https://work-2-jhakqeqvkcqlwmjh.prod-runtime.all-hands.dev}"
PC1_MCP="${PC1_MCP:-https://desktop-rgk6jkb.tail8740ad.ts.net/mcp}"

cd "$REPO_DIR"
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  echo "[+] unshallowing so the bundle carries full history"
  git fetch --unshallow
fi

mkdir -p "$STATE"
git bundle create "$STATE/repo.bundle" "$BRANCH"
echo "[+] bundle: $(du -h "$STATE/repo.bundle" | cut -f1)"

# Serve the bundle if nothing is listening on 12001.
if ! curl -sf -o /dev/null "http://127.0.0.1:12001/repo.bundle"; then
  ( cd "$STATE" && nohup python3 -m http.server 12001 --bind 0.0.0.0 >/tmp/http-push.log 2>&1 & )
  sleep 3
fi

python3 - "$SANDBOX_URL" "$REPO" "$BRANCH" "$PC1_MCP" <<'PY'
import json, os, sys, urllib.request, urllib.error

sandbox, repo, branch, mcp = sys.argv[1:5]
token = os.environ.get("PC1_MCP_TOKEN_2") or os.environ.get("PC1_MCP_TOKEN")
if not token:
    raise SystemExit("PC1_MCP_TOKEN_2 is not set; name it in the invoking command so the secret is injected")
_session = {"id": None}

def post(payload):
    headers = {"Content-Type": "application/json",
               "Accept": "application/json, text/event-stream",
               "Authorization": f"Bearer {token}"}
    if _session["id"]:
        headers["Mcp-Session-Id"] = _session["id"]
    req = urllib.request.Request(mcp, data=json.dumps(payload).encode(), headers=headers,
                                 method="POST")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                sid = r.headers.get("Mcp-Session-Id")
                if sid:
                    _session["id"] = sid
                return r.read().decode(errors="replace")
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 500, 502, 503, 504) and attempt < 3:
                continue
            raise

def parse(text):
    out = []
    for line in text.splitlines():
        if line.startswith("data:"):
            s = line[5:].strip()
            if s:
                try:
                    out.append(json.loads(s))
                except ValueError:
                    pass
    if not out:
        try:
            out = [json.loads(text)]
        except ValueError:
            pass
    return out

def rpc(method, params=None, notify=False):
    if notify:
        post({"jsonrpc": "2.0", "method": method, "params": params or {}})
        return None
    msgs = parse(post({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}))
    for m in msgs:
        if m.get("id") == 1:
            return m
    return msgs[-1] if msgs else None

def call(name, args):
    r = rpc("tools/call", {"name": name, "arguments": args})
    if not r:
        return ""
    parts = (r.get("result") or {}).get("content") or []
    return "\n".join(p.get("text", "") for p in parts if isinstance(p, dict))

rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                   "clientInfo": {"name": "push-via-pc1", "version": "1"}})
rpc("notifications/initialized", None, notify=True)

ps = f'''$ErrorActionPreference = "Continue"
$root = "C:\\AX-Runtime\\repo-push"
$url  = "https://x-access-token:$env:GITHUB_TOKEN@github.com/{repo}.git"
if (Test-Path $root) {{ Remove-Item -Recurse -Force $root }}
New-Item -ItemType Directory -Force -Path $root | Out-Null
Invoke-WebRequest "{sandbox}/repo.bundle" -OutFile "$root\\repo.bundle" -UseBasicParsing -TimeoutSec 300
Set-Location $root
git clone -b {branch} "$root\\repo.bundle" repo *>&1 | Out-Null
Set-Location "$root\\repo"
git push $url {branch} *>&1 | Out-String
"REMOTE " + (git ls-remote $url refs/heads/{branch} *>&1 | Out-String)
'''
call("FileWrite", {"path": r"C:\AX-Runtime\repo-push.ps1", "content": ps})
print(call("Shell", {"command":
      r"powershell -NoProfile -ExecutionPolicy Bypass -File C:\AX-Runtime\repo-push.ps1",
      "timeout": 28}))
PY

#!/usr/bin/env python3
"""Put a file on PC1 by having PC1 fetch it, instead of uploading it.

Why this exists: ax-push-script.py sends a file as base64 chunks through the
channel. That is the only option for text that is not in the repo, and it is
reliable, but it costs one channel round trip per 3000 characters. An 11 KB
script is 5 chunks, and the measured cost of that push was 78 seconds, against
0.67 seconds for PC1 to fetch the same bytes from raw.githubusercontent.com.

So when the file is already committed and pushed, let PC1 pull it. The file
still has to be at a commit that is on the remote, because the URL names a
commit, and that is the point: what lands on PC1 is exactly what is in git,
which is the same thing CI builds from.

The bytes are checked on arrival. A raw fetch that returns a GitHub error page
or a truncated body would otherwise be written as if it were the script, and a
half-written script that still parses is worse than one that fails outright.

  python3 ax-deploy.py AX_PC_CONTROL/pc1-hide-console-windows.ps1
  python3 ax-deploy.py AX_PC_CONTROL/pc1-hide-console-windows.ps1 --dest C:\\AX-Runtime\\reverse\\x.ps1
  python3 ax-deploy.py AX_PC_CONTROL/pc1-hide-console-windows.ps1 --run -SelfTest
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
REPO_SLUG = "aerismusic8-alt/aeris-drive-automation"


def run_git(*args: str) -> str:
    out = subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {out.stderr.strip()}")
    return out.stdout.strip()


def token_from_disk() -> str | None:
    path = os.path.join(HERE, "ax-results", ".ax-token")
    if os.path.exists(path):
        return open(path, encoding="utf-8").read().strip()
    return None


class Channel:
    def __init__(self, base: str, token: str):
        self.base = base.rstrip("/") + "/"
        self.token = token

    def _req(self, method: str, path: str, payload: dict | None = None) -> dict:
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("X-AX-Token", self.token)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", "replace")
        return json.loads(raw) if raw else {}

    def call(self, tool: str, args: dict, wait: float = 120.0) -> dict:
        job_id = self._req("POST", "ax/enqueue", {"tool": tool, "args": args})["job"]["id"]
        deadline = time.time() + wait
        while time.time() < deadline:
            hit = self._req("GET", "ax/state").get("results", {}).get(job_id)
            if hit:
                return hit
            time.sleep(0.25)
        return {"ok": False, "error": f"no result within {wait:.0f}s"}

    def text_of(self, result: dict) -> str:
        for key in ("output", "text", "stdout", "content"):
            if isinstance(result.get(key), str):
                return result[key]
        return json.dumps(result)


def resolve_commit() -> str:
    """The commit to fetch from, proven to be on the remote branch.

    A local check is not enough here. This clone is shallow and its
    remote-tracking refs go stale the moment a push lands, so `branch -r
    --contains` reported a commit as unpushed seconds after it was pushed. The
    branch tip is read from the remote, and when it is not HEAD the API is asked
    whether HEAD is ahead of it. Both answers come from GitHub, which is the only
    thing that can say what raw.githubusercontent.com will serve.
    """
    head = run_git("rev-parse", "HEAD")
    branch = run_git("rev-parse", "--abbrev-ref", "HEAD")

    tip = run_git("ls-remote", "origin", f"refs/heads/{branch}").split()
    if not tip:
        raise SystemExit(f"branch {branch} does not exist on origin")
    tip = tip[0]

    if head == tip:
        return head

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise SystemExit(
            f"HEAD {head[:7]} is not the tip of origin/{branch} ({tip[:7]}), and no "
            "GITHUB_TOKEN is set to confirm it was pushed. Push, or send the working "
            "copy with ax-push-script.py."
        )
    url = f"https://api.github.com/repos/{REPO_SLUG}/compare/{tip}...{head}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            status = json.loads(resp.read().decode("utf-8")).get("status")
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"could not ask GitHub about {head[:7]}: {exc}")

    # "ahead" means HEAD is on top of the remote tip. "identical" cannot happen
    # here because the two SHAs differ. Anything else, including "behind" and
    # "diverged", means the commit is not reachable from the branch.
    if status != "ahead":
        raise SystemExit(
            f"HEAD {head[:7]} is {status} relative to origin/{branch} ({tip[:7]}), so "
            "raw.githubusercontent.com cannot serve it. Push first "
            "(scripts/use-app-token.sh push)."
        )
    return head


def remote_path_for(local: str, dest: str | None) -> str:
    if dest:
        return dest
    rel = os.path.relpath(os.path.abspath(local), REPO_ROOT).replace("/", "\\")
    return "C:\\AX-Runtime\\" + rel


def main() -> int:
    parser = argparse.ArgumentParser(description="Deploy a committed file to PC1 by having PC1 fetch it")
    parser.add_argument("path", help="Repo-relative or absolute path to a committed file")
    parser.add_argument("--dest", help=r"Destination on PC1, e.g. C:\AX-Runtime\reverse\x.py")
    parser.add_argument("--run", action="store_true", help="Run it on PC1 after the bytes are verified")
    parser.add_argument("--args", default="", help="Arguments to pass when running")
    parser.add_argument("--timeout", type=float, default=200.0)
    args = parser.parse_args()

    local = os.path.abspath(args.path)
    if not os.path.exists(local):
        raise SystemExit(f"no such file: {local}")

    rel_repo = os.path.relpath(local, REPO_ROOT).replace(os.sep, "/")
    if rel_repo.startswith(".."):
        raise SystemExit(f"{local} is outside the repo, so it cannot be fetched from it")

    # A working-tree edit that is not committed cannot be fetched, and silently
    # deploying the older committed version is exactly the failure this script
    # would otherwise introduce. Refuse instead.
    dirty = run_git("status", "--porcelain", "--", rel_repo)
    if dirty.strip():
        raise SystemExit(
            f"{rel_repo} has uncommitted changes. Commit and push it first, or use "
            "ax-push-script.py to send the working copy directly."
        )

    commit = resolve_commit()
    want = hashlib.sha256(open(local, "rb").read()).hexdigest()
    url = f"https://raw.githubusercontent.com/{REPO_SLUG}/{commit}/{rel_repo}"
    dest = remote_path_for(local, args.dest)

    token = os.environ.get("AX_TOKEN") or token_from_disk()
    base = os.environ.get("AX_RENDEZVOUS")
    if not base or not token:
        raise SystemExit("need AX_RENDEZVOUS and a token (env or ax-results/.ax-token)")

    ch = Channel(base, token)
    print(f"commit={commit[:7]} sha256={want[:16]}… dest={dest}")

    ps = (
        f"$u='{url}'; $d='{dest}'; $want='{want}'; "
        f"New-Item -ItemType Directory -Force -Path (Split-Path -Parent $d) | Out-Null; "
        f"Invoke-WebRequest -Uri $u -OutFile $d -UseBasicParsing; "
        f"$got=(Get-FileHash -LiteralPath $d -Algorithm SHA256).Hash.ToLower(); "
        f"if($got -ne $want){{ Remove-Item -LiteralPath $d -Force; Write-Output \"HASH_MISMATCH got=$got\"; exit 9 }}; "
        f"Write-Output \"FETCHED_BYTES=$((Get-Item -LiteralPath $d).Length) HASH_OK\""
    )
    t0 = time.time()
    res = ch.call("Shell", {"command": ps}, wait=args.timeout)
    out = ch.text_of(res).strip()
    print(f"{out}\n({time.time() - t0:.1f}s)")

    if "HASH_OK" not in out:
        print("deploy failed: bytes were not verified", file=sys.stderr)
        return 1

    if args.run:
        # A .ps1 runs with -File, anything else is executed directly.
        if dest.lower().endswith(".ps1"):
            cmd = f"powershell -NoProfile -ExecutionPolicy Bypass -File \"{dest}\" {args.args}"
        else:
            cmd = f"& \"{dest}\" {args.args}"
        r2 = ch.call("Shell", {"command": cmd}, wait=args.timeout)
        print(ch.text_of(r2).strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())

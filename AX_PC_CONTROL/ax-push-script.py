#!/usr/bin/env python3
"""Run a PowerShell script on PC1 through the reverse channel.

The channel's Shell tool caps a command at 30 seconds and carries a command as
JSON, so a multi-line script cannot go through it directly. This uploads the
script in chunks with FileWrite, decodes it on the far side, and runs it.

  python3 ax-push-script.py script.ps1
  python3 ax-push-script.py script.ps1 --args '-Foo bar'
  python3 ax-push-script.py -c 'Get-Date'

The script is base64ed for transport so quoting, line endings and non-ASCII text
survive intact. Each chunk is written with append, and the far side strips the
whitespace FileWrite may introduce before decoding.
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
REMOTE_DIR = r"C:\AX-Runtime\evidence"
# FileWrite takes the content inside a JSON string. 3000 characters of base64 is
# comfortably under the tool's limit and keeps each request small.
CHUNK = 3000


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

    def call(self, tool: str, args: dict, wait: float = 180.0) -> dict:
        job_id = self._req("POST", "ax/enqueue", {"tool": tool, "args": args})["job"]["id"]
        deadline = time.time() + wait
        while time.time() < deadline:
            hit = self._req("GET", "ax/state").get("results", {}).get(job_id)
            if hit:
                return hit
            time.sleep(2)
        return {"ok": False, "error": f"no result within {wait}s", "content": []}

    def text_of(self, result: dict) -> str:
        parts = []
        for item in result.get("content", []):
            if item.get("type") == "text":
                parts.append(item.get("text", ""))
        if result.get("error"):
            parts.append(f"ERROR: {result['error']}")
        return "\n".join(parts)


def upload(ch: Channel, local_text: str, remote_name: str) -> str:
    b64 = base64.b64encode(local_text.encode("utf-8")).decode("ascii")
    staged = f"{REMOTE_DIR}\\{remote_name}.b64"
    for i in range(0, len(b64), CHUNK):
        piece = b64[i:i + CHUNK]
        args = {"path": staged, "content": piece}
        if i:
            args["append"] = True
        res = ch.call("FileWrite", args, wait=60)
        if not res.get("ok"):
            raise SystemExit(f"upload failed at offset {i}: {ch.text_of(res)}")
    return staged


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a PowerShell script on PC1")
    parser.add_argument("script", nargs="?", help="Local .ps1 to run")
    parser.add_argument("-c", "--command", help="PowerShell text to run instead of a file")
    parser.add_argument("--args", default="", help="Arguments passed to the script")
    parser.add_argument("--rendezvous", default=os.environ.get("AX_RENDEZVOUS"))
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    if not args.rendezvous:
        print("need --rendezvous or AX_RENDEZVOUS", file=sys.stderr)
        return 2
    token = os.environ.get("AX_TOKEN") or token_from_disk()
    if not token:
        print("no token found", file=sys.stderr)
        return 2

    if args.command:
        source, name = args.command, "ax-inline"
    elif args.script:
        with open(args.script, encoding="utf-8") as fh:
            source = fh.read()
        name = os.path.splitext(os.path.basename(args.script))[0]
    else:
        print("need a script or -c", file=sys.stderr)
        return 2

    ch = Channel(args.rendezvous, token)
    staged = upload(ch, source, name)
    real = f"{REMOTE_DIR}\\{name}.ps1"
    out = f"{REMOTE_DIR}\\{name}.out.txt"
    err = f"{REMOTE_DIR}\\{name}.err.txt"
    marker = f"AX_EXIT_{name}"

    # The script is started detached and its output is polled, rather than run
    # inline. The remote Shell tool kills any command at 30 seconds and reports
    # no result at all when it does, so a script that compiles C# with Add-Type
    # and waits on a key press never survives an inline run.
    #
    # The wrapper writes a marker line when the script is done, which is how the
    # poll below knows the difference between "still running" and "finished".
    # Each argument has to be its own array element. Appending the whole string
    # as one element passes it as a single argument and the script fails to bind
    # any of its parameters.
    extra = [a for a in args.args.split() if a]
    arg_elems = ",".join(f"'{a}'" for a in extra)
    # The launched process runs the real script and then appends a marker, so the
    # poll below has one unambiguous thing to wait for. Without the marker the
    # only signal is "the file stopped changing", which cannot be told apart from
    # "the file does not exist yet" without waiting on a timeout.
    #
    # Both the script and the launcher are uploaded the same way and both have to
    # be decoded here. Decoding only the script leaves Start-Process pointing at a
    # file that was never written, and it then fails without saying anything.
    launcher = f"{REMOTE_DIR}\\{name}.launcher.ps1"
    launcher_body = (
        f"& '{real}' {args.args} *> '{out}'\r\n"
        f"Add-Content '{out}' \"AX_DONE exit=$LASTEXITCODE\"\r\n"
    )
    staged_launcher = upload(ch, launcher_body, f"{name}.launcher")
    wrapper = (
        f"$b64=(Get-Content '{staged}' -Raw) -replace '[^A-Za-z0-9+/=]','';"
        f"[IO.File]::WriteAllBytes('{real}',[Convert]::FromBase64String($b64));"
        f"$b64=(Get-Content '{staged_launcher}' -Raw) -replace '[^A-Za-z0-9+/=]','';"
        f"[IO.File]::WriteAllBytes('{launcher}',[Convert]::FromBase64String($b64));"
        f"Remove-Item '{out}' -ErrorAction SilentlyContinue;"
        f"Start-Process -FilePath 'powershell.exe' "
        f"-ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','{launcher}') "
        f"-WindowStyle Hidden;"
        f"Write-Output 'AX_LAUNCHED'"
    )
    launch = ch.call("Shell", {"command": wrapper}, wait=60)
    if not launch.get("ok"):
        print(f"launch failed: {ch.text_of(launch)}", file=sys.stderr)
        return 1

    deadline = time.time() + args.timeout
    last = ""
    while time.time() < deadline:
        time.sleep(1)
        read = ch.call("FileRead", {"path": out}, wait=15)
        text = ch.text_of(read)
        if text.strip() and "File not found" not in text:
            last = text
        if "AX_DONE" in last:
            break

    print(last)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Push a directory of source files to PC1 and unpack it there.

`ax-push-script.py` carries one PowerShell file. The vision package is several
Python files, and sending them one at a time with a hand-written decoder per
file is the kind of chore that ends with one file silently out of date.

So the directory is zipped, base64ed, uploaded in chunks with FileWrite, and
unpacked on the far side with Expand-Archive. The zip preserves the tree, so the
package lands as a package and its imports work.

  python3 ax-push-dir.py ../axvision C:\\AX-Build\\repo\\AX_PC_CONTROL\\axvision
  python3 ax-push-dir.py ../axvision C:\\dest --exclude __pycache__

Every run is a full replace: the destination is deleted first. A merge would
leave a removed file behind, and then the thing running on PC1 is not the thing
in the repo, which is the failure this whole repo keeps tripping over.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.request
import zipfile
from io import BytesIO

HERE = os.path.dirname(os.path.abspath(__file__))
REMOTE_DIR = r"C:\AX-Runtime\evidence"
CHUNK = 3000


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


def zip_dir(root: str, excludes: list[str]) -> bytes:
    buffer = BytesIO()
    root = os.path.abspath(root)
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in excludes]
            for name in filenames:
                if name in excludes or name.endswith(".pyc"):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, root)
                zf.write(full, rel)
    return buffer.getvalue()


def upload(ch: Channel, payload_b64: str, remote_name: str) -> str:
    staged = f"{REMOTE_DIR}\\{remote_name}.zip.b64"
    for i in range(0, len(payload_b64), CHUNK):
        piece = payload_b64[i:i + CHUNK]
        args = {"path": staged, "content": piece}
        if i:
            args["append"] = True
        res = ch.call("FileWrite", args, wait=60)
        if not res.get("ok"):
            raise SystemExit(f"upload failed at offset {i}: {ch.text_of(res)}")
    return staged


def main() -> int:
    parser = argparse.ArgumentParser(description="Push a directory to PC1")
    parser.add_argument("local_dir")
    parser.add_argument("remote_dir", help=r"Destination on PC1, e.g. C:\AX-Build\repo\AX_PC_CONTROL\axvision")
    parser.add_argument("--exclude", action="append", default=["__pycache__", ".git"])
    parser.add_argument("--rendezvous", default=os.environ.get("AX_RENDEZVOUS"))
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    if not args.rendezvous:
        print("need --rendezvous or AX_RENDEZVOUS", file=sys.stderr)
        return 2
    token = os.environ.get("AX_TOKEN")
    if not token:
        path = os.path.join(HERE, "ax-results", ".ax-token")
        if os.path.exists(path):
            token = open(path, encoding="utf-8").read().strip()
    if not token:
        print("no token found", file=sys.stderr)
        return 2

    blob = zip_dir(args.local_dir, args.exclude)
    b64 = base64.b64encode(blob).decode("ascii")
    print(f"zipped {args.local_dir}: {len(blob)} bytes, {len(b64)} base64 chars")

    ch = Channel(args.rendezvous, token)
    name = os.path.basename(os.path.normpath(args.local_dir))
    staged = upload(ch, b64, name)

    unpack_zip = f"{REMOTE_DIR}\\{name}.zip"
    # The destination is cleared first so a file deleted from the repo cannot
    # survive here and shadow the new code.
    script = (
        f"$b64=(Get-Content '{staged}' -Raw) -replace '[^A-Za-z0-9+/=]','';"
        f"[IO.File]::WriteAllBytes('{unpack_zip}',[Convert]::FromBase64String($b64));"
        f"Remove-Item -Recurse -Force '{args.remote_dir}' -ErrorAction SilentlyContinue;"
        f"Expand-Archive -Path '{unpack_zip}' -DestinationPath '{args.remote_dir}' -Force;"
        f"$f=Get-ChildItem -Recurse -File '{args.remote_dir}';"
        f"Write-Output ('UNPACKED ' + $f.Count + ' files ' + ($f | Measure-Object Length -Sum).Sum + ' bytes');"
        f"Write-Output ($f | ForEach-Object {{ $_.FullName.Substring({len(args.remote_dir)}) }})"
    )
    res = ch.call("Shell", {"command": script}, wait=args.timeout)
    print(ch.text_of(res))
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())

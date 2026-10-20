#!/usr/bin/env python3
"""Pull a file from PC1 to this machine as bytes.

FileDownload returns the content base64-encoded inside a text item, and a
screenshot is a few hundred KB, so this writes straight to disk instead of
printing it.

  python3 ax-pull-file.py C:\\AX-Runtime\\evidence\\shot.png ./shot.png
"""

from __future__ import annotations

import argparse
import base64
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module

ctl = import_module("ax-ctl")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch a file from PC1")
    parser.add_argument("remote", help=r"Path on PC1, e.g. C:\AX-Runtime\evidence\x.png")
    parser.add_argument("local", help="Where to write it here")
    parser.add_argument("--rendezvous", default=os.environ.get("AX_RENDEZVOUS"))
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    if not args.rendezvous:
        print("need --rendezvous or AX_RENDEZVOUS", file=sys.stderr)
        return 2
    token = ctl._token(None)
    if not token:
        print("no token found", file=sys.stderr)
        return 2

    client = ctl.Client(args.rendezvous, token)
    job_id = client.enqueue("FileDownload", {"path": args.remote})["job"]["id"]
    result = client.wait(job_id, args.timeout)
    if not result:
        print(f"no result within {args.timeout}s", file=sys.stderr)
        return 1
    if not result.get("ok"):
        print(f"download failed: {result.get('error')}", file=sys.stderr)
        return 1

    text = ""
    for item in result.get("content", []):
        if item.get("type") == "text":
            text += item.get("text", "")
    # The server prefixes replies with its task id, so find the payload rather
    # than assuming it starts the string.
    marker = "base64:"
    at = text.find(marker)
    if at < 0:
        print(f"unexpected reply: {text[:200]}", file=sys.stderr)
        return 1
    _, size, b64 = text[at:].split(":", 2)
    raw = base64.b64decode(b64)
    os.makedirs(os.path.dirname(os.path.abspath(args.local)), exist_ok=True)
    with open(args.local, "wb") as fh:
        fh.write(raw)
    print(f"wrote {args.local} {len(raw)} bytes (reported {size})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

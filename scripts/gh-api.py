#!/usr/bin/env python3
"""Call the GitHub API with a freshly minted App installation token.

The integration token in GITHUB_TOKEN is read-only, so any write (PR edits,
comments, labels) must go through the App. Installation tokens last an hour,
so we mint one per run instead of caching it.

Usage:
    python3 scripts/gh-api.py GET  /repos/OWNER/REPO/pulls
    python3 scripts/gh-api.py PATCH /repos/OWNER/REPO/pulls/46 --body-file body.md
    python3 scripts/gh-api.py POST /repos/OWNER/REPO/issues/46/comments --body-file c.md
"""

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def mint_token() -> str:
    result = subprocess.run(
        ["node", "scripts/gh-app-token.mjs"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit("Failed to mint app token:\n" + result.stderr)
    token = result.stdout.strip().splitlines()[0].strip()
    if not token:
        sys.exit("App token was empty.")
    return token


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("method")
    parser.add_argument("path", help="API path, e.g. /repos/owner/repo/pulls")
    parser.add_argument("--body-file", help="JSON payload file (use - for stdin)")
    parser.add_argument("--field", action="append", default=[],
                        help="key=value pair, value parsed as JSON when possible")
    args = parser.parse_args()

    payload = None
    if args.body_file:
        raw = sys.stdin.read() if args.body_file == "-" else Path(args.body_file).read_text()
        payload = json.loads(raw)
    elif args.field:
        payload = {}
        for item in args.field:
            key, _, value = item.partition("=")
            try:
                payload[key] = json.loads(value)
            except json.JSONDecodeError:
                payload[key] = value

    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        "https://api.github.com" + args.path,
        data=data,
        method=args.method.upper(),
        headers={
            "Authorization": "Bearer " + mint_token(),
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )

    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            print(f"HTTP {resp.status}")
            if body:
                print(body)
    except urllib.error.HTTPError as err:
        print(f"HTTP {err.code}", file=sys.stderr)
        print(err.read().decode(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

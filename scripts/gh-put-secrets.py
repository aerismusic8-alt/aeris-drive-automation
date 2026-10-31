#!/usr/bin/env python3
"""Upload named environment variables to a repo's Actions secrets.

Values are read from the current environment and never written to disk or
printed. GitHub requires a libsodium sealed box, so `pynacl` must be installed.

  python3 scripts/gh-put-secrets.py --repo owner/name YT_CLIENT_ID YT_CLIENT_SECRET

The token comes from $GITHUB_TOKEN unless --token-file is given.
"""
import argparse
import base64
import json
import os
import sys
import urllib.request

from nacl import public


def api(url: str, token: str, data=None, method="GET"):
    req = urllib.request.Request(
        url, data=data,
        headers={"Authorization": f"token {token}",
                 "Accept": "application/vnd.github+json",
                 "Content-Type": "application/json"},
        method=method)
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read().decode() or "{}"
        return r.status, json.loads(body) if body.strip().startswith(("{", "[")) else body


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", required=True, help="owner/name")
    ap.add_argument("--token-file", help="file holding a token; default $GITHUB_TOKEN")
    ap.add_argument("names", nargs="+", help="env var names to upload")
    args = ap.parse_args()

    token = (open(args.token_file).read().strip() if args.token_file
             else os.environ.get("GITHUB_TOKEN"))
    if not token:
        raise SystemExit("no token: set GITHUB_TOKEN or pass --token-file")

    base = f"https://api.github.com/repos/{args.repo}/actions/secrets"
    _, pk = api(f"{base}/public-key", token)
    key = public.PublicKey(base64.b64decode(pk["key"]))
    box = public.SealedBox(key)

    missing = [n for n in args.names if not os.environ.get(n)]
    if missing:
        raise SystemExit("not set in the environment: " + ", ".join(missing))

    for name in args.names:
        enc = base64.b64encode(box.encrypt(os.environ[name].encode())).decode()
        st, _ = api(f"{base}/{name}", token,
                    data=json.dumps({"encrypted_value": enc, "key_id": pk["key_id"]}).encode(),
                    method="PUT")
        print(f"{'ok' if st in (201, 204) else st}  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

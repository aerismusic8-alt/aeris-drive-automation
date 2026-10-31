#!/usr/bin/env python3
"""Mint a long-lived Google Drive credential with a single sign-in.

The problem this solves: a browser login (the cloud desktop, a Chrome profile)
lives inside one sandbox and dies when the pod is recycled. So "sign in once"
turned into "sign in again" every session, and every chat and browser had its
own. A **refresh token** does not have that property -- it is a string, it does
not expire on its own, and it can be handed to a new pod, a new chat or a
different machine unchanged.

The OAuth **device flow** is what makes the one sign-in possible without a
browser on this machine at all:

    python3 scripts/gdrive-auth.py start     # prints a code and a URL
    # ... open the URL on ANY device (phone is fine), type the code, approve ...
    python3 scripts/gdrive-auth.py poll      # stores the refresh token

After that, `scripts/gdrive-upload.py` uploads with no browser and no login.

Where the token is stored, in order of durability:

1. The OpenHands secret store, as `GDRIVE_REFRESH_TOKEN`. That is the only place
   that survives a pod recycle with certainty, and it is what the YT_* tokens
   already use. `start` prints the exact command to add it.
2. `<state>/gdrive-refresh-token.txt` (mode 600), so the same pod can use it
   immediately without waiting for the secret to be added.

It is never written into the repository.

Scopes: `drive.file` by default -- the app can only touch files it created, which
needs no Google app verification. Pass `--scope drive` to get full access (it
then sees every file in the account, and Google may show an "unverified app"
warning because it is a sensitive scope).

    python3 scripts/gdrive-auth.py start --scope drive
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

STATE = Path(os.environ.get("AERIS_STATE_DIR", "/workspace/ax-tools/aeris938-state"))
PENDING = STATE / "gdrive-device-code.json"
TOKEN_FILE = STATE / "gdrive-refresh-token.txt"
CLIENT_FILE = STATE / "gdrive-client.json"

SCOPES = {
    "drive.file": "https://www.googleapis.com/auth/drive.file",
    "drive": "https://www.googleapis.com/auth/drive",
}

DEVICE_URL = "https://oauth2.googleapis.com/device/code"
TOKEN_URL = "https://oauth2.googleapis.com/token"


def client() -> tuple[str, str]:
    """OAuth client id/secret, from the environment or the state file.

    The environment is what an OpenHands chat provides (the YT_* secrets). A
    machine outside OpenHands -- PC1, a laptop -- has no such injection, so the
    pair is also read from `<state>/gdrive-client.json`. Without this a correct
    token still looks broken with "client id is not set", which is a confusing
    failure because the token is not the problem.
    """
    cid = os.environ.get("GDRIVE_CLIENT_ID") or os.environ.get("YT_CLIENT_ID")
    csec = os.environ.get("GDRIVE_CLIENT_SECRET") or os.environ.get("YT_CLIENT_SECRET")
    if not (cid and csec) and CLIENT_FILE.exists():
        try:
            data = json.loads(CLIENT_FILE.read_text())
            cid = cid or data.get("client_id")
            csec = csec or data.get("client_secret")
        except (OSError, ValueError):
            pass
    if not cid or not csec:
        raise SystemExit(
            "OAuth client not configured. Set GDRIVE_CLIENT_ID / GDRIVE_CLIENT_SECRET "
            "(or YT_CLIENT_ID / YT_CLIENT_SECRET), or write them to\n"
            f"  {CLIENT_FILE}\n"
            'as {"client_id": "...", "client_secret": "..."}')
    return cid, csec


def post(url: str, data: dict) -> tuple[int, dict]:
    req = urllib.request.Request(
        url, data=urllib.parse.urlencode(data).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as f:
            return f.status, json.load(f)
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.load(exc)
        except Exception:
            return exc.code, {"error": exc.read().decode()[:300]}


def stored_token() -> str:
    """The token from the secret (preferred) or the state file, in that order."""
    token = os.environ.get("GDRIVE_REFRESH_TOKEN")
    if token:
        return token.strip()
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text().strip()
    raise FileNotFoundError(TOKEN_FILE)


def cmd_start(args: argparse.Namespace) -> int:
    cid, _ = client()
    scope = SCOPES[args.scope]
    status, body = post(DEVICE_URL, {"client_id": cid, "scope": scope})
    if status != 200 or "device_code" not in body:
        print(f"device/code failed: {status} {body}", file=sys.stderr)
        return 1
    STATE.mkdir(parents=True, exist_ok=True)
    PENDING.write_text(json.dumps({
        "device_code": body["device_code"],
        "scope": scope,
        "interval": body.get("interval", 5),
        "expires_at": time.time() + body.get("expires_in", 1800),
    }))
    os.chmod(PENDING, 0o600)

    print("=" * 64)
    print("  Sign in ONCE. Any device with a browser will do.")
    print("=" * 64)
    print(f"  1. Open:  {body.get('verification_url', 'https://www.google.com/device')}")
    print(f"  2. Code:  {body['user_code']}")
    print(f"  3. Sign in as the account that should own the uploads.")
    print(f"  4. Approve the Drive access.")
    print()
    print(f"  Scope: {scope}")
    print(f"  Code expires in {body.get('expires_in', 1800)}s.")
    print()
    print("  Then run:  python3 scripts/gdrive-auth.py poll")
    return 0


def cmd_poll(args: argparse.Namespace) -> int:
    if not PENDING.exists():
        print("no pending device code; run `start` first", file=sys.stderr)
        return 1
    pending = json.loads(PENDING.read_text())
    cid, csec = client()
    interval = max(5, int(pending.get("interval", 5)))
    deadline = pending.get("expires_at", time.time() + 1800)

    while time.time() < deadline:
        status, body = post(TOKEN_URL, {
            "client_id": cid, "client_secret": csec,
            "device_code": pending["device_code"],
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        })
        if status == 200 and "refresh_token" in body:
            token = body["refresh_token"]
            STATE.mkdir(parents=True, exist_ok=True)
            TOKEN_FILE.write_text(token)
            os.chmod(TOKEN_FILE, 0o600)
            print("OK  refresh token stored (mode 600):", TOKEN_FILE)
            print(f"    scope: {body.get('scope')}")
            print()
            print("Make it permanent -- add it as an OpenHands secret so a recycled")
            print("pod, a new chat and any other browser all keep working:")
            print()
            print(f"    name : GDRIVE_REFRESH_TOKEN")
            print(f"    value: {token[:6]}...{token[-4:]}  (full value is in the file above)")
            print()
            print("Verify with:  python3 scripts/gdrive-upload.py --check")
            PENDING.unlink(missing_ok=True)
            return 0
        err = body.get("error")
        if err == "authorization_pending":
            time.sleep(interval)
            continue
        if err == "slow_down":
            interval += 5
            time.sleep(interval)
            continue
        if err == "access_denied":
            print("denied: the account did not approve the request", file=sys.stderr)
            return 1
        if err in ("expired_token", "invalid_grant"):
            print(f"the code expired ({err}); run `start` again", file=sys.stderr)
            return 1
        print(f"unexpected: {status} {body}", file=sys.stderr)
        return 1
    print("timed out waiting for approval; run `start` again", file=sys.stderr)
    return 1


def cmd_verify(_args: argparse.Namespace) -> int:
    """Prove the stored token is usable WITHOUT calling the Drive API.

    `whoami` asks the Drive API, which answers 403 while the API is disabled in
    the owning Cloud project -- a real failure that says nothing about the token.
    This only exercises the OAuth token endpoint, so a green result means the
    credential itself is good and the secret was pasted correctly.
    """
    try:
        token = stored_token()
    except FileNotFoundError:
        print("no stored token. Run: python3 scripts/gdrive-auth.py start")
        return 1
    cid, secret = client()
    status, data = post("https://oauth2.googleapis.com/token", {
        "client_id": cid, "client_secret": secret,
        "refresh_token": token, "grant_type": "refresh_token"})
    if status != 200 or "access_token" not in data:
        print(f"FAIL ({status}) -- the refresh token was rejected:")
        print(f"  {data.get('error', data)}")
        print("  A revoked or mistyped token looks like this. Mint a new one:")
        print("  python3 scripts/gdrive-auth.py start")
        return 1
    print("TOKEN OK")
    print(f"  scope   : {data.get('scope')}")
    print(f"  expires : {data.get('expires_in')}s (the refresh token itself does not expire)")
    print(f"  length  : {len(token)} chars")
    print("  The credential works. Drive API calls will 403 until the API is")
    print("  enabled in the owning Cloud project; the browser uploader needs no API.")
    return 0


def cmd_whoami(_args: argparse.Namespace) -> int:
    """Prove the stored token works and say which account it belongs to."""
    token = os.environ.get("GDRIVE_REFRESH_TOKEN")
    if not token and TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text().strip()
    if not token:
        print("no GDRIVE_REFRESH_TOKEN and no", TOKEN_FILE)
        return 1
    cid, csec = client()
    status, body = post(TOKEN_URL, {
        "client_id": cid, "client_secret": csec,
        "refresh_token": token, "grant_type": "refresh_token"})
    if status != 200 or "access_token" not in body:
        print(f"refresh failed: {status} {body}")
        return 1
    at = body["access_token"]
    req = urllib.request.Request(
        "https://www.googleapis.com/drive/v3/about?fields=user,storageQuota",
        headers={"Authorization": f"Bearer {at}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as f:
            about = json.load(f)
    except urllib.error.HTTPError as exc:
        print(f"drive about failed: {exc.code} {exc.read().decode()[:200]}")
        return 1
    user = about.get("user", {})
    print("SIGNED IN:", user.get("emailAddress"), f"({user.get('displayName')})")
    print("access token lives ~1h; the refresh token does not expire on its own.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start", help="request a device code")
    s.add_argument("--scope", choices=sorted(SCOPES), default="drive.file")
    s.set_defaults(func=cmd_start)
    sub.add_parser("poll", help="wait for approval and store the refresh token").set_defaults(func=cmd_poll)
    sub.add_parser("verify", help="prove the credential works (no Drive API call)").set_defaults(func=cmd_verify)
    sub.add_parser("whoami", help="prove the stored token works").set_defaults(func=cmd_whoami)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

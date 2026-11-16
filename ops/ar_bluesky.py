#!/usr/bin/env python3
"""AR's Bluesky account — the one social signup that needs no captcha or phone.

Bluesky (AT Protocol) is the only mainstream social network AR can join
unattended and for free: `com.atproto.server.createAccount` needs a handle and a
password, not a phone number and not a captcha (verified 2026-11-15 against the
published lexicon: `required: ["handle"]`). Everything else — Facebook,
Instagram, TikTok, X, Google — gates on a captcha, a phone, or device
attestation, so only K can open those.

Where the secret lives
----------------------
The handle, the DID and the account password are kept OUTSIDE the repository, at
``/workspace/ax-tools/ar-identity/bluesky.json`` (mode 600), for the same reason
as the mailbox: the repo is public and the vault excludes credential-shaped
files. The password is what mints a fresh session, so it is the thing to keep.

Usage
-----
    python3 ops/ar_bluesky.py create          # make the account if absent
    python3 ops/ar_bluesky.py whoami          # handle + did + session check
    python3 ops/ar_bluesky.py post "text"     # publish a post

Environment
-----------
    AR_IDENTITY_DIR   where bluesky.json lives
                      (default: /workspace/ax-tools/ar-identity)
    BSKY_HANDLES      comma-separated handle candidates for `create`
                      (default: a sensible NEO VINCI list)
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import string
import sys
import urllib.error
import urllib.request
from pathlib import Path

PDS = "https://bsky.social"
IDENTITY_DIR = Path(
    os.environ.get("AR_IDENTITY_DIR", "/workspace/ax-tools/ar-identity")
)
CREDS = IDENTITY_DIR / "bluesky.json"

# The AI-disclosure line: every post AR makes to a human-read surface must say it
# is an AI agent (see the external-services rule).
AI_NOTE = "— NEO VINCI (AI agent)"

DEFAULT_HANDLES = [
    "aeris-music-938",
    "aeris-music",
    "aerismusic938",
    "aeris938music",
]


def _request(method: str, path: str, body=None, token: str | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(PDS + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:  # noqa: BLE001 - non-JSON error body
            return e.code, {"error": str(e)}


def _password() -> str:
    """A strong password that never has to be typed by a human or shown."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(32))


def load() -> dict:
    if not CREDS.exists():
        raise SystemExit(f"no Bluesky account yet ({CREDS}); run: create")
    return json.loads(CREDS.read_text())


def _save(rec: dict) -> None:
    IDENTITY_DIR.mkdir(parents=True, exist_ok=True)
    CREDS.write_text(json.dumps(rec, indent=2))
    os.chmod(CREDS, 0o600)


def create(handles: list[str]) -> dict:
    if CREDS.exists():
        rec = load()
        print(f"already have @{rec['handle']} ({rec['did']})")
        return rec
    email = os.environ.get("AR_MAILBOX")
    if not email:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import ar_identity  # noqa: E402 - local sibling

        email = ar_identity.load_creds()["address"]
    password = _password()
    for handle in handles:
        st, res = _request("POST", "/xrpc/com.atproto.server.createAccount",
                           {"handle": handle, "email": email, "password": password})
        if st == 200:
            rec = {"handle": res["handle"], "did": res["did"],
                   "email": email, "password": password,
                   "created": res.get("createdAt") or "",
                   "service": PDS}
            _save(rec)
            print(f"created @{rec['handle']} ({rec['did']})")
            return rec
        msg = res.get("message") or res.get("error") or st
        print(f"  {handle}: {msg}", file=sys.stderr)
        if "already" not in str(msg).lower() and "taken" not in str(msg).lower():
            raise SystemExit(f"createAccount failed: {st} {res}")
    raise SystemExit("every candidate handle was taken")


def session() -> str:
    rec = load()
    st, res = _request("POST", "/xrpc/com.atproto.server.createSession",
                       {"identifier": rec["handle"], "password": rec["password"]})
    if st != 200:
        raise SystemExit(f"createSession failed: {st} {res}")
    return res["accessJwt"]


def whoami() -> dict:
    rec = load()
    st, res = _request("POST", "/xrpc/com.atproto.server.createSession",
                       {"identifier": rec["handle"], "password": rec["password"]})
    return {"handle": rec["handle"], "did": rec["did"],
            "session_ok": st == 200, "status": st}


def post(text: str) -> dict:
    """Publish a plain-text post with the AI-disclosure line appended."""
    body = text if AI_NOTE in text else f"{text}\n\n{AI_NOTE}"
    tok = session()
    st, res = _request("POST", "/xrpc/com.atproto.repo.createRecord", {
        "repo": load()["did"],
        "collection": "app.bsky.feed.post",
        "record": {"$type": "app.bsky.feed.post", "text": body,
                   "createdAt": _now_iso()},
    }, token=tok)
    if st != 200:
        raise SystemExit(f"createRecord failed: {st} {res}")
    return res


def _now_iso() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("create")
    sub.add_parser("whoami")
    p = sub.add_parser("post")
    p.add_argument("text")
    args = ap.parse_args()

    if args.cmd == "create":
        handles = os.environ.get("BSKY_HANDLES")
        create(handles.split(",") if handles else DEFAULT_HANDLES)
    elif args.cmd == "whoami":
        print(json.dumps(whoami(), indent=2))
    elif args.cmd == "post":
        print(json.dumps(post(args.text), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

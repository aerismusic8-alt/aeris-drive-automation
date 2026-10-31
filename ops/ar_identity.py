#!/usr/bin/env python3
"""AR identity — the agent's own mailbox, durable and free.

AR (the agent) sometimes needs an email to register for a free service. This
tool creates and drives that mailbox through the mail.tm REST API: free, no
phone number, and — the point — the inbox is readable over the API, so AR can
fetch a verification link or code without a human.

Where the secret lives
----------------------
The address and its password are kept OUTSIDE the repository, at
``/workspace/ax-tools/ar-identity/creds.json`` (mode 600). Two reasons:

- the repository is public, so a credential must never be committed;
- the knowledge vault (``ops/ax_vault.py``) excludes credential-shaped files on
  purpose, so it is not the place either.

``/workspace`` is the only path that survives a pod recycle, which is why the
file sits there and not under ``$HOME``. The API token is re-minted from the
stored password on every run, so nothing short-lived is persisted.

Usage
-----
    python3 ops/ar_identity.py ensure           # create the mailbox if absent
    python3 ops/ar_identity.py whoami           # address + inbox count
    python3 ops/ar_identity.py inbox [--wait S] # list messages (poll for a code)
    python3 ops/ar_identity.py read <id>        # full text of one message

Environment
-----------
    AR_MAILBOX_LOCAL   local part (default: ar.aeris)
    AR_IDENTITY_DIR    where creds.json lives
                       (default: /workspace/ax-tools/ar-identity)
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import string
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.mail.tm"
DEFAULT_LOCAL = os.environ.get("AR_MAILBOX_LOCAL", "araeris")
IDENTITY_DIR = Path(
    os.environ.get("AR_IDENTITY_DIR", "/workspace/ax-tools/ar-identity")
)
CREDS = IDENTITY_DIR / "creds.json"


def _request(method: str, path: str, token: str | None = None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, {"raw": raw}


def _password(n: int = 24) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))


def _active_domain() -> str:
    status, body = _request("GET", "/domains")
    if status != 200 or not body:
        raise SystemExit(f"mail.tm /domains failed: {status} {body}")
    members = body.get("hydra:member") if isinstance(body, dict) else body
    for d in members or []:
        if d.get("isActive"):
            return d["domain"]
    raise SystemExit("mail.tm has no active domain")


def _try_login(address: str, password: str) -> str | None:
    status, body = _request("POST", "/token", body={"address": address, "password": password})
    if status == 200 and body and "token" in body:
        return body["token"]
    return None


def _login(address: str, password: str) -> str:
    token = _try_login(address, password)
    if token is None:
        raise SystemExit(
            f"mail.tm login failed for {address} — the stored password is stale. "
            f"Delete {CREDS} and re-run ensure."
        )
    return token


def load_creds() -> dict:
    if not CREDS.exists():
        raise SystemExit(
            f"no AR mailbox yet at {CREDS} — run: python3 ops/ar_identity.py ensure"
        )
    return json.loads(CREDS.read_text())


def _save_creds(address: str, password: str, domain: str) -> None:
    IDENTITY_DIR.mkdir(parents=True, exist_ok=True)
    tmp = CREDS.with_suffix(".tmp")
    tmp.write_text(json.dumps({"address": address, "password": password,
                               "domain": domain, "provider": "mail.tm"}, indent=2))
    os.chmod(tmp, 0o600)
    tmp.replace(CREDS)


def cmd_ensure(_args) -> int:
    if CREDS.exists():
        c = load_creds()
        if _try_login(c["address"], c["password"]):
            print(f"AR mailbox already exists: {c['address']}")
            return 0
        print(f"stored mailbox {c['address']} no longer authenticates; creating a new one")
        CREDS.unlink(missing_ok=True)
    domain = _active_domain()
    # A bare local part can collide with an account already taken on the shared
    # domain (the create 201s but the login 401s). Suffix until one round-trips.
    # mail.tm also rate-limits account creation with a bare 429; back off on it.
    for attempt in range(8):
        # mail.tm rejects a local part containing "." (create 201s, login 401s).
        local = DEFAULT_LOCAL if attempt == 0 else f"{DEFAULT_LOCAL}{secrets.token_hex(3)}"
        address = f"{local}@{domain}"
        password = _password()
        status, _ = _request(
            "POST", "/accounts", body={"address": address, "password": password}
        )
        if status == 429:
            print(f"mail.tm rate-limited; waiting 30s (attempt {attempt + 1}/8)")
            time.sleep(30)
            continue
        if status not in (200, 201):
            continue
        if _try_login(address, password):
            _save_creds(address, password, domain)
            print(f"created AR mailbox: {address}")
            print(f"credentials stored at {CREDS} (mode 600, outside the repo)")
            return 0
    raise SystemExit(
        "could not create a mail.tm mailbox that authenticates — "
        "set AR_MAILBOX_LOCAL to a fresh local part and retry."
    )


def cmd_whoami(_args) -> int:
    c = load_creds()
    token = _login(c["address"], c["password"])
    status, me = _request("GET", "/me", token=token)
    status, box = _request("GET", "/messages", token=token)
    count = len((box or {}).get("hydra:member", []) or []) if status == 200 else "?"
    print(f"address: {c['address']}")
    print(f"provider: {c['provider']}   inbox: {count} message(s)")
    print(f"account id: {(me or {}).get('id', '?')}")
    return 0


def cmd_inbox(args) -> int:
    c = load_creds()
    token = _login(c["address"], c["password"])
    deadline = time.time() + (args.wait or 0)
    while True:
        status, box = _request("GET", "/messages", token=token)
        members = (box or {}).get("hydra:member", []) or []
        if members or time.time() >= deadline:
            break
        time.sleep(3)
    if not members:
        print("(inbox empty)")
        return 0
    for m in members:
        sender = (m.get("from") or {}).get("address", "?")
        print(f"{m['id']}  {m.get('createdAt','')}  from {sender}")
        print(f"    subject: {m.get('subject','')}")
    return 0


def cmd_read(args) -> int:
    c = load_creds()
    token = _login(c["address"], c["password"])
    status, m = _request("GET", f"/messages/{args.id}", token=token)
    if status != 200:
        raise SystemExit(f"read failed: {status} {m}")
    print(f"from: {(m.get('from') or {}).get('address','?')}")
    print(f"subject: {m.get('subject','')}")
    print("---")
    print(m.get("text") or "")
    html = m.get("html")
    if html:
        if isinstance(html, list):
            html = "\n".join(html)
        print("--- html ---")
        print(html)
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ensure").set_defaults(fn=cmd_ensure)
    sub.add_parser("whoami").set_defaults(fn=cmd_whoami)
    pi = sub.add_parser("inbox")
    pi.add_argument("--wait", type=int, default=0, help="seconds to poll for new mail")
    pi.set_defaults(fn=cmd_inbox)
    pr = sub.add_parser("read")
    pr.add_argument("id")
    pr.set_defaults(fn=cmd_read)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())

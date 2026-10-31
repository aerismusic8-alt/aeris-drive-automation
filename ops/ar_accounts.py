#!/usr/bin/env python3
"""AR accounts — the register of accounts AR creates for itself.

K authorised AR (2026-10-31) to create its own identity — a mailbox plus a
persistent browser profile — and to open accounts with it on AR's own behalf.

What is durable and where
-------------------------
- **Mailbox**: `ops/ar_identity.py` owns it; the address and password live in
  `/workspace/ax-tools/ar-identity/creds.json` (outside the repo, mode 600).
- **Browser profile**: `/workspace/ax-tools/ar-identity/browser-profile`. This is
  where the cookies that keep AR signed in live. It is under `/workspace` on
  purpose: `$HOME` is discarded on a pod recycle, so a profile kept there would
  log AR out of every account each time.
- **This register**: `/workspace/ax-tools/ar-identity/accounts.json` — which
  services AR has an account on, the login address, and the status. It is kept
  outside the repo as well, because the repository is public.

No password is stored here. Sign-in happens in the browser profile, which is the
credential; this file only says *where* AR has an account.

Usage
-----
    python3 ops/ar_accounts.py add --service pixabay --url https://pixabay.com \\
        --note "stock images for thumbnails"
    python3 ops/ar_accounts.py list
    python3 ops/ar_accounts.py status <service> active|pending|blocked
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

IDENTITY_DIR = Path(
    os.environ.get("AR_IDENTITY_DIR", "/workspace/ax-tools/ar-identity")
)
ACCOUNTS = IDENTITY_DIR / "accounts.json"
PROFILE_DIR = IDENTITY_DIR / "browser-profile"


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load() -> dict:
    if not ACCOUNTS.exists():
        return {"mailbox": _mailbox_address(), "profile": str(PROFILE_DIR),
                "accounts": []}
    return json.loads(ACCOUNTS.read_text())


def _mailbox_address() -> str:
    creds = IDENTITY_DIR / "creds.json"
    if creds.exists():
        return json.loads(creds.read_text()).get("address", "")
    return ""


def save(data: dict) -> None:
    IDENTITY_DIR.mkdir(parents=True, exist_ok=True)
    tmp = ACCOUNTS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    os.chmod(tmp, 0o600)
    tmp.replace(ACCOUNTS)


def cmd_add(args) -> int:
    data = load()
    data["mailbox"] = _mailbox_address()
    data["profile"] = str(PROFILE_DIR)
    for a in data["accounts"]:
        if a["service"] == args.service:
            a.update({"url": args.url or a.get("url", ""),
                      "note": args.note or a.get("note", ""),
                      "updated": _now()})
            save(data)
            print(f"updated {args.service}")
            return 0
    data["accounts"].append({
        "service": args.service,
        "url": args.url or "",
        "login": data["mailbox"],
        "status": args.status,
        "note": args.note or "",
        "created": _now(),
        "updated": _now(),
    })
    save(data)
    print(f"added {args.service} ({args.status})")
    return 0


def cmd_list(_args) -> int:
    data = load()
    print(f"mailbox: {data.get('mailbox') or '(none — run ar_identity.py ensure)'}")
    print(f"profile: {data.get('profile')}")
    print(f"accounts: {len(data['accounts'])}")
    for a in data["accounts"]:
        print(f"  - {a['service']:16} {a['status']:8} {a.get('url','')}")
        if a.get("note"):
            print(f"      {a['note']}")
    return 0


def cmd_status(args) -> int:
    data = load()
    for a in data["accounts"]:
        if a["service"] == args.service:
            a["status"] = args.status
            a["updated"] = _now()
            save(data)
            print(f"{args.service} -> {args.status}")
            return 0
    raise SystemExit(f"no account named {args.service}")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    pa = sub.add_parser("add")
    pa.add_argument("--service", required=True)
    pa.add_argument("--url", default="")
    pa.add_argument("--note", default="")
    pa.add_argument("--status", default="pending",
                    choices=["pending", "active", "blocked"])
    pa.set_defaults(fn=cmd_add)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    ps = sub.add_parser("status")
    ps.add_argument("service")
    ps.add_argument("status", choices=["pending", "active", "blocked"])
    ps.set_defaults(fn=cmd_status)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())

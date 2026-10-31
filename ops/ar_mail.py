#!/usr/bin/env python3
"""AR mailboxes — several free providers, so more services can be signed up for.

`ar_identity.py` holds AR's one original mailbox (mail.tm). That domain is
disposable and most signups reject it, and one address cannot be the contact for
a dozen accounts, so this tool keeps a *set* of mailboxes across providers and
reads any of them over its API.

Providers
---------
* ``mailtm``     — mail.tm (the original address lives here).
* ``guerrilla``  — guerrillamail.com, a second disposable provider.

A mailbox's address and password (or session) live OUTSIDE the repository, one
JSON file per mailbox under ``/workspace/ax-tools/ar-identity/mailboxes/``
(mode 600) — the repository is public, so a credential must never be committed.

Usage
-----
    python3 ops/ar_mail.py list
    python3 ops/ar_mail.py new --provider guerrilla --label tiktok
    python3 ops/ar_mail.py inbox --mailbox guerrilla-tiktok.json [--wait S]
    python3 ops/ar_mail.py read  --mailbox guerrilla-tiktok.json --id 3
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
import urllib.parse
import urllib.request
from pathlib import Path

IDENTITY_DIR = Path(os.environ.get("AR_IDENTITY_DIR", "/workspace/ax-tools/ar-identity"))
MAILBOX_DIR = IDENTITY_DIR / "mailboxes"
MAILTM_API = "https://api.mail.tm"
GUERRILLA_API = "https://api.guerrillamail.com/ajax.php"


def _get(url: str, token: str | None = None, timeout=30):
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/json")
    # guerrillamail 403s the default Python-urllib UA, so identify as a browser.
    req.add_header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read().decode()
        return r.status, (json.loads(raw) if raw else None)


def _post(url: str, body, timeout=30):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
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


def _save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.chmod(tmp, 0o600)
    tmp.replace(path)


# ---------------------------------------------------------------- mail.tm
def mailtm_create(label: str) -> dict:
    _, doms = _get(f"{MAILTM_API}/domains")
    members = doms.get("hydra:member") if isinstance(doms, dict) else doms
    domain = next((d["domain"] for d in members or [] if d.get("isActive")), None)
    if not domain:
        raise SystemExit("mail.tm has no active domain")
    for _ in range(8):
        local = "ar" + secrets.token_hex(4)
        address, pw = f"{local}@{domain}", _password()
        st, _ = _post(f"{MAILTM_API}/accounts", {"address": address, "password": pw})
        if st == 429:
            time.sleep(20)
            continue
        if st not in (200, 201):
            continue
        st, body = _post(f"{MAILTM_API}/token", {"address": address, "password": pw})
        if st == 200 and body and "token" in body:
            return {"provider": "mail.tm", "address": address, "password": pw,
                    "label": label}
    raise SystemExit("could not create a mail.tm mailbox")


def mailtm_token(mb: dict) -> str:
    st, body = _post(f"{MAILTM_API}/token",
                     {"address": mb["address"], "password": mb["password"]})
    if st != 200 or not body or "token" not in body:
        raise SystemExit(f"mail.tm login failed: {st} {body}")
    return body["token"]


def mailtm_inbox(mb: dict) -> list[dict]:
    tok = mailtm_token(mb)
    _, box = _get(f"{MAILTM_API}/messages", token=tok)
    out = []
    for m in (box or {}).get("hydra:member", []) or []:
        out.append({"id": m["id"], "from": (m.get("from") or {}).get("address", "?"),
                    "subject": m.get("subject", ""), "at": m.get("createdAt", "")})
    return out


def mailtm_read(mb: dict, mid: str) -> str:
    tok = mailtm_token(mb)
    _, m = _get(f"{MAILTM_API}/messages/{mid}", token=tok)
    body = m.get("text") or ""
    html = m.get("html")
    if html:
        body += "\n--- html ---\n" + ("\n".join(html) if isinstance(html, list) else html)
    return body


# ---------------------------------------------------------------- guerrillamail
def guerrilla_create(label: str) -> dict:
    st, body = _get(f"{GUERRILLA_API}?f=get_email_address")
    if st != 200 or not body:
        raise SystemExit(f"guerrillamail failed: {st} {body}")
    return {"provider": "guerrilla", "address": body["email_addr"],
            "sid_token": body["sid_token"], "label": label}


def guerrilla_inbox(mb: dict) -> list[dict]:
    q = urllib.parse.urlencode({"f": "check_email", "sid_token": mb["sid_token"], "seq": 0})
    _, body = _get(f"{GUERRILLA_API}?{q}")
    out = []
    for m in (body or {}).get("list", []) or []:
        out.append({"id": str(m.get("mail_id")), "from": m.get("mail_from", "?"),
                    "subject": m.get("mail_subject", ""), "at": m.get("mail_date", "")})
    return out


def guerrilla_read(mb: dict, mid: str) -> str:
    q = urllib.parse.urlencode({"f": "fetch_email", "sid_token": mb["sid_token"],
                                "email_id": mid})
    _, body = _get(f"{GUERRILLA_API}?{q}")
    return (body or {}).get("mail_body", "") or ""


# ---------------------------------------------------------------- registry
def _path(mb: dict) -> Path:
    return MAILBOX_DIR / f"{mb['provider'].replace('.', '')}-{mb['label']}.json"


def load_all() -> list[dict]:
    if not MAILBOX_DIR.exists():
        return []
    out = []
    for f in sorted(MAILBOX_DIR.glob("*.json")):
        try:
            out.append({**json.loads(f.read_text()), "file": f.name})
        except ValueError:
            continue
    return out


def find(mailbox: str) -> dict:
    for mb in load_all():
        if mb["file"] == mailbox or mb.get("label") == mailbox:
            return mb
    raise SystemExit(f"no mailbox {mailbox!r}; run: python3 ops/ar_mail.py list")


def cmd_list(_args) -> int:
    boxes = load_all()
    if not boxes:
        print("(no extra mailboxes yet)")
        return 0
    for mb in boxes:
        try:
            n = len(INBOX[mb["provider"]](mb))
        except Exception as exc:
            n = f"? ({type(exc).__name__})"
        print(f"{mb['file']:32} {mb['address']:34} inbox: {n}")
    return 0


def cmd_new(args) -> int:
    create = {"mailtm": mailtm_create, "guerrilla": guerrilla_create}[args.provider]
    label = args.label or secrets.token_hex(3)
    mb = create(label)
    _save(_path(mb), mb)
    print(f"created {mb['address']}  ({mb['provider']}, label {label})")
    print(f"stored {_path(mb)} (mode 600, outside the repo)")
    return 0


def cmd_inbox(args) -> int:
    mb = find(args.mailbox)
    deadline = time.time() + (args.wait or 0)
    msgs = INBOX[mb["provider"]](mb)
    while not msgs and time.time() < deadline:
        time.sleep(3)
        msgs = INBOX[mb["provider"]](mb)
    if not msgs:
        print("(inbox empty)")
        return 0
    for m in msgs:
        print(f"{m['id']:>10}  {m['at']:20}  {m['from']}")
        print(f"            subject: {m['subject']}")
    return 0


def cmd_read(args) -> int:
    mb = find(args.mailbox)
    print(READ[mb["provider"]](mb, args.id))
    return 0


INBOX = {"mail.tm": mailtm_inbox, "guerrilla": guerrilla_inbox}
READ = {"mail.tm": mailtm_read, "guerrilla": guerrilla_read}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    pn = sub.add_parser("new")
    pn.add_argument("--provider", choices=["mailtm", "guerrilla"], default="guerrilla")
    pn.add_argument("--label", help="a short name for the service it is for")
    pn.set_defaults(fn=cmd_new)
    pi = sub.add_parser("inbox")
    pi.add_argument("--mailbox", required=True)
    pi.add_argument("--wait", type=int, default=0)
    pi.set_defaults(fn=cmd_inbox)
    pr = sub.add_parser("read")
    pr.add_argument("--mailbox", required=True)
    pr.add_argument("--id", required=True)
    pr.set_defaults(fn=cmd_read)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())

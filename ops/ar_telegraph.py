#!/usr/bin/env python3
"""AR's Telegraph account — a publishing surface AR opens itself, for free.

Telegraph (telegra.ph) is the one publishing host whose signup needs neither a
captcha nor a phone: `createAccount` takes a short name and returns an access
token (verified 2026-11-16). That makes it a surface AR can provision alone,
unlike Facebook, Instagram, TikTok, X, Google and (since this week) Bluesky,
which all gate on a captcha, a phone or device attestation.

What it is good for: a search-indexable page per song or per buying guide, with a
canonical URL and a back-link to the channel. Social reach is tiny and slow, so a
page that can rank for a Thai query is worth more than another post.

Where the secret lives
----------------------
The access token is kept OUTSIDE the repository, at
``/workspace/ax-tools/ar-identity/telegraph.json`` (mode 600), for the same reason
as the mailbox and the Nostr key: the repo is public and the vault excludes
credential-shaped files. It is mirrored to the durable vault so a replaced
sandbox can recover it.

Usage
-----
    python3 ops/ar_telegraph.py create               # open the account if absent
    python3 ops/ar_telegraph.py whoami               # account info + session check
    python3 ops/ar_telegraph.py page --title T --text "..."   # publish a page
    python3 ops/ar_telegraph.py page --title T --file body.txt --url <canonical>
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.telegra.ph"
IDENTITY_DIR = Path(os.environ.get("AR_IDENTITY_DIR", "/workspace/ax-tools/ar-identity"))
CREDS = IDENTITY_DIR / "telegraph.json"
VAULT_KEY = "axsecrets:ar-telegraph"

SHORT_NAME = "เพลงส้นทีนไรเนี่ย"
AUTHOR_NAME = "เพลงส้นทีนไรเนี่ย"

_URL_RE = re.compile(r"(https?://[^\s<>()]+)")

# Every page AR publishes to a human-read surface says it was made by an agent.
AI_NOTE = "— เพลงส้นทีนไรเนี่ย (AI agent)"


def _request(method: str, path: str, body=None, timeout: int = 45):
    data = urllib.parse.urlencode(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    # A User-Agent must be ASCII (urllib encodes headers as latin-1), so the
    # brand is romanised here on purpose — do not put the Thai display name in.
    req.add_header("User-Agent", "Ploeng-San-Teen-Music/1.0")
    if data is not None:
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:  # noqa: BLE001 - non-JSON error body
            return e.code, {"error": str(e)}


def load() -> dict:
    if not CREDS.exists():
        raise SystemExit(f"no Telegraph account yet ({CREDS}); run: create")
    return json.loads(CREDS.read_text())


def _save(rec: dict) -> None:
    IDENTITY_DIR.mkdir(parents=True, exist_ok=True)
    CREDS.write_text(json.dumps(rec, indent=2))
    os.chmod(CREDS, 0o600)
    _vault_put(rec)


def _vault_put(rec: dict) -> None:
    """Mirror the token to the durable vault so a replaced sandbox keeps it."""
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import ax_vault  # noqa: PLC0415

        ax_vault.kv_put(ax_vault.ensure_anchor(), VAULT_KEY, rec)
        print(f"mirrored the Telegraph token to the vault ({VAULT_KEY})")
    except Exception as exc:  # noqa: BLE001
        print(f"[=] vault mirror skipped: {str(exc)[:80]}")


def vault_get() -> dict | None:
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import ax_vault  # noqa: PLC0415

        return ax_vault.kv_get(ax_vault.ensure_anchor(), VAULT_KEY)
    except Exception:  # noqa: BLE001
        return None


def create(short_name: str = SHORT_NAME, author_name: str = AUTHOR_NAME) -> dict:
    if CREDS.exists():
        rec = load()
        print(f"already have a Telegraph account ({rec['short_name']})")
        return rec
    st, res = _request("POST", "/createAccount",
                       {"short_name": short_name, "author_name": author_name})
    if st != 200 or not res.get("ok"):
        raise SystemExit(f"createAccount failed: {st} {res}")
    r = res["result"]
    rec = {
        "short_name": r["short_name"],
        "author_name": r.get("author_name") or author_name,
        "author_url": r.get("author_url") or "",
        "access_token": r["access_token"],
        "auth_url": r.get("auth_url") or "",
        "service": API,
    }
    _save(rec)
    print(f"created Telegraph account: {rec['short_name']}")
    return rec


def whoami() -> dict:
    rec = load()
    st, res = _request("POST", "/getAccountInfo",
                       {"access_token": rec["access_token"],
                        "fields": '["short_name","author_name","author_url","page_count"]'})
    ok = st == 200 and res.get("ok")
    info = res.get("result", {}) if ok else {}
    return {"short_name": rec["short_name"], "session_ok": ok, "status": st,
            "page_count": info.get("page_count"), "info": info}


def _nodes(text: str) -> list:
    """Turn plain text into Telegraph nodes: blank line = new paragraph, and a
    bare URL becomes a real link (Telegraph renders a text node as plain text)."""
    paras = [p.strip() for p in text.replace("\r\n", "\n").split("\n\n")]
    out = []
    for p in paras:
        if not p:
            continue
        children, pos = [], 0
        for m in _URL_RE.finditer(p):
            if m.start() > pos:
                children.append(p[pos:m.start()])
            children.append({"tag": "a", "attrs": {"href": m.group(1)},
                             "children": [m.group(1)]})
            pos = m.end()
        if pos < len(p):
            children.append(p[pos:])
        out.append({"tag": "p", "children": children or [p]})
    return out


def page(title: str, text: str, author_name: str | None = None,
         author_url: str | None = None, token: str | None = None) -> dict:
    """Publish one page and return its URL. Appends the AI-disclosure line.

    `token` lets a caller (e.g. a CI rail) pass the access token explicitly
    instead of reading AR's identity file.
    """
    rec = load() if not token else {"access_token": token, "author_name": author_name}
    body = text if AI_NOTE in text else f"{text}\n\n{AI_NOTE}"
    payload = {
        "access_token": rec["access_token"],
        "title": title[:256],
        "author_name": author_name or rec.get("author_name") or AUTHOR_NAME,
        "content": json.dumps(_nodes(body), ensure_ascii=False),
        "return_content": "false",
    }
    if author_url:
        payload["author_url"] = author_url
    st, res = _request("POST", "/createPage", payload)
    if st != 200 or not res.get("ok"):
        raise SystemExit(f"createPage failed: {st} {res}")
    return {"url": res["result"]["url"], "path": res["result"]["path"],
            "title": res["result"]["title"]}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("create")
    sub.add_parser("whoami")
    p = sub.add_parser("page")
    p.add_argument("--title", required=True)
    p.add_argument("--text", help="page body; blank line separates paragraphs")
    p.add_argument("--file", help="read the body from a file instead")
    p.add_argument("--url", help="author_url (the channel link)")
    args = ap.parse_args(argv)

    if args.cmd == "create":
        create()
    elif args.cmd == "whoami":
        print(json.dumps(whoami(), ensure_ascii=False, indent=2))
    elif args.cmd == "page":
        body = args.text
        if args.file:
            body = Path(args.file).read_text(encoding="utf-8")
        if not body:
            raise SystemExit("page needs --text or --file")
        out = page(args.title, body, author_url=args.url)
        print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

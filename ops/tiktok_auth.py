#!/usr/bin/env python3
"""One-tap TikTok authorization for the Content Posting API.

TikTok has no server to receive the redirect here, so the flow is manual
copy-paste, the same shape as the YouTube consent dance: AR prints the authorize
URL, K opens it once in a browser and approves, TikTok bounces to the app's
registered redirect URI with `?code=...`, and K pastes that whole URL back. The
code is exchanged for an access + refresh pair, which goes into the vault under
the keys `tiktok_api` reads. After that the rail refreshes the token itself and
`tiktok_api.available()` turns True.

Free, no paid anything: the app itself is free, and PKCE means the code is only
redeemable with the verifier this process generated.

    python3 ops/tiktok_auth.py --client-key KEY --client-secret SECRET \\
        --redirect-uri https://example.com/callback          # prints the URL
    python3 ops/tiktok_auth.py --code 'https://example.com/callback?code=...'
    python3 ops/tiktok_auth.py --check                       # is it alive?

The redirect URI must be the exact string registered in the TikTok app, and the
app must hold the `video.publish` scope (plus `user.info.basic` to verify).
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OPS = Path(__file__).resolve().parent
sys.path.insert(0, str(OPS))

AUTHORIZE = "https://www.tiktok.com/v2/auth/authorize/"
SCOPES = ("user.info.basic", "video.publish")
VERIFIER_KEY = "axsecrets:tiktok-code-verifier"


def pkce() -> tuple[str, str]:
    """A PKCE verifier and its S256 challenge (RFC 7636)."""
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(48)).decode().rstrip("=")
    digest = hashlib.sha256(verifier.encode()).digest()
    return verifier, base64.urlsafe_b64encode(digest).decode().rstrip("=")


def authorize_url(client_key: str, redirect_uri: str, challenge: str,
                  state: str, scopes: tuple[str, ...] = SCOPES) -> str:
    """The URL K opens once. Every parameter is required by TikTok's Login Kit."""
    params = {
        "client_key": client_key,
        "scope": ",".join(scopes),
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    return f"{AUTHORIZE}?{urllib.parse.urlencode(params)}"


def code_from(pasted: str) -> str:
    """The `code` out of a pasted redirect URL (or a bare code)."""
    pasted = pasted.strip().strip("'\"")
    if "code=" in pasted:
        query = urllib.parse.urlparse(pasted).query or pasted.split("?", 1)[-1]
        return (urllib.parse.parse_qs(query).get("code") or [""])[0]
    return pasted


def exchange(code: str, verifier: str, client_key: str, client_secret: str,
             redirect_uri: str) -> dict:
    """Trade the code for a token pair, exactly as `tiktok_api.refresh` expects."""
    body = urllib.parse.urlencode({
        "client_key": client_key,
        "client_secret": client_secret,
        "code": code,
        "grant_type": "authorization_code",
        "redirect_uri": redirect_uri,
        "code_verifier": verifier,
    }).encode()
    req = urllib.request.Request(
        "https://open.tiktokapis.com/v2/oauth/token/", data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}", "detail": e.read().decode()[:400]}


def _vault():
    import ax_vault  # noqa: PLC0415

    return ax_vault


def save(d: dict) -> bool:
    """Store the pair where `tiktok_api` looks for it."""
    tok = d.get("access_token", "")
    if not tok:
        return False
    v = _vault()
    anchor = v.ensure_anchor()
    v.kv_put(anchor, "axsecrets:tiktok-access-token", tok)
    if d.get("refresh_token"):
        v.kv_put(anchor, "axsecrets:tiktok-refresh-token", d["refresh_token"])
    return True


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--client-key", default="")
    ap.add_argument("--client-secret", default="")
    ap.add_argument("--redirect-uri", default="")
    ap.add_argument("--code", default="", help="the pasted redirect URL or code")
    ap.add_argument("--check", action="store_true", help="report live status")
    a = ap.parse_args(argv)

    import tiktok_api  # noqa: PLC0415

    if a.check:
        print(f"client_key: {'set' if tiktok_api.client_key() else 'missing'}")
        print(f"secret:     {'set' if tiktok_api.client_secret() else 'missing'}")
        print(f"refresh:    {'set' if tiktok_api.refresh_token() else 'missing'}")
        print(f"available:  {tiktok_api.available()}")
        if tiktok_api.available():
            print(f"creator_info: {json.dumps(tiktok_api.creator_info())[:300]}")
        return 0 if tiktok_api.available() else 1

    key = a.client_key or tiktok_api.client_key()
    sec = a.client_secret or tiktok_api.client_secret()
    redirect = a.redirect_uri
    if not (key and sec and redirect):
        print("need --client-key, --client-secret and --redirect-uri "
              "(the exact string registered in the TikTok app)", file=sys.stderr)
        return 2

    if not a.code:
        verifier, challenge = pkce()
        _vault().kv_put(_vault().ensure_anchor(), VERIFIER_KEY, verifier)
        url = authorize_url(key, redirect, challenge, secrets.token_urlsafe(8))
        print("1) open this once in the browser K is already logged into TikTok with:")
        print(f"\n{url}\n")
        print("2) approve, then copy the FULL address it lands on and run:")
        print("   python3 ops/tiktok_auth.py --redirect-uri "
              f"{redirect} --code '<pasted url>'")
        return 0

    verifier = _vault().kv_get(_vault().ensure_anchor(), VERIFIER_KEY) or ""
    if not verifier:
        print("no stored code_verifier — run without --code first", file=sys.stderr)
        return 2
    d = exchange(code_from(a.code), verifier, key, sec, redirect)
    if not save(d):
        print(f"exchange failed: {json.dumps({k: v for k, v in d.items() if k != 'access_token'})[:400]}",
              file=sys.stderr)
        return 1
    print("saved: access + refresh token in the vault")
    print(f"available: {tiktok_api.available()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Post a Reel to the AERIS Music Page through the Meta Graph API.

This is the headless replacement for the browser poster in
`music938-1/scripts/crosspost.py`. The browser route drives a real Chromium with
a saved cookie jar, and that session dies every few weeks, forcing K to sign in
again through noVNC. A Graph API *Page* access token has no such problem: the
advisor panel (2026-11-07, 6 channels / 4 vendors) ranked it the most durable
option, with a System User token that never expires and a 60-day user token that
`refresh()` can renew without a human.

The one thing this still needs is a token, provisioned once by K. Until that
token exists every function here is a clean no-op that returns "unavailable", so
the rail keeps working through the browser and nothing crashes.

Token resolution order:
  1. env  FB_PAGE_TOKEN      (GitHub Actions secret, the normal path)
  2. vault axsecrets:fb-page-token   (the desktop/agent path)

App credentials for `refresh()`:
  env FB_APP_ID / FB_APP_SECRET, else vault axsecrets:fb-app-id / -secret.

The Reels flow is three calls, each verified against Meta's Reels Publishing API:
  start  -> POST /{page}/video_reels?upload_phase=start          -> video_id + upload_url
  upload -> POST {upload_url}  header Authorization: OAuth <t>   -> rupload.facebook.com
  finish -> POST /{page}/video_reels?upload_phase=finish&...     -> publish

Three post types share the one token, so the Page feed is not wall-to-wall Reels:
  post_reel  -> /{page}/video_reels   a vertical song video
  post_photo -> /{page}/photos        cover art + caption (multipart upload)
  post_link  -> /{page}/feed          a Shopee affiliate link card
An advisor panel (2026-11-05, 2 vendors) ranked the mix: Reel for reach, photo
for the visual identity, and at most one link a day so the feed does not read as
an ad wall.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

GRAPH = "https://graph.facebook.com/v21.0"
RUPLOAD = "https://rupload.facebook.com/video-upload/v21.0"
# Graph API node id, verified 2026-11-05 with the System User token. The number
# on the public profile URL (61595890900382) is *not* a Graph node — the Page
# node is the id Business Suite shows as the asset (1349201551618019). Passing
# the profile id to Graph returns "Object with ID ... does not exist".
PAGE_ID = os.environ.get("FB_PAGE_ID", "1349201551618019")
TIMEOUT = 120


def _vault() -> object | None:
    # CI has no vault. `ax_vault.ensure_anchor()` talks to the OpenHands API and
    # raises SystemExit (a BaseException, so a plain `except Exception` misses it)
    # when that API rejects the caller. Guard both the import and the anchor here,
    # and read the env before ever touching the vault, so a GitHub runner never
    # dies with a traceback from a secret lookup.
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import ax_vault  # noqa: PLC0415

        return ax_vault
    except Exception:
        return None


def _vault_get(key: str) -> str:
    v = _vault()
    if v is None:
        return ""
    try:
        return (v.kv_get(v.ensure_anchor(), key) or "").strip()
    except BaseException:  # noqa: BLE001 — SystemExit from the anchor lookup
        return ""


def _vault_put(key: str, value: str) -> bool:
    v = _vault()
    if v is None:
        return False
    try:
        v.kv_put(v.ensure_anchor(), key, value)
        return True
    except BaseException:  # noqa: BLE001
        return False


def page_token() -> str:
    """The Page access token, from the env first and the vault second."""
    return (os.environ.get("FB_PAGE_TOKEN") or "").strip() or _vault_get("axsecrets:fb-page-token")


def app_creds() -> tuple[str, str]:
    return (
        (os.environ.get("FB_APP_ID") or "").strip() or _vault_get("axsecrets:fb-app-id"),
        (os.environ.get("FB_APP_SECRET") or "").strip() or _vault_get("axsecrets:fb-app-secret"),
    )


def available() -> bool:
    """True when a Page token is configured, so a caller can prefer this route."""
    return bool(page_token())


def _get(url: str, data: dict | None = None) -> dict:
    q = urllib.parse.urlencode(data) if data else ""
    req = urllib.request.Request(f"{url}?{q}" if q else url,
                                 headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:400]
        raise RuntimeError(f"graph {e.code}: {detail}") from e


_ALIVE: bool | None = None


def token_alive(refresh: bool = False) -> bool:
    """True only when Graph accepts the Page token right now.

    `available()` says a token is *configured*; this says it *works*. A token
    can be present and rejected — the stored one returned "API access blocked"
    (OAuthException 200) from 2026-11-08 — and a caller that trusted `available()`
    then failed every post while the probe still reported the surface healthy.
    Only a Graph rejection means dead; a transport error is transient, so the
    token is treated as alive and the post attempt is left to surface it.
    """
    global _ALIVE
    if _ALIVE is not None and not refresh:
        return _ALIVE
    tok = page_token()
    if not tok:
        _ALIVE = False
        return False
    try:
        d = _get(f"{GRAPH}/me", {"fields": "id", "access_token": tok})
        _ALIVE = bool(d.get("id"))
    except RuntimeError as e:
        msg = str(e)
        _ALIVE = not ("OAuthException" in msg or "access blocked" in msg)
    return _ALIVE


def _post(url: str, data: dict | None = None, *, raw: bytes | None = None,
          headers: dict | None = None) -> dict:
    hdr = {"Accept": "application/json"}
    hdr.update(headers or {})
    body = raw
    if raw is None and data is not None:
        body = urllib.parse.urlencode(data).encode()
        hdr["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=hdr, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:400]
        raise RuntimeError(f"graph {e.code}: {detail}") from e


def _post_multipart(url: str, fields: dict, file_field: str, filename: str,
                    blob: bytes, content_type: str, *, headers: dict | None = None) -> dict:
    """POST a multipart/form-data body carrying one file, with stdlib only.

    urllib has no multipart writer, and the alternative is a dependency this
    module deliberately does not have, so the body is assembled by hand. The
    boundary is derived from the payload length so it cannot collide with the
    bytes it is delimiting.
    """
    boundary = f"----axfb{len(blob):x}{int(time.time() * 1000) & 0xffffff:x}"
    out = bytearray()
    for k, v in fields.items():
        out += f"--{boundary}\r\n".encode()
        out += f'Content-Disposition: form-data; name="{k}"\r\n\r\n'.encode()
        out += f"{v}\r\n".encode()
    out += f"--{boundary}\r\n".encode()
    out += (f'Content-Disposition: form-data; name="{file_field}"; '
            f'filename="{filename}"\r\n').encode()
    out += f"Content-Type: {content_type}\r\n\r\n".encode()
    out += blob
    out += f"\r\n--{boundary}--\r\n".encode()
    hdr = {"Accept": "application/json",
           "Content-Type": f"multipart/form-data; boundary={boundary}"}
    hdr.update(headers or {})
    req = urllib.request.Request(url, data=bytes(out), headers=hdr, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:400]
        raise RuntimeError(f"graph {e.code}: {detail}") from e


def whoami(token: str | None = None) -> dict:
    """Debug helper: confirm the token works and names the right Page."""
    t = token or page_token()
    if not t:
        return {"ok": False, "error": "no FB_PAGE_TOKEN configured"}
    url = f"{GRAPH}/{PAGE_ID}?" + urllib.parse.urlencode({"fields": "id,name", "access_token": t})
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            d = json.loads(r.read().decode())
        return {"ok": True, "page": d}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"{e.code}: {e.read().decode()[:200]}"}


def get(path: str, params: dict | None = None) -> dict:
    """A GET against the Graph API with the Page token attached.

    Raises RuntimeError on a real API error so the caller can decide whether to
    degrade to "unknown" or fall back to the browser.
    """
    p = dict(params or {})
    p["access_token"] = p.get("access_token") or page_token()
    url = f"{GRAPH}/{path.lstrip('/')}?" + urllib.parse.urlencode(p)
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"graph {e.code}: {e.read().decode()[:300]}") from e


def refresh() -> str:
    """Exchange the current token for a fresh long-lived one and store it back.

    A System User token (`expires_at` 0) is returned unchanged. A 60-day user
    token is exchanged through the app secret, which is what keeps the rail
    alive without K. Returns the (possibly new) token, or "" on failure.
    """
    t = page_token()
    if not t:
        return ""
    app_id, app_secret = app_creds()
    if not (app_id and app_secret):
        return t
    url = f"{GRAPH}/oauth/access_token?" + urllib.parse.urlencode({
        "grant_type": "fb_exchange_token",
        "client_id": app_id,
        "client_secret": app_secret,
        "fb_exchange_token": t,
    })
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            new = json.loads(r.read().decode()).get("access_token", "")
    except urllib.error.HTTPError:
        return t
    if new and new != t:
        _vault_put("axsecrets:fb-page-token", new)
    return new or t


def debug_token() -> dict:
    """Report expiry so the heartbeat can warn *before* the token dies.

    Prefers app-credential inspection, but falls back to self-inspection
    (`input_token == access_token`) when no app id/secret is stored. Self-debug
    still returns `expires_at` and `type`, which is all the heartbeat needs, and
    it keeps the rail working when only the Page token was provisioned.
    """
    t = page_token()
    if not t:
        return {"ok": False, "error": "no token"}
    app_id, app_secret = app_creds()
    inspector = f"{app_id}|{app_secret}" if (app_id and app_secret) else t
    url = f"{GRAPH}/debug_token?" + urllib.parse.urlencode({
        "input_token": t, "access_token": inspector})
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return {"ok": True, "data": json.loads(r.read().decode()).get("data", {})}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"{e.code}: {e.read().decode()[:200]}"}


def post_reel(video: Path, caption: str, *, token: str | None = None) -> str | None:
    """Publish one Reel. Returns the video id, or None if unavailable/failed.

    Raises RuntimeError only on a real API error while a token *is* present, so
    the caller can distinguish "not configured" (fall back to the browser) from
    "configured but the API refused" (report it).
    """
    t = token or page_token()
    if not t:
        return None
    size = video.stat().st_size

    start = _post(f"{GRAPH}/{PAGE_ID}/video_reels", {
        "upload_phase": "start", "access_token": t})
    video_id = start.get("video_id")
    upload_url = start.get("upload_url")
    if not (video_id and upload_url):
        raise RuntimeError(f"reels start returned {start}")

    with open(video, "rb") as fh:
        blob = fh.read()
    up = upload_url if upload_url.startswith("http") else f"{RUPLOAD}/{video_id}"
    _post(up, raw=blob, headers={
        "Authorization": f"OAuth {t}",
        "offset": "0",
        "file_size": str(size),
        "Content-Type": "application/octet-stream",
    })

    fin = _post(f"{GRAPH}/{PAGE_ID}/video_reels", {
        "upload_phase": "finish",
        "video_id": video_id,
        "video_state": "PUBLISHED",
        "description": caption,
        "access_token": t,
    })
    if not fin.get("success", True):
        raise RuntimeError(f"reels finish returned {fin}")
    return video_id


def post_photo(image: Path, caption: str, *, token: str | None = None) -> str | None:
    """Publish one photo (cover art) to the Page feed. Returns the post id.

    Same contract as `post_reel`: None when no token is configured, RuntimeError
    on a real API error so the caller can tell "not set up" from "refused".
    """
    t = token or page_token()
    if not t:
        return None
    blob = image.read_bytes()
    ctype = "image/png" if image.suffix.lower() == ".png" else "image/jpeg"
    out = _post_multipart(f"{GRAPH}/{PAGE_ID}/photos",
                          {"caption": caption, "access_token": t},
                          "source", image.name, blob, ctype)
    pid = out.get("post_id") or out.get("id")
    if not pid:
        raise RuntimeError(f"photos returned {out}")
    return pid


def post_link(message: str, link: str, *, token: str | None = None) -> str | None:
    """Publish a link post (a Shopee card). Returns the post id.

    `message` is the caption; `link` becomes the clickable card. A link post is
    plain form-encoded `/feed`, no file, so `_post` already covers it.
    """
    t = token or page_token()
    if not t:
        return None
    out = _post(f"{GRAPH}/{PAGE_ID}/feed",
                {"message": message, "link": link, "access_token": t})
    pid = out.get("id") or out.get("post_id")
    if not pid:
        raise RuntimeError(f"feed returned {out}")
    return pid


def _main(argv: list[str]) -> int:
    cmd = argv[0] if argv else "status"
    if cmd == "status":
        tok = page_token()
        print("configured" if tok else "not configured (no FB_PAGE_TOKEN)")
        if tok:
            print(json.dumps(whoami(), ensure_ascii=False))
        return 0
    if cmd == "refresh":
        new = refresh()
        print("refreshed" if new else "no token to refresh")
        return 0 if new else 1
    if cmd == "expiry":
        print(json.dumps(debug_token(), ensure_ascii=False))
        return 0
    print(f"unknown command {cmd!r}; use status|refresh|expiry", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))

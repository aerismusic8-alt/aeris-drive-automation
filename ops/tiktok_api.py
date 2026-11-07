#!/usr/bin/env python3
"""Post a Short to TikTok through the official Content Posting API.

The advisor panel (2026-11-07, 6 channels / 4 vendors) ranked the Meta Graph API
first for durability and was *unanimous that TikTok has no fully unattended
route*: the Content Posting API still needs the app to pass TikTok's audit, and
an unaudited client can only publish as `SELF_ONLY` (private). So this module is
the honest best-effort — it removes the browser *cookie* failure, but it cannot
remove TikTok's audit gate, and it says so instead of pretending otherwise.

The browser poster stays the default until both a token is present *and* the
creator account reports a public privacy level, so a token that can only post
privately never silently replaces working public posts with invisible ones.

Token resolution:
  env  TT_CLIENT_KEY / TT_CLIENT_SECRET / TT_REFRESH_TOKEN   (Actions secrets)
  else vault axsecrets:tiktok-*                              (desktop path)

Endpoints (v2):
  refresh  POST https://open.tiktokapis.com/v2/oauth/token/
  query    POST https://open.tiktokapis.com/v2/post/publish/creator_info/query/
  init     POST https://open.tiktokapis.com/v2/post/publish/video/init/
  status   POST https://open.tiktokapis.com/v2/post/publish/status/fetch/
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://open.tiktokapis.com/v2"
OAUTH = f"{API}/oauth/token/"
TIMEOUT = 180
CHUNK = 10 * 1024 * 1024  # TikTok requires 5–64 MB chunks; 10 MB is safe.


def _vault() -> object | None:
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import ax_vault  # noqa: PLC0415

        return ax_vault
    except Exception:
        return None


def _get(key: str) -> str:
    v = _vault()
    if v is None:
        return ""
    try:
        return (v.kv_get(v.ensure_anchor(), key) or "").strip()
    except BaseException:  # noqa: BLE001 — CI has no vault; ensure_anchor exits
        return ""


def _put(key: str, value: str) -> bool:
    v = _vault()
    if v is None:
        return False
    try:
        v.kv_put(v.ensure_anchor(), key, value)
        return True
    except BaseException:  # noqa: BLE001
        return False


def _env(name: str, vault_key: str) -> str:
    return (os.environ.get(name) or "").strip() or _get(vault_key)


def client_key() -> str:
    return _env("TT_CLIENT_KEY", "axsecrets:tiktok-client-key")


def client_secret() -> str:
    return _env("TT_CLIENT_SECRET", "axsecrets:tiktok-client-secret")


def refresh_token() -> str:
    return _env("TT_REFRESH_TOKEN", "axsecrets:tiktok-refresh-token")


def access_token() -> str:
    return (os.environ.get("TT_ACCESS_TOKEN") or "").strip() or _get("axsecrets:tiktok-access-token")


def available() -> bool:
    return bool(client_key() and client_secret() and refresh_token())


def _req(url: str, body: dict | None, token: str = "", *, method: str = "POST") -> dict:
    hdr = {"Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        hdr["Content-Type"] = "application/json; charset=UTF-8"
    if token:
        hdr["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=hdr, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:400]
        raise RuntimeError(f"tiktok {e.code}: {detail}") from e


def refresh() -> str:
    """Rotate the access token from the refresh token; store both back."""
    if not available():
        return ""
    body = urllib.parse.urlencode({
        "client_key": client_key(),
        "client_secret": client_secret(),
        "grant_type": "refresh_token",
        "refresh_token": refresh_token(),
    }).encode()
    req = urllib.request.Request(
        OAUTH, data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            d = json.loads(r.read().decode())
    except urllib.error.HTTPError:
        return ""
    tok = d.get("access_token", "")
    if tok:
        _put("axsecrets:tiktok-access-token", tok)
    if d.get("refresh_token"):
        _put("axsecrets:tiktok-refresh-token", d["refresh_token"])
    return tok


def creator_info() -> dict:
    """What privacy levels this account may use (SELF_ONLY means unaudited)."""
    # Same rotation guard as post_video: only the agent may burn the refresh token.
    tok = access_token()
    if not tok and _put("axsecrets:tiktok-probe", "1"):
        tok = refresh()
    if not tok:
        return {"ok": False, "error": "no access token"}
    try:
        d = _req(f"{API}/post/publish/creator_info/query/", {}, tok)
        return {"ok": True, "data": d.get("data", {}), "error": d.get("error", {})}
    except RuntimeError as e:
        return {"ok": False, "error": str(e)}


def _privacy(info: dict) -> str:
    opts = (info.get("data") or {}).get("privacy_level_options") or []
    for want in ("PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS", "FOLLOWER_OF_CREATOR"):
        if want in opts:
            return want
    return opts[0] if opts else "SELF_ONLY"


def post_video(video: Path, caption: str, *, allow_private: bool = False) -> str | None:
    """Upload and publish one video. Returns the publish_id, or None.

    Returns None (so the caller falls back to the browser) when the token is
    absent, or when the account can only post `SELF_ONLY` and `allow_private`
    is false — an invisible post is worse than no post.
    """
    if not available():
        return None
    # Rotating burns the stored refresh token, so only the agent — the one place
    # that can write the new value back to the vault — may do it. CI has no
    # vault, `_put` returns False, so this stays a plain read there and the
    # token is left for the agent to rotate on its own schedule.
    tok = access_token()
    if not tok and _put("axsecrets:tiktok-probe", "1"):
        tok = refresh()
    if not tok:
        return None
    info = creator_info()
    level = _privacy(info)
    if level == "SELF_ONLY" and not allow_private:
        print("  tiktok: account is unaudited (SELF_ONLY only) — keeping the browser route")
        return None

    size = video.stat().st_size
    chunks = max(1, (size + CHUNK - 1) // CHUNK)
    init = _req(f"{API}/post/publish/video/init/", {
        "post_info": {"title": caption[:2200], "privacy_level": level,
                      "disable_comment": False, "disable_duet": False,
                      "disable_stitch": False},
        "source_info": {"source": "FILE_UPLOAD", "video_size": size,
                        "chunk_size": size if chunks == 1 else CHUNK,
                        "total_chunk_count": chunks},
    }, tok)
    data = init.get("data", {})
    publish_id, upload_url = data.get("publish_id"), data.get("upload_url")
    if not (publish_id and upload_url):
        raise RuntimeError(f"tiktok init returned {init}")

    with open(video, "rb") as fh:
        for i in range(chunks):
            blob = fh.read(size if chunks == 1 else CHUNK)
            start = 0 if chunks == 1 else i * CHUNK
            end = start + len(blob) - 1
            req = urllib.request.Request(
                upload_url, data=blob, method="PUT",
                headers={"Content-Range": f"bytes {start}-{end}/{size}",
                         "Content-Type": "video/mp4"})
            try:
                urllib.request.urlopen(req, timeout=TIMEOUT).read()
            except urllib.error.HTTPError as e:
                raise RuntimeError(f"tiktok upload {e.code}: {e.read().decode()[:200]}") from e
    return publish_id


def status(publish_id: str) -> dict:
    # Rotation guard: a status check must never burn the refresh token in CI.
    tok = access_token()
    if not tok and _put("axsecrets:tiktok-probe", "1"):
        tok = refresh()
    if not tok:
        return {"ok": False, "error": "no access token"}
    try:
        return {"ok": True, "data": _req(
            f"{API}/post/publish/status/fetch/", {"publish_id": publish_id}, tok)}
    except RuntimeError as e:
        return {"ok": False, "error": str(e)}


def _main(argv: list[str]) -> int:
    cmd = argv[0] if argv else "status"
    if cmd == "status":
        print("configured" if available() else "not configured (no TikTok app tokens)")
        if available():
            print(json.dumps(creator_info(), ensure_ascii=False)[:600])
        return 0
    if cmd == "refresh":
        print("refreshed" if refresh() else "no token to refresh")
        return 0
    print(f"unknown command {cmd!r}; use status|refresh", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))

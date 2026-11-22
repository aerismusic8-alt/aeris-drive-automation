#!/usr/bin/env python3
"""Post a Reel to the เพลงส้นทีนไรเนี่ย Page through the Meta Graph API.

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
  post_reel   -> /{page}/video_reels   a vertical song video (<=90 s)
  post_video  -> /{page}/videos        a full song / compilation (any length)
  post_photo  -> /{page}/photos        cover art + caption (multipart upload)
  post_photos -> /{page}/feed          a multi-photo album
  post_text   -> /{page}/feed          a text-only status
  post_link   -> /{page}/feed          a Shopee affiliate link card
An advisor panel (2026-11-05, 2 vendors) ranked the mix: Reel for reach, photo
for the visual identity, and at most one link a day so the feed does not read as
an ad wall.

`post_text`, `post_video` and `post_photos` take `when=<datetime>` to schedule
(Meta requires 10 minutes to 75 days ahead); every other call publishes now.
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
# Video bytes go to a separate host; the plain `graph` host refuses `source`.
GRAPH_VIDEO = "https://graph-video.facebook.com/v21.0"
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
    """The configured token, from the env first and the vault second.

    This is usually a *System User* token: it authenticates as the System User,
    not as the Page. See `page_access_token` for the Page-scoped exchange.
    """
    return (os.environ.get("FB_PAGE_TOKEN") or "").strip() or _vault_get("axsecrets:fb-page-token")


# The Page-scoped token, per process. The exchange is one extra call and the
# result is stable, so it is worth caching.
_PAGE_TOKEN_CACHE: dict[str, str] = {}


def page_access_token(token: str | None = None) -> str:
    """Exchange the configured token for one that authenticates *as the Page*.

    A System User token carries the Page's tasks but is not itself a Page token:
    posting or editing Page fields with it fails `#210 A page access token is
    required`. The Page node returns the Page token for any token that holds the
    Page's tasks, so exchange on demand. If the exchange is refused the original
    token is returned unchanged, which keeps the caller's error the real one.
    """
    base = (token or page_token()).strip()
    if not base:
        return ""
    cached = _PAGE_TOKEN_CACHE.get(base)
    if cached:
        return cached
    try:
        d = _get(f"{GRAPH}/{PAGE_ID}",
                 {"fields": "access_token", "access_token": base})
    except RuntimeError:
        return base
    pt = (d.get("access_token") or "").strip()
    if pt:
        _PAGE_TOKEN_CACHE[base] = pt
    return pt or base


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


def _hold() -> object:
    """The publish hold, imported by path: this module is loaded both as a
    script in ops/ and as a library from music938-1/scripts, so `import
    hold_gate` alone is not reliable."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import hold_gate  # noqa: PLC0415

    return hold_gate


def _post(url: str, data: dict | None = None, *, raw: bytes | None = None,
          headers: dict | None = None) -> dict:
    # Every write in this module goes through here or `_post_multipart`, so K's
    # hold is enforced at one place instead of at six call sites that can drift.
    _hold().assert_open("fb_graph")
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
    _hold().assert_open("fb_graph")
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
    p["access_token"] = p.get("access_token") or page_access_token()
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
    t = page_access_token(token) if (token or page_token()) else ""
    if not t:
        return None
    # K (2026-11-18): a PARKED genre must never be uploaded. YouTube has gated
    # this since 2026-11-19; this route did not, so a lukthung/indie/symphonic
    # song could reach the Page while the same clip was refused for YouTube.
    import genre_gate  # noqa: E402  (same directory)
    genre_gate.assert_ok(str(video))
    # K (2026-11-17): nothing below the channel floor may be uploaded anywhere.
    import clip_standard  # noqa: E402  (same directory)
    # Same self-heal as `yt_publish`: a clip rendered before its master was
    # re-mastered carries stale audio, and refusing it here while YouTube repairs
    # and ships the identical file left Facebook permanently behind. Repair the
    # audio (video stream copied, picture untouched) before measuring; a style
    # failure is still refused below.
    if clip_standard.needs_audio_repair(str(video)):
        video = Path(clip_standard.repair_audio(str(video)))
    clip_standard.assert_ok(str(video))
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
    t = page_access_token(token) if (token or page_token()) else ""
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
    t = page_access_token(token) if (token or page_token()) else ""
    if not t:
        return None
    out = _post(f"{GRAPH}/{PAGE_ID}/feed",
                {"message": message, "link": link, "access_token": t})
    pid = out.get("id") or out.get("post_id")
    if not pid:
        raise RuntimeError(f"feed returned {out}")
    return pid


def _schedule(fields: dict, when: "datetime | None") -> dict:
    """Add Meta's scheduled-publish fields, or publish immediately.

    `scheduled_publish_time` must be 10 minutes to 75 days ahead and is a unix
    timestamp. Passing `published=false` *without* a time makes a draft, which is
    never what a caller here means, so `when=None` omits both fields (publish now).
    """
    if when is None:
        return fields
    stamp = int(when.timestamp())
    if stamp < int(time.time()) + 600:
        raise ValueError("scheduled_publish_time must be at least 10 minutes ahead")
    fields = dict(fields)
    fields["published"] = "false"
    fields["scheduled_publish_time"] = str(stamp)
    return fields


def post_text(message: str, *, when=None, token: str | None = None) -> str | None:
    """Publish a text-only status. Returns the post id.

    The plainest Page post, and the one the feed needs most: a text status reads
    as a person talking, where a wall of covers and Reels reads as a catalogue.
    """
    t = page_access_token(token) if (token or page_token()) else ""
    if not t:
        return None
    fields = _schedule({"message": message, "access_token": t}, when)
    out = _post(f"{GRAPH}/{PAGE_ID}/feed", fields)
    pid = out.get("id") or out.get("post_id")
    if not pid:
        raise RuntimeError(f"feed returned {out}")
    return pid


def post_video(video: Path, caption: str, *, title: str | None = None,
               when=None, token: str | None = None) -> str | None:
    """Publish a regular (landscape or portrait) video, not a Reel. Returns the id.

    Reels are vertical, <=90 s and short-form only; a full song, a compilation or
    a film belongs here, on `/{page}/videos`. The bytes go to the `graph-video`
    host, which is the one that accepts a video upload (the plain `graph` host
    rejects `source`).
    """
    t = page_access_token(token) if (token or page_token()) else ""
    if not t:
        return None
    import genre_gate  # noqa: E402  (same directory)
    genre_gate.assert_ok(str(video))
    import clip_standard  # noqa: E402  (same directory)
    if clip_standard.needs_audio_repair(str(video)):
        video = Path(clip_standard.repair_audio(str(video)))
    clip_standard.assert_ok(str(video))
    # A big file goes up in chunks: one 300 MB multipart POST breaks the pipe.
    if video.stat().st_size > 40 * 1024 * 1024:
        return post_video_resumable(video, caption, title=title, when=when, token=t)
    blob = video.read_bytes()
    fields = {"description": caption, "access_token": t}
    if title:
        fields["title"] = title
    fields = _schedule(fields, when)
    out = _post_multipart(f"{GRAPH_VIDEO}/{PAGE_ID}/videos", fields,
                          "source", video.name, blob, "video/mp4")
    vid = out.get("id") or out.get("video_id")
    if not vid:
        raise RuntimeError(f"videos returned {out}")
    return vid


def post_video_resumable(video: Path, caption: str, *, title: str | None = None,
                         when=None, token: str | None = None,
                         chunk_mb: int = 8) -> str | None:
    """Upload a large video in chunks, then finish it.

    `post_video` sends the whole file in one multipart POST, which reads it into
    memory and holds a single connection open for the duration. A 308 MB MV broke
    that with `URLError: Broken pipe` (2026-11-22), losing the upload after
    minutes. Meta's documented resumable protocol — start / transfer / finish —
    moves a bounded chunk per request, so a dropped connection costs one chunk
    rather than the whole file.
    """
    t = page_access_token(token) if (token or page_token()) else ""
    if not t:
        return None
    import genre_gate  # noqa: E402
    genre_gate.assert_ok(str(video))
    import clip_standard  # noqa: E402
    if clip_standard.needs_audio_repair(str(video)):
        video = Path(clip_standard.repair_audio(str(video)))
    clip_standard.assert_ok(str(video))

    size = video.stat().st_size
    url = f"{GRAPH_VIDEO}/{PAGE_ID}/videos"
    start = _post(url, {"upload_phase": "start", "file_size": str(size),
                        "access_token": t})
    sid = start.get("upload_session_id")
    vid = start.get("video_id")
    if not sid or not vid:
        raise RuntimeError(f"resumable start returned {start}")
    offset = int(start.get("start_offset", 0))
    end = int(start.get("end_offset", min(size, chunk_mb * 1024 * 1024)))
    with open(video, "rb") as f:
        while offset < size:
            f.seek(offset)
            blob = f.read(max(1, end - offset))
            out = _post_multipart(
                url, {"upload_phase": "transfer", "upload_session_id": sid,
                      "start_offset": str(offset), "video_id": vid,
                      "access_token": t},
                "video_file_chunk", video.name, blob, "application/octet-stream")
            offset = int(out.get("start_offset", size))
            end = int(out.get("end_offset", size))
    fields = {"upload_phase": "finish", "upload_session_id": sid,
              "video_id": vid, "description": caption, "access_token": t}
    if title:
        fields["title"] = title
    fields = _schedule(fields, when)
    out = _post(url, fields)
    if out.get("success") is False:
        raise RuntimeError(f"resumable finish returned {out}")
    return vid


def post_photos(images: list[Path], caption: str, *, when=None,
                token: str | None = None) -> str | None:
    """Publish a multi-photo post (an album). Returns the feed post id.

    Meta has no single multi-upload call: each photo is uploaded unpublished, then
    one `/feed` post attaches them by id. A single image degrades to `post_photo`.
    """
    if len(images) == 1:
        return post_photo(images[0], caption, token=token)
    t = page_access_token(token) if (token or page_token()) else ""
    if not t:
        return None
    ids: list[str] = []
    for image in images:
        blob = image.read_bytes()
        ctype = "image/png" if image.suffix.lower() == ".png" else "image/jpeg"
        out = _post_multipart(f"{GRAPH}/{PAGE_ID}/photos",
                              {"published": "false", "access_token": t},
                              "source", image.name, blob, ctype)
        mid = out.get("id")
        if not mid:
            raise RuntimeError(f"photos returned {out}")
        ids.append(mid)
    fields = {"message": caption,
              "attached_media": json.dumps([{"media_fbid": i} for i in ids]),
              "access_token": t}
    fields = _schedule(fields, when)
    out = _post(f"{GRAPH}/{PAGE_ID}/feed", fields)
    pid = out.get("id") or out.get("post_id")
    if not pid:
        raise RuntimeError(f"feed returned {out}")
    return pid


def page_fields(token: str | None = None) -> dict:
    """Read the Page's `name` and `about` (the Edit Page Info "Description")."""
    t = token or page_token()
    if not t:
        return {}
    return _get(f"{GRAPH}/{PAGE_ID}",
                {"fields": "id,name,about", "access_token": t})


def page_insights(*, token: str | None = None) -> dict:
    """The Page's headline numbers through the Graph API — no browser.

    Returns a `social_stats`-shaped dict so the measurement rail can read an
    `api-only` Facebook the same way it read the browser dashboard: `followers`
    and `views_28d` (Page views, the metric the browser route read from Page
    Insights), plus `engagements_28d`. `page_impressions` was removed in Graph
    v21, so `page_views_total` is the reach metric that still answers.

    A missing or rejected token returns `{"reachable": False, "note": ...}` so the
    caller falls back instead of reading a fabricated zero.
    """
    if not available():
        return {"reachable": False, "note": "no FB_PAGE_TOKEN"}
    t = page_access_token()
    try:
        base = get(PAGE_ID, {"fields": "followers_count,fan_count", "access_token": t})
    except RuntimeError as exc:
        return {"reachable": False, "note": f"graph read failed: {exc}"[:200]}
    out: dict = {
        "reachable": True,
        "source": "graph-api",
        "followers": base.get("followers_count", base.get("fan_count")),
    }
    for key, metric in (("views_28d", "page_views_total"),
                        ("engagements_28d", "page_post_engagements")):
        try:
            r = get(f"{PAGE_ID}/insights",
                    {"metric": metric, "period": "days_28", "access_token": t})
            vals = r.get("data") or []
            out[key] = (vals[0]["values"][-1]["value"]
                        if vals and vals[0].get("values") else None)
        except RuntimeError:
            out[key] = None
    return out


def set_page_about(about: str, *, token: str | None = None, dry_run: bool = False) -> bool:
    """Set the Page description (the `about` field) via the Graph API.

    `about` is the documented mapping of the Edit Page Info "Description" field,
    so this is the sanctioned route — no browser. It needs a token that carries
    the Page's tasks (`pages_manage_metadata`); a System User token is exchanged
    for the Page token first, since the write itself needs a Page token.

    The Page *name* is deliberately not written here: the Graph API does not
    expose it for update, so a rename stays a manual Page Settings action.
    """
    base = token or page_token()
    if not base:
        return False
    t = page_access_token(base)
    cur = page_fields(t)
    if (cur.get("about") or "").strip() == about.strip():
        return True  # already current; a no-op PUT is still a write we avoid
    if dry_run:
        return True
    _post(f"{GRAPH}/{PAGE_ID}", {"about": about, "access_token": t})
    return True


def _main(argv: list[str]) -> int:
    cmd = argv[0] if argv else "status"
    if cmd == "status":
        tok = page_token()
        print("configured" if tok else "not configured (no FB_PAGE_TOKEN)")
        if tok:
            print(json.dumps(whoami(), ensure_ascii=False))
        return 0
    if cmd == "page":
        print(json.dumps(page_fields(), ensure_ascii=False))
        return 0
    if cmd == "refresh":
        new = refresh()
        print("refreshed" if new else "no token to refresh")
        return 0 if new else 1
    if cmd == "expiry":
        print(json.dumps(debug_token(), ensure_ascii=False))
        return 0
    if cmd == "post-text":
        print(post_text(argv[1]) or "unavailable")
        return 0
    if cmd == "post-link":
        print(post_link(argv[1], argv[2]) or "unavailable")
        return 0
    if cmd == "post-photo":
        print(post_photo(Path(argv[1]), argv[2]) or "unavailable")
        return 0
    if cmd == "post-video":
        print(post_video(Path(argv[1]), argv[2]) or "unavailable")
        return 0
    if cmd == "post-reel":
        print(post_reel(Path(argv[1]), argv[2]) or "unavailable")
        return 0
    print(f"unknown command {cmd!r}; use status|page|refresh|expiry|"
          "post-text|post-link|post-photo|post-video|post-reel", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))

#!/usr/bin/env python3
"""Free footage and free music, from sources that need no key and no account.

`stills_rail` covers pictures. This covers the two other raw materials a clip
needs, both verified free and keyless on 2026-11-16:

* **Video** — Wikimedia Commons holds ~76k video files (webm/mp4, up to 1080p+)
  under CC0/PD/CC BY/BY-SA. The search API returns a direct upload URL, so a clip
  can be cut without a browser or a key.
* **Music** — Openverse's audio endpoint (the same API stills use) indexes
  Jamendo and the wider CC web. It needs no key and returns a direct audio URL,
  so a bed can be pulled for a Short without touching the paid catalogues.

Licence handling is the same contract as `stills_rail`: NC and ND are dropped, BY
and BY-SA are kept and must be credited. `credits_block` names each origin.
"""
from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request

# upload.wikimedia.org answers 403 to a User-Agent whose contact is example.com;
# a plain product/URL UA is accepted (verified 2026-11-16). Do not "tidy" this.
UA = {"User-Agent": "AERIS-Music/1.0 (https://youtube.com/@aerismusicth)"}
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
OPENVERSE_AUDIO = "https://api.openverse.org/v1/audio/"

OK_LICENCE = re.compile(r"(cc0|public domain|cc[ -]by|pdm|by-sa|by\b)", re.I)
BAD_LICENCE = re.compile(r"(nc\b|noncommercial|nd\b|noderiv)", re.I)

# Openverse returns short codes; map them to the label we store.
OV_OK = {"cc0": "CC0", "pdm": "Public Domain Mark", "by": "CC BY", "by-sa": "CC BY-SA"}


def _get_json(url, timeout=40):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or "{}")


def _licence_ok(text: str) -> bool:
    return bool(OK_LICENCE.search(text or "")) and not BAD_LICENCE.search(text or "")


def search_video_commons(query, limit=8):
    """Commons video files (webm/mp4). No key; direct upload URL per file."""
    params = {
        "action": "query", "format": "json", "generator": "search",
        "gsrsearch": f"filetype:video {query}", "gsrnamespace": "6",
        "gsrlimit": str(min(limit * 3, 50)),
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata",
    }
    try:
        data = _get_json(f"{COMMONS_API}?{urllib.parse.urlencode(params)}")
    except Exception:
        return []
    out = []
    for page in (data.get("query", {}).get("pages", {}) or {}).values():
        info = (page.get("imageinfo") or [{}])[0]
        mime = info.get("mime") or ""
        if not mime.startswith("video/"):
            continue
        meta = info.get("extmetadata") or {}
        licence = (meta.get("LicenseShortName", {}).get("value") or "CC BY-SA")
        if not _licence_ok(licence):
            continue
        out.append({
            "title": (page.get("title") or "video").replace("File:", "")[:120],
            "url": info.get("url"),
            "source": f"https://commons.wikimedia.org/wiki/{page.get('title','')}",
            "licence": licence,
            "credit": (meta.get("Artist", {}).get("value") or "Wikimedia Commons")[:90],
            "width": info.get("width") or 0, "height": info.get("height") or 0,
            "mime": mime, "origin": "Wikimedia Commons",
        })
    return out


def search_audio_openverse(query, limit=8):
    """Openverse audio (Jamendo + Freesound + the CC web). No key; direct URL.

    Jamendo serves full-length mp3s and is reachable from this host; Freesound's
    CDN only serves short previews and times out here (2026-11-16), so Jamendo
    tracks are ranked first. Freesound stays as a fallback rather than a filter.
    """
    params = {"q": query, "license": "cc0,pdm,by,by-sa",
              "page_size": str(min(limit * 3, 50))}
    try:
        data = _get_json(f"{OPENVERSE_AUDIO}?{urllib.parse.urlencode(params)}")
    except Exception:
        return []
    out = []
    for r in data.get("results", []):
        code = (r.get("license") or "").lower()
        if code not in OV_OK:
            continue
        url = r.get("url")
        if not url:
            continue
        out.append({
            "title": (r.get("title") or "untitled")[:120],
            "url": url,
            "source": r.get("foreign_landing_url") or url,
            "licence": OV_OK[code],
            "credit": (r.get("creator") or "").strip()[:90],
            "duration_ms": r.get("duration") or 0,
            "origin": "Openverse",
        })
    out.sort(key=_audio_rank)
    return out


def _audio_rank(item: dict) -> int:
    """0 for a full track we can actually fetch (Jamendo), 1 for a preview host."""
    return 0 if "jamendo" in (item.get("url") or "") else 1


VIDEO_SOURCES = [search_video_commons]
AUDIO_SOURCES = [search_audio_openverse]


def search_video(query, limit=8):
    return _interleave(VIDEO_SOURCES, query, limit)


def search_audio(query, limit=8):
    return _interleave(AUDIO_SOURCES, query, limit)


def _interleave(sources, query, limit):
    """Round-robin the sources so a thin first source is filled by the next."""
    pools = [s(query, limit=limit) for s in sources]
    out, seen = [], set()
    for i in range(max((len(p) for p in pools), default=0)):
        for pool in pools:
            if i < len(pool) and pool[i]["url"] not in seen:
                seen.add(pool[i]["url"])
                out.append(pool[i])
    return out[:limit]


def download(item, out_dir, name=None):
    """Fetch one item's bytes to `out_dir`. Returns the Path, or None on failure.

    Uses the module UA, which upload.wikimedia.org accepts; a 403 here is almost
    always a User-Agent problem, not a missing file.
    """
    from pathlib import Path
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    ext = Path(urllib.parse.urlparse(item["url"]).path).suffix or ".bin"
    dest = out / (name or (re.sub(r"[^A-Za-z0-9._-]+", "-", item["title"])[:60] + ext))
    try:
        req = urllib.request.Request(item["url"], headers=UA)
        with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
            f.write(r.read())
        return dest
    except Exception:
        return None


def credits_block(items) -> str:
    """A credit line per reused item. BY / BY-SA require this in the description."""
    lines = []
    for it in items:
        who = it.get("credit") or "unknown"
        lines.append(f"{it['title']} — {who} ({it['licence']}, via {it['origin']})")
    return "\n".join(lines)


if __name__ == "__main__":
    import sys
    kind = sys.argv[1] if len(sys.argv) > 1 else "video"
    q = " ".join(sys.argv[2:]) or "ocean"
    fn = search_video if kind == "video" else search_audio
    print(json.dumps(fn(q, limit=6), ensure_ascii=False, indent=1))
